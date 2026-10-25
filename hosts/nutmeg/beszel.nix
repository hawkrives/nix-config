{...}: {
  # SMART health and drive temps for the Mac Mini's SATA SSD. This is opt-in per
  # host because it grants the agent CAP_SYS_RAWIO/CAP_SYS_ADMIN and drops
  # NoNewPrivileges + PrivateDevices — worth it on real hardware, pointless on
  # the tuckles VM. The hub runs on potato-bunny (hosts/potato-bunny/beszel-hub.nix).
  services.beszel.agent.smartmon.enable = true;
}
