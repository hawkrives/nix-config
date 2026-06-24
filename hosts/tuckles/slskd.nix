{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.slskd;
  # Regenerate slskd's config exactly as the upstream module does (filter nulls,
  # YAML), but with an API-key placeholder so the real key stays out of the
  # world-readable Nix store. A root ExecStartPre patches the key in at runtime.
  yamlFormat = pkgs.formats.yaml { };
  cleanSettings = lib.filterAttrsRecursive (
    _: v: (builtins.tryEval v).success && v != null
  ) cfg.settings;
  configTemplate = yamlFormat.generate "slskd-template.yml" cleanSettings;
in
{
  age.secrets.slskd-env.file = ../../secrets/slskd-env.age;
  age.secrets.slskd-api-key.file = ../../secrets/slskd-api-key.age;

  # slskd runs as its own user (group "slskd") but must read the NAS music
  # library to share it — those files are group "users" (gid 100) with "other"
  # denied (drwxrws--- / -rw-rw----), so without "users" slskd falls through to
  # "other" and can't read them ("File not shared" on every upload). Same shared
  # gid-100 reasoning as the *arr users in servarr.nix; NFS sec=sys passes the
  # supplementary gid through (PrivateUsers is forced off below to preserve it).
  # It also covers writing downloads into /mnt/music/soulseek/complete.
  users.users.slskd.extraGroups = [ "users" ];

  services.slskd = {
    enable = true;
    # Soulseek account creds (SLSKD_SLSK_USERNAME / SLSKD_SLSK_PASSWORD) come
    # straight from the ragenix env secret.
    environmentFile = config.age.secrets.slskd-env.path;
    openFirewall = false; # Mullvad has no inbound forward; listen_port is outbound-only.

    settings = {
      soulseek.listen_port = 50300;
      web.port = 5030;
      directories = {
        downloads = "/mnt/music/soulseek/complete"; # NFS — same fs as the Lidarr library
        incomplete = "/var/lib/slskd/incomplete"; # local VM disk
      };
      shares.directories = [ "/mnt/music/data" ]; # read-only library share
      # API-key auth for Soularr + the web UI. The key is a placeholder here
      # (this ends up in the store); the real value is injected at start.
      web.authentication.api_keys.soularr = {
        key = "@SLSKD_API_KEY@";
        role = "readwrite";
        cidr = "0.0.0.0/0,::/0";
      };
    };
  };

  systemd.services.slskd = {
    # Confine to the same Mullvad namespace qBittorrent uses (kill-switch implicit).
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
    # NB: deliberately NOT RequiresMountsFor=/mnt/music. The NFS mounts
    # idle-unmount after 5m (x-systemd.idle-timeout); a hard Requires on the
    # mount makes systemd stop slskd when that fires. Like qB/SAB, rely on the
    # automount to (re)mount /mnt/music transparently on access instead.
    restartTriggers = [
      config.age.secrets.slskd-api-key.file
      config.age.secrets.slskd-env.file
    ];
    serviceConfig = {
      # The slskd module's strict hardening conflicts with vpn-confinement + NFS:
      #   PrivateUsers -> userns remaps uid and breaks the NAS sec=sys mapping
      #   PrivateMounts -> private mount ns can't see the /mnt/music autofs
      #   RestrictNamespaces -> interferes with the netns join
      PrivateUsers = lib.mkForce false;
      PrivateMounts = lib.mkForce false;
      RestrictNamespaces = lib.mkForce false;
      RuntimeDirectory = "slskd"; # /run/slskd for the patched config
      ExecStartPre = lib.mkBefore [
        ("+" + (pkgs.writeShellScript "slskd-render-config" ''
          set -euo pipefail
          key=$(${pkgs.coreutils}/bin/cat ${config.age.secrets.slskd-api-key.path})
          ${pkgs.gnused}/bin/sed "s|@SLSKD_API_KEY@|$key|" ${configTemplate} > /run/slskd/slskd.yml
          ${pkgs.coreutils}/bin/chown ${cfg.user}:${cfg.group} /run/slskd/slskd.yml
          ${pkgs.coreutils}/bin/chmod 600 /run/slskd/slskd.yml
        ''))
      ];
      ExecStart = lib.mkForce "${cfg.package}/bin/slskd --app-dir /var/lib/slskd --config /run/slskd/slskd.yml";
    };
  };

  networking.firewall.allowedTCPPorts = [ 5030 ]; # web UI on the LAN (via the netns port-map)

  # tsnsrv embeds Tailscale, so its backend dials carry Tailscale's fwmark
  # (0x80000); the vpn-confinement netns rules drop marked packets, so tsnsrv
  # can't reach slskd directly at the netns bridge (192.168.15.1:5030 times out)
  # even though plain unmarked services (a curl, the qui app reaching qB) reach
  # it fine. Bridge it with a plain socat forwarder on localhost:5031 and point
  # the slsk tsnsrv node at that (see tsnsrv.nix).
  systemd.services.slskd-web-proxy = {
    description = "localhost:5031 -> slskd web UI in the mullvad netns (for tsnsrv)";
    after = [ "slskd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:5031,bind=127.0.0.1,fork,reuseaddr TCP4:192.168.15.1:5030";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/slskd/incomplete 0755 ${cfg.user} ${cfg.group} -"
  ];
}
