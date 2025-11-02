{
  flake,
  pkgs,
  pkgsUnstable,
  ...
}: {
  imports = [
    flake.modules.common.nixpkgs-unstable # provides the pkgsUnstable argument

    flake.homeModules.home-shared
    flake.homeModules.git-shared
    flake.homeModules.jj-shared
    flake.homeModules.helix-shared
    flake.homeModules.sqlite-shared
  ];

  home.packages =
    [
      pkgs.awscli2
      pkgsUnstable.copilot-cli
    ]
    ++ # language servers for zed
    [
      pkgsUnstable.bash-language-server
      pkgsUnstable.docker-compose-language-service
      pkgsUnstable.dockerfile-language-server
      pkgsUnstable.nil
      pkgsUnstable.nixd
      pkgsUnstable.ruff
      pkgsUnstable.sql-formatter
      pkgsUnstable.taplo # for toml
      pkgsUnstable.terraform-ls
      pkgsUnstable.ty
      pkgsUnstable.vscode-css-languageserver
      pkgsUnstable.vscode-json-languageserver
      pkgsUnstable.vtsls
      pkgsUnstable.yaml-language-server
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
      pkgsUnstable.systemd-lsp
    ]);

  programs.git = {
    userName = "Hawken Rives";
    userEmail = "hawken.rives@techcyte.com";
  };

  home.sessionVariables = {
    GOPRIVATE = "gitlab.com/techcyte/";
  };
}
