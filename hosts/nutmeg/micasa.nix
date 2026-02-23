{perSystem, inputs, ...}: {
  imports = [
    inputs.micasa.nixosModules.default
  ];

  services.micasa = {
    enable = true;
    package = perSystem.micasa.default;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFhbHFf1LJ/NseB3yDEAKNu3CGNDs+ot8qdQA5LI4rU hawken.rives@Techcyte-DGQJV434PF"
    ];
  };
}
