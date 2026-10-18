{...}: let
  # Baseline sandbox: the set nixpkgs' radarr and sonarr modules ship, for the
  # media services whose modules ship little or none of it. These all run as an
  # unprivileged user, talk only TCP/Unix sockets, and touch the NAS through the
  # gid-100 group model, which PrivateUsers leaves intact (the kernel still
  # checks host ids; unmapped owners only *display* as nobody). bazarr is
  # missing here because its nixpkgs module now ships an equivalent set.
  #
  # UMask and Restart are deliberately absent: servarr.nix owns those per
  # service, and the seerr module sets its own.
  hardening = {
    CapabilityBoundingSet = "";
    NoNewPrivileges = true;
    ProtectHome = true;
    ProtectClock = true;
    ProtectKernelLogs = true;
    PrivateTmp = true;
    PrivateDevices = true;
    PrivateUsers = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
    RemoveIPC = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
      "~@debug"
      "~@mount"
      "@chown"
    ];
  };
in {
  # Each service starts from the baseline; deviations go in its own `//` so
  # they're visible next to the service they're for.

  # .NET, same app family as radarr/sonarr.
  systemd.services.lidarr.serviceConfig = hardening;

  # .NET, same app family as radarr/sonarr.
  systemd.services.prowlarr.serviceConfig = hardening;

  # Python.
  systemd.services.tautulli.serviceConfig = hardening;

  # Node enumerates interfaces over netlink (os.networkInterfaces).
  systemd.services.seerr.serviceConfig =
    hardening
    // {
      RestrictAddressFamilies = hardening.RestrictAddressFamilies ++ ["AF_NETLINK"];
    };
}
