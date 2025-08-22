{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.self.homeModules.home-shared
    inputs.self.homeModules.git-shared
    inputs.self.homeModules.jj-shared
    inputs.self.homeModules.helix-shared
    inputs.self.homeModules.sqlite-shared
  ];

  home.packages = [
    pkgs.awscli2
  ];

  programs.git = {
    userName = "Hawken Rives";
    userEmail = "hawken.rives@techcyte.com";
  };

  programs.jj.settings.user = {
    name = "Hawken Rives";
    email = "hawken.rives@techcyte.com";
  };
}
