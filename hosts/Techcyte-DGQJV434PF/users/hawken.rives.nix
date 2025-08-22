{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.self.homeModules.home-shared
    inputs.self.homeModules.git-shared
    inputs.self.homeModules.helix-shared
    inputs.self.homeModules.sqlite-shared
  ];

  home.packages = [
    pkgs.awscli2
  ];
}
