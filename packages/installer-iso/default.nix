{inputs, ...}:
inputs.nixos-generators.nixosGenerate {
  system = "x86_64-linux";
  format = "install-iso";
  modules = [./installer.nix];
}
