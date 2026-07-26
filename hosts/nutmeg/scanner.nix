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

  # Staging lives on the same filesystem as the consume dir so the final move
  # is an atomic rename rather than a copy.
  systemd.tmpfiles.rules = [
    "d ${stagingDir} 0750 paperless paperless - -"
  ];
}
