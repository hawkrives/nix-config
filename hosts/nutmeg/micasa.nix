{perSystem, ...}: {
  services.micasa = {
    enable = true;
    package = perSystem.micasa.packages.default;
    # if we want to add keys explicitly for micasa; this merges with the openssh setting
    # authorizedKeys = [ ... ];
  };
}
