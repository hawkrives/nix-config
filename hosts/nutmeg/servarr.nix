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
  services.tsnsrv.services.radarr-nm.urlParts.port = config.services.radarr.settings.server.port;

  # ── Sonarr (:8989) ────────────────────────────────────────────────
  services.sonarr = apiKey "sonarr" // {
    enable = true;
  };
  services.tsnsrv.services.sonarr-nm.urlParts.port = config.services.sonarr.settings.server.port;

  # ── Prowlarr (:9696) ——————————————————————————————————————————————
  services.prowlarr = apiKey "prowlarr" // {
    enable = true;
  };
  services.tsnsrv.services.prowlarr-nm.urlParts.port = config.services.prowlarr.settings.server.port;

  # ── Lidarr (:8686) ────────────────────────────────────────────────
  services.lidarr = apiKey "lidarr" // {
    enable = true;
  };
  services.tsnsrv.services.lidarr-nm.urlParts.port = config.services.lidarr.settings.server.port;

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
  services.tsnsrv.services.bazarr-nm.urlParts.port = config.services.bazarr.listenPort;

  # Bazarr has no declarative-config option (it owns config.yaml at runtime), but
  # the one thing we *do* want pinned — its link to radarr/sonarr, including the
  # API keys — are secrets that belong in ragenix. Inject them (plus loopback) on
  # every start with a YAML-aware edit, so the connection lives in git and the
  # keys never sit in plaintext. Everything else in config.yaml stays runtime-
  # managed. Runs as root ('+') to read the root-owned secrets, then hands the
  # file back to bazarr. No-ops until bazarr has created the radarr/sonarr
  # sections, so it enforces rather than bootstraps.
  systemd.services.bazarr.serviceConfig.ExecStartPre =
    let
      pin = pkgs.writeShellScript "bazarr-pin-arr" ''
        set -euo pipefail
        cfg=${config.services.bazarr.dataDir}/config/config.yaml
        [ -f "$cfg" ] || exit 0
        ${pkgs.yq-go}/bin/yq -e '.radarr and .sonarr' "$cfg" >/dev/null 2>&1 || exit 0
        rkey=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' ${config.age.secrets.radarr-api-key.path})
        skey=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' ${config.age.secrets.sonarr-api-key.path})
        RKEY="$rkey" SKEY="$skey" ${pkgs.yq-go}/bin/yq -i '
            .radarr.ip = "127.0.0.1" | .radarr.apikey = strenv(RKEY)
          | .sonarr.ip = "127.0.0.1" | .sonarr.apikey = strenv(SKEY)
        ' "$cfg"
        ${pkgs.coreutils}/bin/chown ${config.services.bazarr.user}:${config.services.bazarr.group} "$cfg"
      '';
    in
    [ "+${pin}" ];

  # ── Overseerr (:5055) —────────────────────────────────────────────
  services.overseerr = {
    enable = true;
    openFirewall = true;
  };
  services.tsnsrv.services.seerr-nm.urlParts.port = config.services.overseerr.port;

  # Same idea as bazarr: overseerr owns settings.json at runtime (no declarative
  # config option), but its radarr/sonarr API keys are secrets that belong in
  # ragenix. Pin the *arr connections (+ loopback for plex) on every start. It's
  # DynamicUser, so the file is owned by a dynamic uid under /var/lib/private —
  # we run as root ('+') to read the secrets and rewrite the file in place
  # (truncate-in-place via cat keeps the dynamic-uid ownership). No-ops until the
  # servers exist, so it enforces rather than bootstraps. The plex *token* is
  # still a runtime OAuth thing (the 401 watchlist error) — not managed here.
  systemd.services.overseerr.serviceConfig.ExecStartPre =
    let
      pin = pkgs.writeShellScript "overseerr-pin-arr" ''
        set -euo pipefail
        cfg=/var/lib/overseerr/settings.json
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
