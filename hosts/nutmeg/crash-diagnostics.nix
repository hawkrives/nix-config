{ pkgs, ... }:
{
  # [crash forensics]
  #
  # nutmeg (Apple Mac mini6,2, Late 2012) has silently hard-stopped at least
  # three times: 2026-06-25, 2026-07-11 (down 3.5h), and 2026-07-26 (down 7min).
  # Every time the journal simply ends mid-line with no shutdown sequence, and
  # `last` records a bare "crash". The 2026-07-26 stop was investigated in
  # detail and left *no* usable evidence: no panic, no oops, no OOM kill, no
  # hung task, no ATA/I-O error, no thermal event, no MCE, and an empty pstore.
  #
  # That absence was not bad luck — the box was configured to leave no trace:
  #   kernel.nmi_watchdog = 0   (hard lockup detector off, despite HW support)
  #   kernel.panic_on_oops = 0  (an oops leaves a limping kernel, unlogged)
  #   kernel.panic = 0          (panic == sit there dead forever, hence the 3.5h)
  # so a wedged CPU produces exactly what we saw: silence, then a corpse until
  # someone walks over and presses the power button.
  #
  # The goal here is NOT to fix the crash (root cause is still unknown). It is
  # to guarantee the *next* one is diagnosable, and to bound the outage.

  # [lockup detection + panic behavior]
  boot.kernel.sysctl = {
    # Turn the NMI hard lockup detector back on. This is the one that matters
    # here: it runs off a perf/PMU counter, so it can still fire on a CPU that
    # is fully wedged with interrupts disabled — precisely the failure mode
    # that leaves no logs. The hardware supports it (CONFIG_HARDLOCKUP_DETECTOR,
    # HAVE_HARDLOCKUP_DETECTOR_PERF) and the kernel enables it at boot, but the
    # sysctl was reading 0.
    "kernel.nmi_watchdog" = 1;
    "kernel.watchdog" = 1;

    # A hard lockup is always a genuine bug, so escalate it to a panic: that
    # routes it through pstore (see below) and then reboots.
    "kernel.hardlockup_panic" = 1;

    # An oops means the kernel is already in undefined territory; on a headless
    # box it's better to panic and capture it than to limp on silently.
    "kernel.panic_on_oops" = 1;

    # Deliberately NOT set to 1. A *soft* lockup is a 20s+ CPU stall, which a
    # busy media server can hit legitimately under a Plex transcode or a big nix
    # build. Soft lockups still get logged loudly; we just don't reboot for one.
    # If the next incident logs a soft lockup and then wedges anyway, flip this.
    "kernel.softlockup_panic" = 0;

    # Reboot 30s after a panic instead of sitting dead. 30s (not 0) leaves a
    # window to read the console if anyone happens to be looking at it.
    "kernel.panic" = 30;

    # Deliberately NOT setting kernel.hung_task_panic: this host NFS-mounts the
    # Synology (see modules/nixos/synology-mounts.nix), and a NAS hiccup puts
    # tasks in uninterruptible sleep as a matter of course. Rebooting for that
    # would trade a rare crash for frequent spurious reboots.
  };

  # [persistence] Panic logs already survive a reboot on this box: the kernel
  # registers efi_pstore as the pstore backend and efivarfs is mounted rw, so a
  # panic gets written to EFI NVRAM and reappears in /sys/fs/pstore on the next
  # boot. Nothing to enable — the pstore was empty after the last crash because
  # no panic ever happened, which is itself the finding. The sysctls above are
  # what turn a silent lockup INTO a panic, so pstore finally has something to
  # catch. systemd's systemd-pstore.service then archives it to
  # /var/lib/systemd/pstore automatically.
  #
  # If a future crash still leaves pstore empty, the remaining suspects are
  # abrupt power loss and SMC/thermal cutoff, neither of which any on-box
  # logging can capture. The next escalation would be netconsole shipping the
  # dying kmsg to another always-on host over UDP.

  # [watchdog] The real hardware watchdog is NOT usable on this machine:
  #   iTCO_wdt: unable to reset NO_REBOOT flag, device disabled by hardware/BIOS
  # Apple's firmware locks the TCO NO_REBOOT flag, so there is no /dev/watchdog
  # and systemd.watchdog would silently do nothing. softdog is the fallback: a
  # pure-kernel timer that reboots if PID 1 stops petting it.
  #
  # Be clear about the limits: softdog is driven by a kernel timer, so it
  # recovers a wedged *userspace* (systemd starved, root fs stuck) but CANNOT
  # recover a true hard lockup where the kernel itself stops running — that case
  # is covered by kernel.hardlockup_panic above, not by this.
  boot.kernelModules = [ "softdog" ];

  # 120s is deliberately generous. PID 1 missing a ping for two minutes on a
  # box this busy means something is genuinely wrong, and a false-positive
  # reboot of a healthy server would be worse than the thing we're fixing.
  # Even so: 2 minutes of downtime instead of 3.5 hours.
  systemd.watchdog.runtimeTime = "120s";

  # [disk health] The root SSD (Samsung 860 EVO 250GB) is a prime suspect for a
  # machine that dies without being able to log why — if the SATA link or the
  # controller wedges, the kernel cannot write the very errors that would
  # explain it. smartctl wasn't even installed here, so the drive's health was
  # unknown at the time of the crash investigation.
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.wall.enable = true;
    notifications.mail.enable = false; # no MTA on this host

    # -a: all attributes; -o on: offline data collection; -S on: attribute
    # autosave; short self-test daily at 02:00, long self-test Saturdays 03:00.
    defaults.autodetected = "-a -o on -S on -s (S/../.././02|L/../../6/03)";
  };

  environment.systemPackages = [ pkgs.smartmontools ];
}
