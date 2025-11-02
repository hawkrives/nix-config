{
  flake,
  pkgs,
  perSystem,
  ...
}: let
  p = perSystem.nixpkgs-unstable;
in {
  imports = [
    flake.homeModules.home-shared
    flake.homeModules.git-shared
    flake.homeModules.jj-shared
    flake.homeModules.helix-shared
    flake.homeModules.sqlite-shared
  ];

  fonts.packages = [pkgs.font-blex-mono-nerd-font];

  home.packages =
    [
      pkgs.awscli2
      p.copilot-cli
    ]
    ++ # language servers for zed
    [
      p.bash-language-server
      p.docker-compose-language-service
      p.dockerfile-language-server
      p.nil
      p.nixd
      p.ruff
      p.sql-formatter
      p.taplo # for toml
      p.terraform-ls
      p.ty
      p.vscode-css-languageserver
      p.vscode-json-languageserver
      p.vtsls
      p.yaml-language-server
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
      p.systemd-lsp
    ]);

  programs.git = {
    userName = "Hawken Rives";
    userEmail = "hawken.rives@techcyte.com";
  };

  home.sessionVariables = {
    GOPRIVATE = "gitlab.com/techcyte/";
  };
}
