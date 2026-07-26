{ lib, pkgs, ... }:
let
  scannerHost = "EPSON86794C.local";
  consumeDir = "/var/lib/paperless/consume";
  stagingDir = "/var/lib/adf-autoscan";

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
      sane_env() { env SANE_CONFIG_DIR=/etc/sane-config LD_LIBRARY_PATH=/etc/sane-libs "$@"; }

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

      # $work is under /var/lib, same filesystem as the consume dir, so this
      # rename is atomic and paperless can never observe a partial PDF.
      mv "$staged" "${consumeDir}/scan-$ts.pdf"
      echo "adf-scan-once: deposited scan-$ts.pdf (''${#kept[@]}/''${#pages[@]} pages kept)"
    '';
  };

  adf-autoscan = pkgs.writeShellApplication {
    name = "adf-autoscan";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      adf-scan-once
    ];
    text = ''
      # Poll the scanner's eSCL status endpoint and fire a scan when paper is
      # loaded into the feeder and has sat there, with the device idle, for the
      # full grace period. The grace exists so that a copy job started at the
      # panel wins the race for the paper.

      status_url="https://${scannerHost}/eSCL/ScannerStatus"

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
        local xml state adf
        if ! xml="$(curl -sk --max-time 10 "$status_url" 2>/dev/null)"; then
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

      echo "adf-autoscan: watching $status_url"

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
in
{
  # Epson ET-3958, reached over eSCL/AirScan. sane-airscan speaks eSCL over
  # HTTPS, so no USB, no udev rules, and no proprietary Epson driver is needed.
  # The device is addressed by its mDNS name rather than a DHCP lease.
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan ];

    # nixpkgs ships two eSCL backends. sane-backends' own `escl` backend
    # returns only the FRONT of each sheet in ADF Duplex mode on this device,
    # silently losing the back of every double-sided page. sane-airscan handles
    # the same scanner correctly, so remove `escl` to make it impossible to
    # select the broken one by accident. This also stops `scanimage -L` dumping
    # the printer's HTML landing page to stderr, which `escl` probes on port 80.
    disabledDefaultBackends = [ "escl" ];
  };

  environment.systemPackages = [ adf-scan-once ];

  # Web UI for everything the feeder cannot do: books, passports, receipts, and
  # any scan needing non-default settings. Writes finished files straight into
  # the paperless consumption directory.
  services.scanservjs = {
    enable = true;
    settings = {
      host = "127.0.0.1";
      port = 8090;
      outputDirectory = consumeDir;
      ocrLanguage = "eng";
    };
  };

  # scanservjs runs as its own user; the consume dir is mode 777 so it can
  # write, and paperless can unlink what it did not create (no sticky bit).
  # Expose on the tailnet: https://scan.<tailnet>.ts.net -> 127.0.0.1:8090.
  # 127.0.0.1 rather than "localhost" avoids resolving to ::1 first.
  services.tsnsrv.services.scan.urlParts = {
    host = "127.0.0.1";
    port = 8090;
  };

  # Staging lives on the same filesystem as the consume dir so the final move
  # is an atomic rename rather than a copy.
  systemd.tmpfiles.rules = [
    "d ${stagingDir} 0750 paperless paperless - -"
  ];

  systemd.services.adf-autoscan = {
    description = "Auto-scan the Epson ADF into paperless";
    after = [
      "network-online.target"
      "paperless-consumer.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # No SANE environment here: adf-scan-once scopes SANE_CONFIG_DIR and
    # LD_LIBRARY_PATH to its own scanimage call, so this unit does not need
    # them and must not leak them to the whole process tree.

    serviceConfig = {
      ExecStart = lib.getExe adf-autoscan;
      Restart = "always";
      RestartSec = 10;
      User = "paperless";
      Group = "paperless";
      UMask = "0022";
      StateDirectory = "adf-autoscan";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ consumeDir ];
    };
  };
}
