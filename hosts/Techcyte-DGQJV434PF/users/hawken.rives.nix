{
  flake,
  pkgs,
  ...
}: {
  imports = [
    flake.homeModules.home-shared
    flake.homeModules.git-shared
    flake.homeModules.jj-shared
    flake.homeModules.helix-shared
    flake.homeModules.sqlite-shared
  ];

  home.packages = [
    pkgs.awscli2
  ];

  programs.git = {
    userName = "Hawken Rives";
    userEmail = "hawken.rives@techcyte.com";
  };

  programs.jujutsu.settings.user = {
    name = "Hawken Rives";
    email = "hawken.rives@techcyte.com";
  };
}
