{
  config,
  pkgs,
  ...
}: let
  # qBittorrent's WebUI API, reached at the airvpn netns address (see qui.nix).
  qbApi = "http://192.168.15.1:6001/api/v2";
  state = "/var/lib/fake-seed-watch";

  # fake-seed-report: list networks whose peers keep joining swarms as 100%
  # "seeds" without ever sending data (see fake-seed-watch/fake_seed_report.py).
  # Its tests run as part of the build.
  fake-seed-report = pkgs.stdenvNoCC.mkDerivation {
    name = "fake-seed-report";
    src = ./fake-seed-watch;
    nativeBuildInputs = [pkgs.python3 pkgs.makeWrapper];
    doCheck = true;
    checkPhase = ''
      python3 -m unittest -v test_fake_seed_report
    '';
    installPhase = ''
      install -Dm644 fake_seed_report.py $out/lib/fake_seed_report.py
      makeWrapper ${pkgs.python3}/bin/python3 $out/bin/fake-seed-report \
        --add-flags $out/lib/fake_seed_report.py
    '';
  };

  # Every 2s, log each peer claiming 100% on each torrent that is still
  # downloading. Fake seeds stay connected for only a few seconds, so a slower
  # poll would miss most of them; a seed that is real shows bytes downloaded.
  fake-seed-watch = pkgs.writeShellApplication {
    name = "fake-seed-watch";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils];
    text = ''
      log=${state}/sightings.tsv
      while true; do
        now=$(date +%s)
        hashes=$(curl -fsS --max-time 10 "${qbApi}/torrents/info?filter=downloading" | jq -r '.[].hash') || hashes=""
        for hash in $hashes; do
          curl -fsS --max-time 10 "${qbApi}/sync/torrentPeers?hash=$hash&rid=0" |
            jq -r --arg ts "$now" --arg hash "$hash" '
              .peers // {} | .[] | select(.progress >= 1)
              | [$ts, $hash, .ip, .port, .client, .country_code, .downloaded] | @tsv' >>"$log" || true
        done
        sleep 2
      done
    '';
  };

  # Daily: report new suspects to Telegram (each network once), and keep a week
  # of sightings. It only reports; banning is a human decision, made by adding
  # the range to qbittorrent.nix's ipfilter.p2p.
  fake-seed-digest = pkgs.writeShellApplication {
    name = "fake-seed-digest";
    runtimeInputs = [fake-seed-report pkgs.curl pkgs.gawk pkgs.coreutils];
    text = ''
      log=${state}/sightings.tsv
      touch "$log"
      cutoff=$(( $(date +%s) - 7 * 86400 ))
      awk -F'\t' -v c="$cutoff" '$1 >= c' "$log" >"$log.new" && mv "$log.new" "$log"

      report=$(fake-seed-report --new-only ${state}/reported "$log" /etc/qbittorrent/ipfilter.p2p)
      [ -n "$report" ] || exit 0
      curl -fsS --max-time 30 --retry 5 --retry-connrefused \
        -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$(printf 'qBittorrent: possible fake seeds (0 bytes sent, repeated reconnects)\n\n%s' "$report" | head -c 4000)" \
        -d disable_web_page_preview=true >/dev/null
    '';
  };
in {
  environment.systemPackages = [fake-seed-report];

  systemd.services.fake-seed-watch = {
    description = "Log peers claiming 100% on downloading qBittorrent torrents";
    after = ["qbittorrent.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${fake-seed-watch}/bin/fake-seed-watch";
      StateDirectory = "fake-seed-watch";
      Restart = "always";
      RestartSec = "30s";
    };
  };

  systemd.services.fake-seed-digest = {
    description = "Report networks that look like fake seeds to Telegram";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fake-seed-digest}/bin/fake-seed-digest";
      EnvironmentFile = config.age.secrets.telegram-notify.path;
      StateDirectory = "fake-seed-watch";
    };
  };
  systemd.timers.fake-seed-digest = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  services.notifyFailure.units = ["fake-seed-watch.service" "fake-seed-digest.service"];
}
