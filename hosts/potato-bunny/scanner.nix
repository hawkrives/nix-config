{
  lib,
  pkgs,
  flake,
  ...
}: let
  # Found through DSM's Avahi (see scannerAddress below), not a DHCP lease.
  scannerHost = "EPSON86794C.local";
  paperlessData = "/volume2/@appdata/paperless";
  consumeDir = "${paperlessData}/consume";
  # Same filesystem as consumeDir, so the final move is an atomic rename and
  # paperless never sees a partial PDF.
  stagingDir = "${paperlessData}/scan-staging";
  scanservjsData = "/volume2/@appdata/scanservjs";

  # SANE and scanservjs as the NixOS modules would set them up, with these
  # settings; the units below take their config from here.
  nixos = flake.inputs.nixpkgs.lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      {
        # Epson ET-3958, reached over eSCL/AirScan. sane-airscan speaks eSCL
        # over HTTPS, so no USB, no udev rules, and no proprietary Epson
        # driver is needed.
        hardware.sane = {
          enable = true;
          extraBackends = [pkgs.sane-airscan];
          # nixpkgs ships two eSCL backends. sane-backends' own `escl`
          # backend returns only the FRONT of each sheet in ADF Duplex mode on
          # this device, silently losing the back of every double-sided page.
          # sane-airscan handles the same scanner correctly, so remove `escl`
          # to make it impossible to select the broken one by accident. This
          # also stops `scanimage -L` dumping the printer's HTML landing page
          # to stderr, which `escl` probes on port 80.
          disabledDefaultBackends = ["escl"];
        };
        # Web UI for everything the feeder cannot do: books, passports,
        # receipts, and any scan needing non-default settings. Writes finished
        # files straight into the paperless consumption directory.
        services.scanservjs = {
          enable = true;
          settings = {
            host = "127.0.0.1";
            port = 8090;
            outputDirectory = consumeDir;
            ocrLanguage = "eng";
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = "25.11";
      }
    ];
  };
  etcSource = name: nixos.config.environment.etc.${name}.source;
  saneConfig = etcSource "sane-config";
  saneLibs = etcSource "sane-libs";
  scanservjsEnv =
    nixos.config.systemd.services.scanservjs.environment
    // {
      SANE_CONFIG_DIR = "${saneConfig}";
      LD_LIBRARY_PATH = "${saneLibs}";
    };

  # Pages whose greyscale standard deviation falls below this are treated as
  # blank and dropped. Measured on this scanner at 300dpi colour:
  #   empty scan bed (misfeed)     0.0025  <- dropped
  #   real blank paper back        0.0143  <- KEPT (see below)
  #   back of a cheque             0.0358  <- real content: watermark + endorsement
  #   normal text pages            0.117 - 0.243
  # Deliberately set below the real-blank value, so effectively only genuinely
  # empty captures are dropped. A cheque back measures just 0.0358, so the gap
  # between "blank paper" and "real but sparse content" is only ~2.5x — far too
  # narrow to split safely. Dropping a real page is data loss; keeping a blank
  # one is a minor annoyance, so this errs hard toward keeping. Consequence:
  # single-sided sheets scanned duplex deposit their blank backs into paperless.
  blankThreshold = "0.005";

  adf-scan-once = pkgs.writeShellApplication {
    name = "adf-scan-once";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.sane-backends
      pkgs.gawk
      pkgs.imagemagick
      pkgs.img2pdf
    ];
    text = ''
      # Scan everything in the ADF, drop blank pages, deposit one PDF into the
      # paperless consumption directory.
      #
      # Exit codes are a contract with adf-autoscan:
      #   0  deposited a PDF
      #   10 nothing fed (also covers the scanner being offline, since
      #      scanimage then fails and produces no pages)
      #   11 fed pages, all blank, no PDF

      work="$(mktemp -d "${stagingDir}/work.XXXXXXXX")"
      trap 'rm -rf "$work"' EXIT

      # SANE_CONFIG_DIR/LD_LIBRARY_PATH are needed by scanimage but must NOT be
      # exported process-wide: /etc/sane-libs on the search path would also
      # apply to magick and img2pdf below, which have no business loading SANE
      # backends. Scope them to scanimage via this wrapper instead.
      sane_env() { env SANE_CONFIG_DIR=${saneConfig} LD_LIBRARY_PATH=${saneLibs} "$@"; }

      # No --device-name: `escl` is disabled so exactly one SANE device exists,
      # and scanimage auto-selects it. This is deliberate, not an oversight.
      # sane-airscan's device names carry a per-process discovery index
      # (airscan:e0:, airscan:e1:, ...) that is assigned at discovery time and
      # is NOT valid in a different process — naming the device here caused
      # "open of device ... failed: Invalid argument" in testing. Letting one
      # scanimage process both discover and open avoids the race entirely.
      rc=0
      sane_env scanimage \
        --source "ADF Duplex" \
        --mode Color \
        --resolution 300 \
        --format=jpeg \
        --batch="$work/page-%04d.jpg" || rc=$?

      shopt -s nullglob
      pages=( "$work"/page-*.jpg )

      if (( ''${#pages[@]} == 0 )); then
        echo "adf-scan-once: no pages fed (scanimage rc=$rc)" >&2
        exit 10
      fi

      echo "adf-scan-once: fed ''${#pages[@]} page(s) (scanimage rc=$rc)"

      kept=()
      for p in "''${pages[@]}"; do
        sd="$(magick "$p" -colorspace Gray -format '%[fx:standard_deviation]' info:)"
        if awk -v a="$sd" -v b="${blankThreshold}" 'BEGIN { exit !(a < b) }'; then
          echo "adf-scan-once: dropping $(basename "$p") as blank (stddev=$sd < ${blankThreshold})"
        else
          echo "adf-scan-once: keeping $(basename "$p") (stddev=$sd)"
          kept+=( "$p" )
        fi
      done

      if (( ''${#kept[@]} == 0 )); then
        echo "adf-scan-once: all ''${#pages[@]} page(s) blank, no PDF produced" >&2
        exit 11
      fi

      ts="$(date +%Y%m%d-%H%M%S)"
      staged="$work/scan-$ts.pdf"
      img2pdf --output "$staged" "''${kept[@]}"

      # $work is under stagingDir, same filesystem as the consume dir, so this
      # rename is atomic and paperless can never observe a partial PDF.
      mv "$staged" "${consumeDir}/scan-$ts.pdf"
      echo "adf-scan-once: deposited scan-$ts.pdf (''${#kept[@]}/''${#pages[@]} pages kept)"
    '';
  };

  adf-autoscan = pkgs.writeShellApplication {
    name = "adf-autoscan";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.avahi
      pkgs.curl
      pkgs.gnugrep
      adf-scan-once
    ];
    text = ''
      # Poll the scanner's eSCL status endpoint and fire a scan when paper is
      # loaded into the feeder and has sat there, with the device idle, for the
      # full grace period. The grace exists so that a copy job started at the
      # panel wins the race for the paper.

      # DSM's resolver doesn't do mDNS, so each poll asks its Avahi (over
      # D-Bus) for the scanner's address; a scanner that moves keeps working.
      scanner_status_url() {
        local ip
        ip="$(avahi-resolve -4 -n ${scannerHost} 2>/dev/null | cut -f2 || true)"
        [ -n "$ip" ] && echo "https://$ip/eSCL/ScannerStatus"
      }

      idle_poll=20
      idle_grace=20
      armed_poll=5
      batch_poll=2
      batch_grace=2
      batch_window=60

      last_scan=0
      last_logged_state=""

      # Echoes "<pwg:State> <scan:AdfState>", or "ERR ERR" if unreachable.
      read_status() {
        local xml state adf url
        if ! url="$(scanner_status_url)" ||
          ! xml="$(curl -sk --max-time 10 "$url" 2>/dev/null)"; then
          echo "ERR ERR"
          return 0
        fi
        state="$(printf '%s' "$xml" | grep -o '<pwg:State>[^<]*' | cut -d'>' -f2 || true)"
        adf="$(printf '%s' "$xml" | grep -o '<scan:AdfState>[^<]*' | cut -d'>' -f2 || true)"
        echo "''${state:-ERR} ''${adf:-ERR}"
      }

      # Log only on transitions. At a 20s poll, logging every observation would
      # bury the journal in thousands of useless lines a day; this way a jam or
      # an unreachable scanner shows up exactly once, when it happens.
      log_state_change() {
        local current="$1 $2"
        if [ "$current" != "$last_logged_state" ]; then
          case "$2" in
            ScannerAdfJam)
              echo "adf-autoscan: FEEDER JAMMED (state=$1) - needs manual clearing" >&2
              ;;
            ERR)
              echo "adf-autoscan: scanner unreachable" >&2
              ;;
            *)
              echo "adf-autoscan: state=$1 adf=$2"
              ;;
          esac
          last_logged_state="$current"
        fi
      }

      # Block until the feeder stops reporting paper, so a failed scan with
      # paper still loaded cannot spin into a retry loop. A jam also satisfies
      # this (Jam != Loaded) and is reported by log_state_change.
      wait_for_feeder_clear() {
        local state adf
        while true; do
          read -r state adf <<<"$(read_status)"
          log_state_change "$state" "$adf"
          if [ "$adf" != "ScannerAdfLoaded" ]; then
            return 0
          fi
          sleep "$armed_poll"
        done
      }

      echo "adf-autoscan: watching ${scannerHost}"

      while true; do
        now="$(date +%s)"
        if (( now - last_scan < batch_window )); then
          poll="$batch_poll"
          grace="$batch_grace"
        else
          poll="$idle_poll"
          grace="$idle_grace"
        fi

        read -r state adf <<<"$(read_status)"
        log_state_change "$state" "$adf"

        if [ "$adf" != "ScannerAdfLoaded" ] || [ "$state" != "Idle" ]; then
          sleep "$poll"
          continue
        fi

        # Armed. Confirm the feeder stays loaded and the device stays idle for
        # the whole grace before committing to the scan.
        echo "adf-autoscan: paper detected, arming (grace=''${grace}s)"
        waited=0
        armed_ok=1
        while (( waited < grace )); do
          sleep "$armed_poll"
          waited=$(( waited + armed_poll ))
          read -r state adf <<<"$(read_status)"
          log_state_change "$state" "$adf"
          if [ "$adf" != "ScannerAdfLoaded" ] || [ "$state" != "Idle" ]; then
            echo "adf-autoscan: disarmed (state=$state adf=$adf)"
            armed_ok=0
            break
          fi
        done

        if (( armed_ok == 0 )); then
          # Something else claimed the device or the paper. Fall back to the
          # outer loop; the grace restarts if paper is still there.
          continue
        fi

        echo "adf-autoscan: firing scan"
        rc=0
        adf-scan-once || rc=$?
        case "$rc" in
          0 | 11)
            # Fed paper: enter or refresh the batch window.
            last_scan="$(date +%s)"
            ;;
          *)
            echo "adf-autoscan: scan fed nothing or failed (rc=$rc)" >&2
            wait_for_feeder_clear
            ;;
        esac
      done
    '';
  };
