{
  lib,
  pkgs,
  config,
  synologyMount,
  ...
}: let
  # NB: `name` goes to fetchFromGitHub directly rather than wrapping the fetch
  # in `builtins.path` (as the nixpkgs plex example does) -- builtins.path has
  # to realise its argument, which makes evaluating this host an IFD that only
  # succeeds on a machine that already has the fetched output. Same store path
  # either way.
  hama = pkgs.fetchFromGitHub {
    name = "Hama.bundle";
    # https://github.com/ZeroQI/Hama.bundle
    owner = "ZeroQI";
    repo = "Hama.bundle";
    rev = "adee212b7b419790f89ed127e59e13a8e1ff63f5";
    sha256 = "PgZAqK3Ooz8JgMqCW7hZOBzuaVjCywA6ytx33J/WqC4=";
  };

  youtubeAgent = pkgs.fetchFromGitHub {
    name = "YouTube-Agent.bundle";
    # https://github.com/ZeroQI/YouTube-Agent.bundle
    owner = "ZeroQI";
    repo = "YouTube-Agent.bundle";
    rev = "e63f7a81b3493cf522a3d58276bc2ed117ed206c";
    sha256 = "W1lY9uDqxkkKmxBDewQc/BOsZSK2CbKHRBTzTscR68Y=";
  };

  absoluteSeriesScanner = pkgs.fetchFromGitHub {
    # https://github.com/ZeroQI/Absolute-Series-Scanner
    owner = "ZeroQI";
    repo = "Absolute-Series-Scanner";
    rev = "a3af601f8e127c027edc387c1e4d64927c9f25fc";
    sha256 = "BgwLzvzV4+jWePgZPOkbY2jnO4qwL8cgaTBl4R4uMRA=";
  };

  plexData = "${config.services.plex.dataDir}/Plex Media Server";

  # Preferences.xml attributes forced on every start (Plex reads the file at
  # startup and only rewrites it when a pref changes):
  #   DlnaEnabled=0 -- nothing here uses DLNA, so its listener (:32469 plus
  #                    SSDP) is just attack surface.
  #   logDebug=1    -- debug level is what logs each request with its source
  #                    address ("Request: [ip:port] GET /path"); with
  #                    PLEX_MEDIA_SERVER_USE_SYSLOG those go to the journal.
  plexPrefs = {
    DlnaEnabled = "0";
    logDebug = "1";
  };

  # Plex's FHS wrapper gives bubblewrap a fresh tmpfs for /, /etc and
  # /tmp/.X11-unix, owned by plex and exec-capable -- writable spots the
  # unit's NoExecPaths can't reach, since bwrap creates those mounts itself.
  # / and /tmp/.X11-unix are remounted read-only once everything is bound.
  # The run script's only write to the root is its /db symlink, so bwrap
  # creates that instead and the script skips it. /etc has to stay writable:
  # the FHS container-init writes /etc/ld.so.conf and ldconfig rename()s a
  # fresh /etc/ld.so.cache into place on every start.
  plexPackage = pkgs.plex.override {
    buildFHSEnv = args:
      pkgs.buildFHSEnv (args
        // {
          runScript = pkgs.runCommand "plex-run-script" {} ''
            substitute ${args.runScript} $out \
              --replace-fail 'ln -s "$db" /db' 'test -L /db || ln -s "$db" /db'
            chmod +x $out
          '';
          extraBwrapArgs = [
            "--symlink"
            "${config.services.plex.dataDir}/.skeleton/com.plexapp.plugins.library.db"
            "/db"
            "--remount-ro"
            "/"
            "--remount-ro"
            "/tmp/.X11-unix"
          ];
        });
  };
