{
  lib,
  pkgs,
  config,
  synologyMount,
  ...
}:
let
  servarrApp = {
    # enable = true;
    openFirewall = true;

    settings.log.dbEnabled = false; # avoid writing logs to the database
    settings.auth.method = "External"; # disable auth requirement
    settings.update.mechanism = "external"; # disable builtin update process
  };

  # Each app's API key lives in a ragenix secret (secrets/<app>-api-key.age) as
  # an environment file with a single <APP>__AUTH__APIKEY=… line, decrypted to
  # /run/agenix/<app>-api-key. systemd reads EnvironmentFile= as root before
  # dropping to the service user, so the secret stays root-owned (the default).
  # The env var overrides the <ApiKey> in the app's config.xml at startup.
  apiKey =
    app:
    servarrApp
    // {
      environmentFiles = [ config.age.secrets."${app}-api-key".path ];
    };
in
{
  # The NAS media tree is owned by the old stack's shared identity (uid 1036,
  # gid 100 = "users") with group-write on the library dirs. Our per-app service
  # users each live only in their own group, so they can't write to the shared
  # media over NFS (NFS sec=sys passes uid/gid through). Add them to "users"
  # (gid 100) so they inherit the group-write the NAS already grants. radarr
  # only worked by luck (/mnt/movies happens to be 0777); shows/music are 0770.
  users.users.sonarr.extraGroups = [ "users" ];
  users.users.radarr.extraGroups = [ "users" ];
  users.users.lidarr.extraGroups = [ "users" ];
  # bazarr writes sidecar subtitles next to the media in /mnt/{shows,movies},
  # so it needs the same group-write access as the *arr that own those trees.
  users.users.bazarr.extraGroups = [ "users" ];

  # …but group membership is only half of it: the shared model also needs every
  # file/dir these services create to carry the group-write bit, so the *next*
  # service user can write it (e.g. beets retagging a track Lidarr just imported,
  # or Lidarr creating an album folder under an artist dir). systemd's default
  # UMask=0022 strips group-write, producing drwxr-s--- / -rw-r----- under the
  # media tree — which silently breaks imports into freshly created folders and
  # blocks beets-sync from rewriting tags. 0007 reproduces the tree's existing
  # drwxrws--- / -rw-rw---- (group-write, "other" denied) for everything new.
  # mkForce: the upstream servarr modules pin UMask = "0022" directly (no
  # mkDefault), so a plain assignment conflicts at eval — override it outright.
  systemd.services.lidarr.serviceConfig.UMask = lib.mkForce "0007";
  systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0007";
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0007";
  systemd.services.bazarr.serviceConfig.UMask = lib.mkForce "0007";

  fileSystems."/mnt/photos" = synologyMount "/volume1/media-photos" { readOnly = true; };
  fileSystems."/mnt/shows" = synologyMount "/volume1/media-shows" { };
  fileSystems."/mnt/channels" = synologyMount "/volume1/media-channels" { };
  fileSystems."/mnt/music" = synologyMount "/volume1/media-music" { };
  fileSystems."/mnt/movies" = synologyMount "/volume1/media-movies" { };

  fileSystems."/var/lib/lidarr/.config/Lidarr/MediaCover" =
    synologyMount "/volume1/app-servarr/lidarr/MediaCover"
      { };
  fileSystems."/var/lib/lidarr/.config/Lidarr/Backups" =
    synologyMount "/volume1/app-servarr/lidarr/Backups"
      { };

  fileSystems."/var/lib/radarr/.config/Radarr/MediaCover" =
    synologyMount "/volume1/app-servarr/radarr/MediaCover"
      { };
  fileSystems."/var/lib/radarr/.config/Radarr/Backups" =
    synologyMount "/volume1/app-servarr/radarr/Backups"
      { };
  fileSystems."/var/lib/sonarr/.config/NzbDrone/MediaCover" =
    synologyMount "/volume1/app-servarr/sonarr/MediaCover"
      { };
  fileSystems."/var/lib/sonarr/.config/NzbDrone/Backups" =
    synologyMount "/volume1/app-servarr/sonarr/Backups"
      { };

  fileSystems."/mnt/servarr" = synologyMount "/volume1/app-servarr" { };

  age.secrets.radarr-api-key.file = ../../secrets/radarr-api-key.age;
  age.secrets.sonarr-api-key.file = ../../secrets/sonarr-api-key.age;
  age.secrets.prowlarr-api-key.file = ../../secrets/prowlarr-api-key.age;
  age.secrets.lidarr-api-key.file = ../../secrets/lidarr-api-key.age;

  # ── Radarr (:7878) ────────────────────────────────────────────────
  services.radarr = apiKey "radarr" // {
    enable = true;
  };
  services.tsnsrv.services.radarr.urlParts.port = config.services.radarr.settings.server.port;

  # ── Sonarr (:8989) ────────────────────────────────────────────────
  services.sonarr = apiKey "sonarr" // {
    enable = true;
  };
  services.tsnsrv.services.sonarr.urlParts.port = config.services.sonarr.settings.server.port;

  # ── Prowlarr (:9696) ——————————————————————————————————————————————
  services.prowlarr = apiKey "prowlarr" // {
    enable = true;
  };
  services.tsnsrv.services.prowlarr.urlParts.port = config.services.prowlarr.settings.server.port;

  # ── Lidarr (:8686) ────────────────────────────────────────────────
  services.lidarr = apiKey "lidarr" // {
    enable = true;
  };
  services.tsnsrv.services.lidarr.urlParts.port = config.services.lidarr.settings.server.port;

  # ── Daily *arr backup enforcement ─────────────────────────────────
  # Each app's "Backup Interval" is set to 1 day (daily scheduled backups,
  # auto-pruned by its own retention). But that interval lives in the app's
  # SQLite DB — exactly the kind of stateful setting that drifted and lost the
  # Lidarr track-naming formats. This daily timer re-pins backupInterval=1 via
  # each API so the daily-backup behaviour can't silently regress. Same "enforce
  # a runtime-managed setting on a schedule" idea as the bazarr/seerr pins below.
  #
  # We re-pin the interval rather than POSTing the Backup command directly:
  # command-triggered backups are stored as type "Manual", which the *arr never
  # prune by retention — daily manual backups would grow the NAS Backups/ dirs
  # unbounded (Lidarr's are ~190 MB each). Pinning lets the app's own scheduler
  # create and prune the daily backups. Runs as root to read /run/agenix keys.
  systemd.services.arr-backup-pin = {
    description = "Re-assert daily backup interval (backupInterval=1) on each *arr";
    after = [ "network.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -u
      pin() { # name port apiver keyfile
        local name=$1 port=$2 ver=$3 key base cur body
        key=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' "$4")
        base="http://localhost:$port/api/$ver/config/host"
        cur=$(${pkgs.curl}/bin/curl -fsSL -H "X-Api-Key: $key" "$base") || { echo "$name: GET failed"; return; }
        body=$(${pkgs.jq}/bin/jq '.backupInterval = 1' <<<"$cur")
        ${pkgs.curl}/bin/curl -fsSL -X PUT -H "X-Api-Key: $key" -H "Content-Type: application/json" \
          -d "$body" "$base" >/dev/null && echo "$name: backupInterval pinned to 1" || echo "$name: PUT failed"
      }
      pin radarr   ${toString config.services.radarr.settings.server.port}   v3 ${config.age.secrets.radarr-api-key.path}
      pin sonarr   ${toString config.services.sonarr.settings.server.port}   v3 ${config.age.secrets.sonarr-api-key.path}
      pin prowlarr ${toString config.services.prowlarr.settings.server.port} v1 ${config.age.secrets.prowlarr-api-key.path}
      pin lidarr   ${toString config.services.lidarr.settings.server.port}   v1 ${config.age.secrets.lidarr-api-key.path}
    '';
  };
  systemd.timers.arr-backup-pin = {
    description = "Daily: re-assert *arr backup interval";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "20m";
    };
  };

  # ── Recyclarr ─────────────────────────────────────────────────────
  # services.recyclarr.enable = true;

  # ── FlareSolverr (:8191) —─────────────────────────────────────────
  services.flaresolverr = {
    # enable = true;
    # openFirewall = true;
  };

  # ── Bazarr (:6767) ────────────────────────────────────────────────
  services.bazarr = {
    enable = true;
    openFirewall = true;
  };
  services.tsnsrv.services.bazarr.urlParts.port = config.services.bazarr.listenPort;

  # Bazarr has no declarative-config option (it owns config.yaml at runtime), so
  # we enforce two things on every start with YAML-aware edits:
  #
  #   1. general.ip = "::" — bind dual-stack so tsnsrv can reach it. The NixOS
  #      module passes only --port, so the listen address comes from config.yaml,
  #      which defaults to 0.0.0.0 (IPv4-only). tsnsrv's default "localhost"
  #      upstream resolves to ::1 first and gets connection refused. Binding ::
  #      (with net.ipv6.bindv6only=0) accepts both IPv6 and IPv4-mapped, so
  #      [::1]:6767 works — a real fix rather than the 127.0.0.1 tsnsrv pin used
  #      for tautulli/jellyfin/aurral (which lack an equivalent bind knob).
  #
  #   2. the radarr/sonarr link + API keys — secrets that belong in ragenix.
  #      Injecting them here keeps the connection in git while the keys never sit
  #      in plaintext. No-ops until bazarr has created those sections.
  #
  # Runs as root ('+') to read the root-owned secrets, then hands the file back
  # to bazarr. Enforces rather than bootstraps (skips if config.yaml is absent).
  systemd.services.bazarr.serviceConfig.ExecStartPre =
    let
      pin = pkgs.writeShellScript "bazarr-pin" ''
        set -euo pipefail
        cfg=${config.services.bazarr.dataDir}/config/config.yaml
        [ -f "$cfg" ] || exit 0
        ${pkgs.yq-go}/bin/yq -i '.general.ip = "::"' "$cfg"
        if ${pkgs.yq-go}/bin/yq -e '.radarr and .sonarr' "$cfg" >/dev/null 2>&1; then
          rkey=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' ${config.age.secrets.radarr-api-key.path})
          skey=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' ${config.age.secrets.sonarr-api-key.path})
          RKEY="$rkey" SKEY="$skey" ${pkgs.yq-go}/bin/yq -i '
              .radarr.ip = "127.0.0.1" | .radarr.apikey = strenv(RKEY)
            | .sonarr.ip = "127.0.0.1" | .sonarr.apikey = strenv(SKEY)
          ' "$cfg"
        fi
        ${pkgs.coreutils}/bin/chown ${config.services.bazarr.user}:${config.services.bazarr.group} "$cfg"
      '';
    in
    [ "+${pin}" ];

  # ── Seerr (:5055) ─────────────────────────────────────────────────
  # Seerr (formerly Jellyseerr) — an actively-maintained Overseerr fork that adds
  # Jellyfin/Emby while keeping full Plex support. Migrated from overseerr: its
  # DB + settings.json share Overseerr's schema, so the old data was copied into
  # /var/lib/seerr and Seerr migrates it forward. `services.jellyseerr` is a
  # renamed-option alias for `services.seerr`.
  services.seerr = {
    enable = true;
    openFirewall = true;
  };
  services.tsnsrv.services.seerr.urlParts.port = config.services.seerr.port;

  # Same idea as bazarr: seerr owns settings.json at runtime (no declarative
  # config option), but its radarr/sonarr API keys are secrets that belong in
  # ragenix. Pin the *arr connections (+ loopback for plex) on every start. It's
  # DynamicUser, so the file is owned by a dynamic uid under /var/lib/private —
  # we run as root ('+') to read the secrets and rewrite the file in place
  # (truncate-in-place via cat keeps the dynamic-uid ownership). No-ops until the
  # servers exist, so it enforces rather than bootstraps. The plex *token* is
  # still a runtime OAuth thing (signed in via the UI) — not managed here.
  systemd.services.seerr.serviceConfig.ExecStartPre =
    let
      pin = pkgs.writeShellScript "seerr-pin-arr" ''
        set -euo pipefail
        cfg=${config.services.seerr.configDir}/settings.json
        [ -f "$cfg" ] || exit 0
        ${pkgs.jq}/bin/jq -e '(.radarr | length > 0) and (.sonarr | length > 0)' "$cfg" >/dev/null 2>&1 || exit 0
        rkey=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' ${config.age.secrets.radarr-api-key.path})
        skey=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' ${config.age.secrets.sonarr-api-key.path})
        tmp=$(${pkgs.coreutils}/bin/mktemp)
        ${pkgs.jq}/bin/jq --arg rk "$rkey" --arg sk "$skey" '
            .plex.ip = "127.0.0.1"
          | .radarr[0].hostname = "127.0.0.1" | .radarr[0].apiKey = $rk
          | .sonarr[0].hostname = "127.0.0.1" | .sonarr[0].apiKey = $sk
        ' "$cfg" > "$tmp"
        ${pkgs.coreutils}/bin/cat "$tmp" > "$cfg"
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      '';
    in
    [ "+${pin}" ];
}
