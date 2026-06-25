{
  pkgs,
  config,
  ...
}:
let
  py = pkgs.python3Packages;

  # music-tag and slskd-api aren't in nixpkgs; build them from PyPI.
  music-tag = py.buildPythonPackage {
    pname = "music-tag";
    version = "0.4.3";
    pyproject = true;
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/fc/f4/ebcdd2fc9bfaf569b795250090e4f4088dc65a5a3e32c53baa9bfc3fc296/music-tag-0.4.3.tar.gz";
      hash = "sha256-Cqtubu2o3w9TFuwtIZC9dFYbfgNWKrCRzo1Wh828//Y=";
    };
    build-system = [ py.setuptools ];
    propagatedBuildInputs = [ py.mutagen ];
    doCheck = false;
  };

  slskd-api = py.buildPythonPackage {
    pname = "slskd-api";
    version = "0.1.5";
    # Use the prebuilt wheel — the sdist build needs setuptools-git-versioning.
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/83/d8/4f06e30ca269ce08076fa42b62727a6c6c8983b28aa9028e51221eeb92a0/slskd_api-0.1.5-py3-none-any.whl";
      hash = "sha256-3gPCGgtfK2MW+NvycMaFkIW/VS6B7WAkqxkvUdRWpMA=";
    };
    propagatedBuildInputs = [ py.requests ];
    doCheck = false;
  };

  soularr = pkgs.stdenvNoCC.mkDerivation {
    pname = "soularr";
    version = "0-unstable-2026-06-21";
    src = pkgs.fetchFromGitHub {
      owner = "mrusse";
      repo = "soularr";
      rev = "f9e0ab922fd928a6d5d39cc9ddc0b0734006ddac";
      hash = "sha256-gtz99+DiFjJZuq54qo5C+5Exx++S+ePzldgDM9NHAOA=";
    };
    # Romaji-search patch: for CJK albums, also search Soulseek with the
    # Latin/romaji alias pulled from the MusicBrainz API (artist/release-group
    # foreign IDs Lidarr already provides). Search augmentation only — matching is
    # unchanged. Toggled by [Search Settings] romaji_search (default true).
    patches = [ ./soularr-romaji.patch ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    pythonEnv = pkgs.python3.withPackages (_: [
      music-tag
      slskd-api
      py.pyarr
      py.flask
      py.waitress
      py.requests # used by the romaji patch's MusicBrainz lookups
    ]);
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/soularr $out/bin
      cp soularr.py $out/share/soularr/soularr.py
      makeWrapper $pythonEnv/bin/python $out/bin/soularr \
        --add-flags "$out/share/soularr/soularr.py"
      runHook postInstall
    '';
  };

  # config.ini template — secrets are placeholders here (store-safe); the real
  # Lidarr + slskd keys are sed'd in at start from systemd credentials.
  # allowed_filetypes = flac,mp3 320  →  FLAC preferred, 320 kbps MP3 fallback.
  configTemplate = pkgs.writeText "soularr-config.ini" ''
    [Lidarr]
    api_key = @LIDARR_KEY@
    host_url = http://localhost:8686
    download_dir = /mnt/music/soulseek/complete
    disable_sync = False

    [Slskd]
    api_key = @SLSKD_KEY@
    host_url = http://192.168.1.66:5030
    url_base = /
    download_dir = /mnt/music/soulseek/complete
    delete_searches = False
    stalled_timeout = 3600
    remote_queue_timeout = 300

    [Release Settings]
    use_selected_lidarr_release = False
    use_most_common_tracknum = True
    allow_multi_disc = True
    accepted_countries = Europe,Japan,United Kingdom,United States,[Worldwide],Australia,Canada
    skip_region_check = False
    accepted_formats = CD,Digital Media,Vinyl

    [Search Settings]
    search_timeout = 10000
    maximum_peer_queue = 50
    minimum_peer_upload_speed = 0
    minimum_filename_match_ratio = 0.8
    minimum_search_interval = 10
    allowed_filetypes = flac,mp3 320
    album_prepend_artist = False
    search_type = incrementing_page
    number_of_albums_to_grab = 8
    search_source = missing
    failed_import_denylist = True
    romaji_search = True

    [Download Settings]
    download_filtering = True
    use_extension_whitelist = False
    extensions_whitelist = lrc,nfo,txt
  '';
in
{
  age.secrets.slskd-api-key.file = ../../secrets/slskd-api-key.age;
  # lidarr-api-key.age is declared in servarr.nix.

  systemd.services.soularr = {
    description = "Soularr — drive slskd (Soulseek) from Lidarr's wanted list";
    # Pull the music mount up at start (for ReadWritePaths) and order after it,
    # but with Wants/After — NOT RequiresMountsFor. A run can exceed the NFS 5m
    # idle-unmount (the search phase doesn't touch /mnt), and a hard Requires
    # would make systemd kill soularr when the mount idle-unmounts (it did: a
    # 6.5m CJK-churning run got SIGTERM'd). Wants doesn't propagate the stop.
    after = [
      "network-online.target"
      "mnt-music.mount"
    ];
    wants = [
      "network-online.target"
      "mnt-music.mount"
    ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "soularr";
      WorkingDirectory = "/var/lib/soularr";
      # DynamicUser implies ProtectSystem=strict (so /mnt is read-only) — carve
      # out the download dir. And gid 100 ("users") to write the setgid 1036:100
      # tree, so the files Lidarr later hardlink-imports inherit the shared group.
      ReadWritePaths = [ "/mnt/music/soulseek/complete" ];
      SupplementaryGroups = [ "users" ];
      # soularr builds its own "Artist - Album (Year)" temp folder (os.mkdir) and
      # moves the downloaded tracks into it before triggering Lidarr's import.
      # Lidarr's import is move-mode: it hardlinks each track into the library and
      # then DeleteFile()s the source — which needs group-write on *this* folder.
      # The default UMask=0022 makes it drwxr-sr-x (no group-write), so the delete
      # fails with "Permission denied"; Lidarr then drops the track (no DB row)
      # even though the library copy already landed, and soularr files the album
      # under failed_imports. 0007 makes the temp folder group-writable from
      # creation — same fix and reasoning as slskd's UMask (see tuckles/slskd.nix).
      UMask = "0007";
      # Both keys exposed to the (non-root) service via systemd credentials.
      LoadCredential = [
        "lidarr-key:${config.age.secrets.lidarr-api-key.path}"
        "slskd-key:${config.age.secrets.slskd-api-key.path}"
      ];
      ExecStartPre = pkgs.writeShellScript "soularr-render-config" ''
        set -euo pipefail
        lk=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' "$CREDENTIALS_DIRECTORY/lidarr-key")
        sk=$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/slskd-key")
        ${pkgs.gnused}/bin/sed -e "s|@LIDARR_KEY@|$lk|" -e "s|@SLSKD_KEY@|$sk|" \
          ${configTemplate} > /var/lib/soularr/config.ini
        ${pkgs.coreutils}/bin/chmod 600 /var/lib/soularr/config.ini
      '';
      # --no-lock-file: systemd already serializes oneshot runs, and soularr's own
      # lock file is left stale if a run is SIGTERM'd (e.g. by an idle-unmount),
      # which then silently exits every subsequent run with code 1.
      ExecStart = "${soularr}/bin/soularr --config-dir /var/lib/soularr --var-dir /var/lib/soularr --no-lock-file";
    };
  };

  systemd.timers.soularr = {
    description = "Run Soularr hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };
}
