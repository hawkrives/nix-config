{perSystem, inputs, ...}: {
  imports = [
    inputs.micasa.nixosModules.default
  ];

  services.micasa = {
    enable = true;
    package = perSystem.micasa.default;
    # if we want to add keys explicitly for micasa; this merges with the openssh setting
    # authorizedKeys = [ ... ];
  };
}
