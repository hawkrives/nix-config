{
  config,
  pkgs,
  ...
}: let
  plexData = "${config.services.plex.dataDir}/Plex Media Server";

  # Telegram report on changes to the only places a compromised Plex can write
  # a file and then execute it (see the NoExecPaths in ./plex.nix):
  #
  #  - Codecs/ and Drivers/, where Plex downloads shared objects at runtime.
  #    Files there are immutable per path: each transcoder build gets its own
  #    <build-hash> directory, so a version bump adds a new directory rather
  #    than rewriting files. A modified file, or an added file outside Plex's
  #    naming scheme, is an alert; an added codec matching the scheme, or a
  #    removed old build, is reported as information.
  #  - bwrap's /etc tmpfs inside the sandbox, which holds only ld.so.conf,
  #    ld.so.cache and the ssl mountpoint. Any other file or directory on that
  #    tmpfs is an alert. It is recreated on each Plex start, so it is checked
  #    statelessly, each finding reported once per Plex process.
  plex-codec-watch = pkgs.writeShellApplication {
    name = "plex-codec-watch";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.gawk pkgs.curl pkgs.procps];
    text = ''
      state=/var/lib/plex-codec-watch
      manifest=$state/manifest
      reported=$state/sandbox-reported
      touch "$reported"
      cd "${plexData}"

      # Paths (relative to the data dir) Plex itself puts in Codecs/ and Drivers/.
      expected='^(Codecs/[0-9a-f]+-[0-9a-f]+-linux-x86_64/lib[a-z0-9_]+_(de|en)coder\.so'
      expected+='|Codecs/EasyAudioEncoder-[0-9a-f]+-linux-x86_64/EasyAudioEncoder/(EasyAudioEncoder|eae-license\.txt)'
      expected+='|Codecs/EasyAudioEncoder-[0-9]+-linux-x86_64\.zip'
      expected+='|Codecs/\.device-id'
      expected+='|Drivers/[a-z]+-[0-9a-f]+-linux-x86_64/[a-z0-9_]+_drv_video\.so)$'

      # "<sha256|link:target> <path>" per file; directories are implied.
      current=$(
        find Codecs Drivers -type f -print0 2>/dev/null | sort -z | xargs -0r sha256sum | awk '{ h = $1; sub(/^[0-9a-f]+  /, ""); print h " " $0 }'
        find Codecs Drivers -type l -printf 'link:%l %p\n' 2>/dev/null | sort
      )

      alerts=""
      infos=""

      if [ -f "$manifest" ]; then
        declare -A old new
        while read -r h p; do [ -n "$p" ] && old[$p]=$h; done <"$manifest"
        while read -r h p; do [ -n "$p" ] && new[$p]=$h; done <<<"$current"

        for p in "''${!new[@]}"; do
          if [ -z "''${old[$p]+x}" ]; then
            if [[ ''${new[$p]} != link:* && $p =~ $expected ]]; then
              infos+="+ $p"$'\n'
            else
              alerts+="added: $p (''${new[$p]:0:16})"$'\n'
            fi
          elif [ "''${old[$p]}" != "''${new[$p]}" ]; then
            alerts+="modified: $p (''${old[$p]:0:16} -> ''${new[$p]:0:16})"$'\n'
          fi
        done
        for p in "''${!old[@]}"; do
          [ -n "''${new[$p]+x}" ] || infos+="- $p"$'\n'
        done
      fi

      # Unexpected entries on bwrap's /etc tmpfs, judged by device so the
      # read-only binds and symlinks bwrap places in it are skipped.
      pid=$(pgrep -x -u plex 'Plex Media Serv' | head -1 || true)
      if [ -n "$pid" ]; then
        etc=/proc/$pid/root/etc
        dev=$(stat -c %d "$etc")
        while read -r d kind p; do
          [ "$d" = "$dev" ] || continue
          case "$kind $p" in
            "f ld.so.conf" | "f ld.so.cache" | "d ssl") continue ;;
          esac
          sum=-
          [ "$kind" = f ] && sum=$(sha256sum "$etc/$p" | cut -c1-16)
          key="$pid $kind $p $sum"
          grep -qxF "$key" "$reported" && continue
          alerts+="sandbox /etc: $kind $p ($sum)"$'\n'
          echo "$key" >>"$reported"
        done < <(find "$etc" -xdev -mindepth 1 \( -type f -o -type d \) -printf '%D %y %P\n')
      fi

      send() {
        curl -fsS --max-time 30 --retry 5 --retry-connrefused \
          -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
          --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
          --data-urlencode "text=''${1:0:4000}" \
          -d disable_web_page_preview=true >/dev/null
      }

      version="Plex ${config.services.plex.package.version}"
      if [ -n "$alerts" ]; then
        msg="🚨 ${config.networking.hostName}: unexpected change where Plex can execute files ($version)"$'\n\n'"$alerts"
        [ -z "$infos" ] || msg+=$'\n'"Also:"$'\n'"$infos"
        send "$msg"
      elif [ -n "$infos" ]; then
        send "ℹ️ ${config.networking.hostName}: Plex codecs changed ($version)"$'\n\n'"$infos"
      fi

      # Record only after a successful send, so a lost alert repeats next run.
      printf '%s\n' "$current" >"$manifest"
    '';
  };
in {
  systemd.services.plex-codec-watch = {
    description = "Report changes to Plex's executable directories to Telegram";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${plex-codec-watch}/bin/plex-codec-watch";
      EnvironmentFile = config.age.secrets.telegram-notify.path;
      StateDirectory = "plex-codec-watch";
      # Root, not plex: what it watches is exactly what a compromised Plex
      # could write, so its state must be out of plex's reach. It only reads.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = ["CAP_DAC_READ_SEARCH" "CAP_SYS_PTRACE"];
    };
  };
  systemd.timers.plex-codec-watch = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  services.notifyFailure.units = ["plex-codec-watch.service"];
}
