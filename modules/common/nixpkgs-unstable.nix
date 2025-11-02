{
  inputs,
  pkgs,
  ...
}: {
  _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
}
