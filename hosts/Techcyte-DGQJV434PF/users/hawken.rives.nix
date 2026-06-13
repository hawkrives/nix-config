{
  pkgs,
  ...
}: {
  imports = [
    ../../../modules/home/home-shared.nix
    ../../../modules/home/git-shared.nix
    ../../../modules/home/jj-shared.nix
    ../../../modules/home/helix-shared.nix
    ../../../modules/home/sqlite-shared.nix
  ];

  home.packages =
    [
      pkgs.awscli2
      pkgs.podman
      pkgs.lima
      pkgs.nomad
    ]
    ++ # language servers for zed
    [
      pkgs.bash-language-server
      pkgs.docker-compose-language-service
      pkgs.dockerfile-language-server
      pkgs.nil
      pkgs.nixd
      pkgs.ruff
      pkgs.sql-formatter
      pkgs.taplo # for toml
      pkgs.terraform-ls
      pkgs.ty
      pkgs.vscode-css-languageserver
      pkgs.vscode-json-languageserver
      pkgs.vtsls
      pkgs.yaml-language-server
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
      pkgs.systemd-lsp
    ]);

  programs.git.settings.user = {
    name = "Hawken Rives";
    email = "hawken.rives@techcyte.com";
  };

  home.sessionVariables = {
    GOPRIVATE = "gitlab.com/techcyte/";
  };
}
