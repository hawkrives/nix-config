# Tailscale, from nixpkgs, in place of the Synology package (which stays
# installed but stopped, as the fallback: see below). The node keeps its
# identity and tailnet IP (100.111.251.156): on first start the unit copies
# the package's state over.
#
# Behaviour kept from the package: the same port (41641) and interface
# (tailscale0), the exit-node and accept-routes prefs (they live in the
# state), and MagicDNS off on this host — DSM's resolv.conf points at the LAN
# resolver, and a root tailscaled with accept-dns would rewrite it. The
# kernel (4.4) has no nftables, so the firewall mode is iptables (DSM's
# legacy iptables on PATH).
#
# Fallback to the package, by hand: `systemctl stop nix-tailscaled`, copy
# /volume2/@appdata/nix-tailscale/tailscaled.state back over the package's
# (owned tailscale:tailscale), set dsm.services.tailscale.enable = true and
# drop this import, deploy.
{pkgs, ...}: let
  ts = pkgs.tailscale;
  # On a Synology the CLI looks for the package's socket by default, so every
  # caller (root's PATH included) goes through this.
  cli = pkgs.writeShellScriptBin "tailscale" ''
    exec ${ts}/bin/tailscale --socket=/run/tailscale/tailscaled.sock "$@"
  '';
  stateDir = "/volume2/@appdata/nix-tailscale";

  preStart = pkgs.writeShellScript "nix-tailscaled-pre-start" ''
    set -euo pipefail
    # The package's boot task used to load these; VMM usually has already.
    /sbin/modprobe tun 2>/dev/null || true
    if [ ! -e /dev/net/tun ]; then
      mkdir -p /dev/net
      mknod /dev/net/tun c 10 200
    fi
    PATH=${pkgs.coreutils}/bin:${pkgs.findutils}/bin \
      ${pkgs.bash}/bin/bash ${./tailscale-migrate.sh} /volume2/@appdata/Tailscale ${stateDir}
  '';

  postStart = pkgs.writeShellScript "nix-tailscaled-post-start" ''
    set -euo pipefail
    for _ in $(${pkgs.coreutils}/bin/seq 60); do
      ${cli}/bin/tailscale status >/dev/null 2>&1 && break
      ${pkgs.coreutils}/bin/sleep 0.5
    done
    ${cli}/bin/tailscale set --accept-dns=false
  '';
in {
  dsm.services.tailscale.enable = false;
  profileExtra = [cli];

  # The exit node's IPv6 side (::/0 is advertised); IPv4 forwarding is DSM's,
  # already on for its VMs and containers.
  systemd.units."nix-ipv6-forwarding.service".text = ''
    [Unit]
    Description=IPv6 forwarding for the Tailscale exit node
    Before=nix-tailscaled.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=${pkgs.bash}/bin/bash ${./ipv6-forwarding.sh} on
    ExecStop=${pkgs.bash}/bin/bash ${./ipv6-forwarding.sh} off
  '';

  systemd.units."nix-tailscaled.service".text = ''
    [Unit]
    Description=Tailscale (nixpkgs)
    Conflicts=pkgctl-Tailscale.service
    Wants=nix-ipv6-forwarding.service
    After=pkgctl-Tailscale.service nix-ipv6-forwarding.service network-online.target
    Wants=network-online.target
    RequiresMountsFor=/volume2
    OnFailure=notify-failure@%n.service

    [Service]
    Environment=PATH=/usr/sbin:/usr/bin:/sbin:/bin
    Environment=TS_DEBUG_FIREWALL_MODE=iptables
    RuntimeDirectory=tailscale
    ExecStartPre=${preStart}
    ExecStart=${ts}/bin/tailscaled --state=${stateDir}/tailscaled.state --statedir=${stateDir} --socket=/run/tailscale/tailscaled.sock --port=41641 --tun=tailscale0
    ExecStartPost=${postStart}
    ExecStopPost=${ts}/bin/tailscaled --cleanup
    Restart=on-failure
    RestartSec=5
  '';
}
