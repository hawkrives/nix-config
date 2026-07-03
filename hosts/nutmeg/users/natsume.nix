{flake, ...}: {
  imports = [
    flake.homeModules.home-shared
    flake.homeModules.git-shared
    flake.homeModules.jj-shared
    flake.homeModules.jjui-shared
    flake.homeModules.helix-shared
    flake.homeModules.sqlite-shared
  ];
}