in {
  imports = [./plex-codec-watch.nix ./plex-egress-review.nix];

  services.plex = {
    enable = true;
    openFirewall = true;
    package = plexPackage;

    extraPlugins = [
      hama
      youtubeAgent
    ];

    extraScanners = [
      absoluteSeriesScanner
    ];
  };

  # TimeoutStopSec bounds how long ExecStop below waits for Plex to close its
  # library/blobs SQLite DBs (which backups.nix snapshots); a normal stop takes
  # under a second, but hard-killing Plex mid-write is how those DBs get
  # corrupted, so a slow flush gets room.
  #
  # A runaway Plex Transcoder (e.g. a background loudness-analysis job leaking
  # on a file EasyAudioEncoder can't decode) is capped at the cgroup level, so
  # the kernel OOM-kills it inside plex.service before the whole box swaps
  # itself into a global OOM. OOMPolicy=continue keeps the rest of Plex running
  # when that happens; the default (stop) tears the unit down, and the SIGQUIT
  # stop then waits out TimeoutStopSec on helpers that ignore it.
  #
  # MainPID is the bubblewrap wrapper, not Plex, and Plex is bwrap's direct
  # child under --die-with-parent. A plain KillSignal stop SIGQUITs bwrap,
  # which dies at once and takes Plex down with SIGKILL mid-shutdown, leaving
  # the library DBs' WAL un-checkpointed. So ExecStop signals only Plex and
  # waits for it to close its DBs (bounded by TimeoutStopSec). The helpers it
  # spawns (Script Host, DLNA, Tuner, EasyAudioEncoder) inherit its blocked
  # SIGINT/SIGQUIT/SIGTERM, so once Plex is gone only SIGKILL can stop them.
  systemd.services.plex.serviceConfig = {
    ExecStop = "+${pkgs.writeShellScript "plex-graceful-stop" ''
      pms=$(${pkgs.procps}/bin/pgrep -P "$MAINPID" -x "Plex Media Serv")
      [ -n "$pms" ] || exit 0
      kill -QUIT "$pms"
      while kill -0 "$pms" 2>/dev/null; do ${pkgs.coreutils}/bin/sleep 0.2; done
      for p in $(< /sys/fs/cgroup/system.slice/plex.service/cgroup.procs); do
        [ "$p" = "$MAINPID" ] || [ "$p" = "$$" ] || kill -KILL "$p" 2>/dev/null
      done
      exit 0
    ''}";
    TimeoutStopSec = "5min";
    OOMPolicy = "continue";
    MemoryMax = "8G";
    MemorySwapMax = "1G";

    # Hardening on top of the nixpkgs module's set, shaped around the
    # bubblewrap FHS env Plex runs in: bwrap needs to create user + mount
    # namespaces, call the @mount syscalls, and read /proc/sys/kernel/overflowuid
    # (so ProcSubset=pid stops it from starting).
    ProtectClock = true;
    ProtectKernelLogs = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    SystemCallArchitectures = "native";
    RemoveIPC = true;
    PrivateIPC = true;
    PrivateUsers = true;
    CapabilityBoundingSet = "";
    RestrictNamespaces = [
      "user"
      "mnt"
    ];
    SystemCallFilter = [
      "@system-service"
      "@mount"
      "~@debug @obsolete @cpu-emulation @raw-io @reboot @swap @module @clock"
    ];
    SystemCallErrorNumber = "EPERM";
    # Only the GPU (VAAPI transcoding) beyond the standard pseudo-devices.
    DevicePolicy = "closed";
    DeviceAllow = ["char-drm rw"];
    # Everything read-only except Plex's own state; transcodes go to /dev/shm
    # (TranscoderTempDirectory), which strict leaves writable. Plex only reads
    # the media shares, and allowMediaDeletion is off, so read-only /mnt costs
    # nothing — turning that pref on would need /mnt added here.
    ProtectSystem = lib.mkForce "strict";
    ReadWritePaths = ["/var/lib/plex"];
    # Nothing writable is executable, so a payload dropped into /tmp, /dev/shm
    # or the data dir can't be run. Plex downloads its codecs and VAAPI driver
    # as shared objects into Codecs/ and Drivers/, so those two stay
    # executable (and writable, for the downloads on a Plex version bump).
    # The writable paths are their own mounts (ReadWritePaths, PrivateTmp,
    # /dev/shm) and don't inherit noexec from /, so each is listed.
    NoExecPaths = [
      "/"
      "/var/lib/plex"
      "/tmp"
      "/var/tmp"
      "/dev/shm"
    ];
    ExecPaths = [
      "/nix/store"
      # Quoted: systemd splits ExecPaths= on whitespace.
      ''"${plexData}/Codecs"''
      ''"${plexData}/Drivers"''
    ];

    ExecStartPre = lib.mkAfter [
      "+${pkgs.writeShellScript "plex-enforce-prefs" ''
        prefs="${plexData}/Preferences.xml"
        [ -f "$prefs" ] || exit 0
        ${lib.concatStrings (lib.mapAttrsToList (name: value: ''
            ${pkgs.xmlstarlet}/bin/xml ed -L \
              -u '/Preferences/@${name}' -v '${value}' \
              -i '/Preferences[not(@${name})]' -t attr -n '${name}' -v '${value}' \
              "$prefs"
          '')
          plexPrefs)}
      ''}"
    ];

    # Puts this unit's cgroup into the plex_egress table's set (below).
    # systemd ignores NFTSet= table names with anything but [A-Za-z0-9_].
    NFTSet = "cgroup:inet:plex_egress:plex_cgroup";
  };

  # Outbound containment for Plex, aimed at the SSRF class of bug Plex2Shell
  # opened with: new connections Plex starts may not reach other services on
  # this host or the LAN. Plex reaching Plex is fine -- the server proxies to
  # its plug-in hosts on random loopback ports -- so loopback connections are
  # judged by the socket they land on rather than by port. Internet traffic
  # is only counted (per protocol . port in @plex_ports) and logged when it
  # isn't DNS/HTTP(S), to decide later whether a port allowlist is viable.
  #
  # plex_cgroup is filled by the unit's NFTSet= and starts empty, so with
  # Plex down or the set lost every rule here simply stops matching.
  networking.nftables.tables.plex_egress = {
    family = "inet";
    content = ''
      set plex_cgroup {
        type cgroupsv2
      }

      set plex_ports {
        type inet_proto . inet_service
        size 1024
        flags dynamic
        counter
      }

      chain output {
        type filter hook output priority filter; policy accept;
        ct state new socket cgroupv2 level 2 @plex_cgroup jump plex_new
      }

      chain plex_new {
        # Local destinations, including this host's LAN and tailnet
        # addresses, all go out lo; mark them for the check in plex_lo.
        oif "lo" ct mark set ct mark or 0x100 accept

        # GDM/SSDP/mDNS discovery.
        ip daddr { 224.0.0.0/4, 255.255.255.255, 192.168.1.255 } accept
        ip6 daddr ff00::/8 accept
        # Remote Access maps its port through the router with NAT-PMP.
        ip daddr 192.168.1.1 udp dport 5351 accept
        # Other Plex servers on the LAN (connection tests, shared libraries).
        ip daddr 192.168.1.0/24 tcp dport 32400 accept

        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 } jump plex_reject
        ip6 daddr { fc00::/7, fe80::/10 } jump plex_reject

        meta l4proto { tcp, udp } update @plex_ports { meta l4proto . th dport }
        meta l4proto { tcp, udp } th dport != { 53, 80, 443 } limit rate 30/minute log prefix "plex-egress: " level info
      }

      chain input {
        type filter hook input priority filter; policy accept;
        iif "lo" ct state new ct mark and 0x100 == 0x100 jump plex_lo
      }

      chain plex_lo {
        socket cgroupv2 level 2 @plex_cgroup accept
        meta l4proto { tcp, udp } th dport 53 accept
        jump plex_reject
      }

      chain plex_reject {
        limit rate 30/minute log prefix "plex-egress-reject: " level warn
        counter reject
      }
    '';
  };

  # The build-time `nft -c` runs in the builder's sandbox, which can't resolve
  # socket cgroupv2 matches; check the rest with a stand-in match.
  networking.nftables.preCheckRuleset = ''
    sed -i 's/socket cgroupv2 level 2 @plex_cgroup/meta mark 0x0/' ruleset.conf
  '';

  # nftables (re)loads delete and recreate every table, emptying plex_cgroup
  # until Plex next starts; put a running Plex back in.
  systemd.services.nftables.serviceConfig = let
    readdPlex = pkgs.writeShellScript "nftables-readd-plex" ''
      ${config.systemd.package}/bin/systemctl -q is-active plex.service || exit 0
      ${pkgs.nftables}/bin/nft add element inet plex_egress plex_cgroup '{ "system.slice/plex.service" }'
    '';
  in {
    ExecStartPost = lib.mkAfter ["${readdPlex}"];
    ExecReload = lib.mkAfter ["${readdPlex}"];
  };

  services.tautulli = {
    enable = true;
    openFirewall = true;

    dataDir = "/var/lib/tautulli";
  };

  # Tautulli binds IPv4-only (0.0.0.0:8181), so point tsnsrv at 127.0.0.1
  # explicitly — the default "localhost" resolves to ::1 first and the proxy
  # gets connection refused (same workaround as aurral).
  services.tsnsrv.services.tautulli.urlParts = {
    host = "127.0.0.1";
    port = config.services.tautulli.port;
  };
  services.tsnsrv.services.plex.urlParts.port = 32400;

  # Plex reads the same NAS media tree, which is group-owned by gid 100 ("users")
  # with the library dirs at 0770. Plex's own uid isn't the owner (1036), so it
  # needs gid 100 to traverse/read shows and music (movies happen to be 0777).
  # Read-only is all Plex needs; the *arr services do the writing (see servarr.nix).
  users.users.plex.extraGroups = ["users"];

  fileSystems."/var/lib/plex/media-shows" = synologyMount "/volume1/media-shows" {};
  fileSystems."/var/lib/plex/media-channels" = synologyMount "/volume1/media-channels" {};
  fileSystems."/var/lib/plex/media-music" = synologyMount "/volume1/media-music" {};
  fileSystems."/var/lib/plex/media-movies" = synologyMount "/volume1/media-movies" {};

  # Plex's Butler task backs up the library + blobs DBs here every 3 days and
  # keeps several rotations (~1.6G each), which had quietly eaten 6.3G of the
  # root SSD. Park it on the NAS instead. The Preferences key
  # (ButlerDatabaseBackupPath) still says /var/lib/plex/backup — we move the
  # mountpoint under it rather than repointing Plex, so there's no UI/API state
  # to keep in sync.
  #
  # There is no /volume1/app-plex export (that's why the old attempt here was
  # commented out), so this lives under app-servarr next to the serviceBackup
  # output. It is deliberately NOT ${serviceBackup.dest}/plex: that directory is
  # an rsync --delete target (see modules/nixos/service-backup.nix) and dropping
  # unrelated files into it invites them being reaped.
  #
  # This is complementary to the serviceBackup plex job, not redundant with it:
  # that job overwrites a single copy each night, so it has no history, whereas
  # Butler keeps dated rotations to fall back to if a corrupt DB gets backed up.
  fileSystems."/var/lib/plex/backup" =
    synologyMount "/volume1/app-servarr/plex/butler-backups"
    {};

  # need uid/gid to match the NAS
  # users.groups.servarr.gid = 1050;
  # users.users.servarr = {
  #   uid = 1036;
  #   isNormalUser = true;
  #   group = "servarr";
  #   home = "/var/lib/servarr";
  # };
}
