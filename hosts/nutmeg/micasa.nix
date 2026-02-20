{perSystem, inputs, ...}: {
  imports = [
    inputs.micasa.nixosModules.default
  ];

  services.micasa = {
    enable = false; # until the nixos module is fixed
    # enable = true;
    package = perSystem.micasa.default;
    # if we want to add keys explicitly for micasa; this merges with the openssh setting
    # authorizedKeys = [ ... ];
  };
}
