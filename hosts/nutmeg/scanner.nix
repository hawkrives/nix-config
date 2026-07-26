{ lib, pkgs, ... }:
let
  scannerHost = "EPSON86794C.local";
  device = "escl:https://${scannerHost}:443";
  consumeDir = "/var/lib/paperless/consume";
  stagingDir = "/var/lib/adf-autoscan";

  # Pages whose greyscale standard deviation falls below this are treated as
  # blank and dropped. Calibrated against a real blank feeder page in Task 4;
  # see the plan for the measurement procedure before changing it.
  blankThreshold = "0.06";

  adf-scan-once = pkgs.writeShellApplication {
    name = "adf-scan-once";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.sane-backends
      pkgs.imagemagick
      pkgs.img2pdf
    ];
    text = ''
      # Scan everything in the ADF, drop blank pages, deposit one PDF into the
      # paperless consumption directory.
      #
      # Exit codes are a contract with adf-autoscan:
      #   0  deposited a PDF
      #   10 nothing fed
      #   11 fed pages, all blank, no PDF

      work="$(mktemp -d "${stagingDir}/work.XXXXXXXX")"
      trap 'rm -rf "$work"' EXIT

      # scanimage --batch always exits non-zero when the feeder empties, so its
      # status is logged but never used to decide success.
      # SANE_CONFIG_DIR/LD_LIBRARY_PATH are scoped to this one command rather
      # than exported. hardware.sane only exports them as sessionVariables,
      # which systemd units do not inherit, but exporting them process-wide
      # would also put /etc/sane-libs on the search path for magick and
      # img2pdf below, which have no business loading SANE backends.
      rc=0
      SANE_CONFIG_DIR=/etc/sane-config \
      LD_LIBRARY_PATH=/etc/sane-libs \
      scanimage \
        --device-name "${device}" \
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
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan ];
  };

  environment.systemPackages = [ adf-scan-once ];

  # Staging lives on the same filesystem as the consume dir so the final move
  # is an atomic rename rather than a copy.
  systemd.tmpfiles.rules = [
    "d ${stagingDir} 0750 paperless paperless - -"
  ];
}
