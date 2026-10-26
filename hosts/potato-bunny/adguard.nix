# The LAN's second DNS server: an AdGuard Home that mirrors nutmeg's, so name
# resolution survives nutmeg rebooting or dying. Clients get both from the
# router's DHCP (set in SRM, not here).
#
#   :53 on 192.168.1.194 and 2600:2b00:9b16:6d01::194   (DNS)
#   https://ag2.vaquita-woodpecker.ts.net                (tsnsrv.nix, web UI)
#     -> 127.0.0.1:5380 adguardhome, data in /volume2/@appdata/adguardhome
#
# nutmeg's instance is the one to edit. adguardhome-sync copies its filters,
# rewrites, clients, blocked services and DNS settings here every 10 minutes;
# the query log and statistics stay per-instance. The addresses this one
# listens on are not part of what it syncs, and the pre-start pins them.
#
# Neither instance has a login (nutmeg's `users: []`); the web UIs are only
# reachable from the LAN and the tailnet.
{
  pkgs,
  perSystem,
  ...
}: let
  data = "/volume2/@appdata/adguardhome";
  conf = "${data}/AdGuardHome.yaml";
  origin = "http://192.168.1.228:5380";
  # The addresses the router's DHCP and router advertisements name as the
  # LAN's second DNS server. ::194 mirrors .194 the way nutmeg's ::228 mirrors
  # .228; SLAAC only gives the NAS its EUI-64 address, so nix-lan-dns-address
  # adds it. It is inside 2600:2b00:9b16:6d01::/64, which the ISP delegates:
  # if that rotates, this and the router setting both need the new prefix.
  dnsV6 = "2600:2b00:9b16:6d01::194";
  bindHosts = ["192.168.1.194" dnsV6];

  # AdGuard rewrites its own config, so the parts that belong to this host are
  # set on every start. A first start gets just these and the sync fills in the
  # rest.
  preStart = pkgs.writeShellScript "adguardhome-pre-start" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/install -d -m 0700 ${data}
    [ -f ${conf} ] || echo "schema_version: 34" > ${conf}
    ${pkgs.yq-go}/bin/yq -i '
      .http.address = "127.0.0.1:5380" |
      .users = [] |
      .dns.bind_hosts = ${builtins.toJSON bindHosts} |
      .dns.port = 53
    ' ${conf}
  '';
in {
  tsnsrv.services.ag2.upstream = "http://127.0.0.1:5380";

  systemd.units."nix-lan-dns-address.service".text = ''
    [Unit]
    Description=The LAN DNS address ${dnsV6} on ovs_eth0
    OnFailure=notify-failure@%n.service
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=${pkgs.iproute2}/bin/ip -6 addr replace ${dnsV6}/128 dev ovs_eth0 nodad
    ExecStop=${pkgs.iproute2}/bin/ip -6 addr del ${dnsV6}/128 dev ovs_eth0
  '';

  # Root: it binds :53.
  systemd.units."adguardhome.service".text = ''
    [Unit]
    Description=AdGuard Home (LAN DNS, mirrors nutmeg)
    ConditionPathIsMountPoint=/volume2
    OnFailure=notify-failure@%n.service
    After=network-online.target
    Wants=network-online.target
    Wants=nix-lan-dns-address.service
    After=nix-lan-dns-address.service

    [Service]
    ExecStartPre=${preStart}
    ExecStart=${pkgs.adguardhome}/bin/AdGuardHome --no-check-update --work-dir ${data} --config ${conf}
    Restart=on-failure
    RestartSec=5
  '';

  # One pass per run; the timer drives it. No DHCP (nutmeg serves none) and no
  # TLS settings (neither uses AdGuard's TLS).
  systemd.units."adguardhome-sync.service" = {
    wantedBy = [];
    text = ''
      [Unit]
      Description=Copy nutmeg's AdGuard settings to this one
      Wants=adguardhome.service
      After=adguardhome.service network-online.target

      [Service]
      Type=oneshot
      User=nobody
      ExecStart=${perSystem.self.adguardhome-sync}/bin/adguardhome-sync run --api-port 0 --origin-url ${origin} --replica-url http://127.0.0.1:5380 --feature-dhcp-server-config=false --feature-dhcp-static-leases=false --feature-tls-config=false
    '';
  };
  systemd.units."adguardhome-sync.timer" = {
    wantedBy = ["timers.target"];
    text = ''
      [Unit]
      Description=Copy nutmeg's AdGuard settings to this one, every 10 minutes

      [Timer]
      OnBootSec=2min
      OnUnitActiveSec=10min
    '';
  };
}