in {
  profileExtra = [adf-scan-once];

  tsnsrv.services.scan.upstream = "http://127.0.0.1:8090";

  # Both run as paperless's account, so what they deposit in its consume
  # folder is already its own. They reach the scanner over the LAN.
  systemd.units."adf-autoscan.service".text = ''
    [Unit]
    Description=Auto-scan the Epson ADF into paperless
    ConditionPathIsMountPoint=/volume2
    OnFailure=notify-failure@%n.service
    Wants=paperless-consumer.service network-online.target
    After=paperless-consumer.service network-online.target

    [Service]
    User=svc-paperless
    UMask=0022
    PermissionsStartOnly=true
    ExecStartPre=${pkgs.coreutils}/bin/install -d -o svc-paperless -m 0750 ${stagingDir}
    ExecStart=${lib.getExe adf-autoscan}
    Restart=always
    RestartSec=10
  '';

  systemd.units."scanservjs.service".text = ''
    [Unit]
    Description=scanservjs (scanning web UI)
    ConditionPathIsMountPoint=/volume2
    OnFailure=notify-failure@%n.service
    Wants=paperless-consumer.service network-online.target
    After=paperless-consumer.service network-online.target

    [Service]
    User=svc-paperless
    PermissionsStartOnly=true
    ExecStartPre=${pkgs.coreutils}/bin/install -d -o svc-paperless -m 0750 ${scanservjsData}
    ${lib.concatStrings (lib.mapAttrsToList (k: v: "Environment=\"${k}=${toString v}\"\n") scanservjsEnv)}
    # It keeps its data under the working directory.
    ExecStart=/bin/sh -c "cd ${scanservjsData} && exec ${lib.getExe pkgs.scanservjs}"
    Restart=on-failure
    RestartSec=10
  '';
}
