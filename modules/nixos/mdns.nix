# mDNS via avahi: publish this host as <hostname>.local and resolve other
# hosts' .local names through NSS. Used so nutmeg's *arr can reach the download
# clients on tuckles at tuckles.local without any DNS rewrites.
{ config, pkgs, ... }:
let
  avahiCfg = config.services.avahi;

  # avahi publishes services.avahi.hostName when it's set and falls back to the
  # system hostname otherwise. Bake the static name in if there is one, so the
  # check compares against what avahi will actually claim rather than a guess.
  staticName = avahiCfg.hostName;
  domain = avahiCfg.domainName;

  nameCheck = pkgs.writeShellApplication {
    name = "avahi-name-check";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      # Self-heal for avahi silently dropping this host's .local name.
      #
      # Two failure modes have bitten this fleet. Both leave the unit reporting
      # "active (running)", so nothing alerts and the breakage is only noticed
      # when some other thing that depends on .local fails:
      #
      #  1. HOST-NAME CONFLICT RENAME (tuckles, 2026-08-26). After the VM froze
      #     ~3min under volume1 IO saturation, avahi's probe state machine
      #     mis-fired on resume, declared a conflict, and renamed itself
      #     tuckles -> tuckles-2 -> tuckles-3. Nothing published tuckles.local
      #     any more, so `mise run tuckles:{ask,yes}` (which target
      #     haru@tuckles.local) broke. Nothing on the LAN was contesting the
      #     name -- a plain restart reclaimed it. See the tuckles-vm-stalls note.
      #  2. STALE PID DEATH (nutmeg, 2026-07-26). avahi's process died leaving
      #     /run/avahi-daemon/pid behind. avahi drops privileges before writing
      #     that file, so it cannot remove a stale one and every restart then
      #     fails with "Failed to create PID file: File exists" until cleared.
      #
      # Detection reads avahi's OWN reported name out of the unit's StatusText
      # (avahi pushes it via sd_notify and updates it on rename -- that line is
      # how the tuckles breakage was found). Purely local: no multicast round
      # trip, so a transient network blip cannot false-positive into a restart.

      stamp=/run/avahi-name-check.last-restart
      min_uptime=120   # don't race avahi's own startup probe
      cooldown=900     # at most one restart per 15 min

      static_name="${staticName}"
      if [ -n "$static_name" ]; then
        expected="$static_name.${domain}"
      else
        expected="$(cat /proc/sys/kernel/hostname).${domain}"
      fi

      published() {
        systemctl show avahi-daemon --property=StatusText --value 2>/dev/null \
          | sed -n 's/.*Host name is \([^ ]*\)\..*/\1/p'
      }

      actual="$(published)"
      if [ "$actual" = "$expected" ]; then
        exit 0 # healthy; stay quiet so the journal only records real events
      fi

      shown="$actual"
      if [ -z "$shown" ]; then
        shown="<none>"
      fi

      # Give a freshly-started daemon time to finish probing before judging it.
      now="$(date +%s)"
      entered="$(systemctl show avahi-daemon --property=ActiveEnterTimestamp --value 2>/dev/null)"
      started=0
      if [ -n "$entered" ]; then
        started="$(date -d "$entered" +%s 2>/dev/null || echo 0)"
      fi
      if [ "$started" -gt 0 ] && [ "$((now - started))" -lt "$min_uptime" ]; then
        echo "avahi publishes $shown, want $expected, but it started $((now - started))s ago; letting it settle"
        exit 0
      fi

      # Flap guard. tuckles freezes for minutes at a time, so this timer WILL
      # fire mid-stall; without a cooldown it would restart avahi on every tick
      # and turn one outage into a restart storm. Kept in /run: resets on boot.
      if [ -e "$stamp" ]; then
        last="$(cat "$stamp" 2>/dev/null || echo 0)"
        if [ "$((now - last))" -lt "$cooldown" ]; then
          echo "avahi publishes $shown, want $expected, but last restart was $((now - last))s ago (cooldown $cooldown s); not touching it"
          exit 0
        fi
      fi

      echo "avahi publishes $shown but should publish $expected -- recovering"

      # Only clear the pid file when it points at something dead; removing a
      # live daemon's pid file would be actively harmful. This is failure 2.
      pidfile=/run/avahi-daemon/pid
      if [ -e "$pidfile" ]; then
        p="$(cat "$pidfile" 2>/dev/null || true)"
        if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then
          echo "clearing stale pid file (pid $p is not running)"
          rm -f "$pidfile"
        fi
      fi

      # Stamp BEFORE restarting: a restart that fails must still count against
      # the cooldown, or a persistently broken avahi gets hammered every tick.
      echo "$now" > "$stamp"

      # reset-failed first, or start-limit-hit masks the real error.
      systemctl reset-failed avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
      systemctl restart avahi-daemon.service

      sleep 3
      after="$(published)"
      if [ -z "$after" ]; then
        after="<none>"
      fi
      if [ "$after" = "$expected" ]; then
        echo "recovered: avahi now publishes $after"
      else
        echo "STILL WRONG after restart: avahi publishes $after, want $expected"
      fi
    '';
  };
in
{
  services.avahi = {
    enable = true;
    nssmdns4 = true; # resolve *.local A (IPv4) records via getaddrinfo/NSS
    nssmdns6 = true; # also resolve *.local AAAA (IPv6) records via NSS
    publish = {
      enable = true;
      addresses = true; # advertise this host's A record (<hostname>.local)
      # register a mDNS HINFO record which contains information about the local operating system and CPU
      hinfo = true;
      # Needed to allow samba to automatically register mDNS records, without the need for an `extraServiceFile`
      userServices = true;
    };
    openFirewall = true; # mDNS UDP 5353
  };

  # Watchdog for the two silent avahi failures described in the script above.
  # Deliberately only `after` avahi-daemon, never `requires`/`wants`: if avahi
  # is down this still needs to run -- that is the case worth recovering from.
  systemd.services.avahi-name-check = {
    description = "Verify avahi still publishes this host's .local name";
    after = [ "avahi-daemon.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${nameCheck}/bin/avahi-name-check";
    };
  };

  systemd.timers.avahi-name-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "30s"; # keep the fleet from checking in lockstep
      AccuracySec = "10s";
    };
  };
}
