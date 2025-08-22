{
  pkgs,
  perSystem,
  ...
}: let
  p = perSystem.nixpkgs-unstable;
in {
  programs.helix = {
    enable = true;
    package = perSystem.nixpkgs-unstable.helix;

    extraPackages =
      [
        # language servers for helix
        p.bash-language-server
        p.docker-language-server # official from Docker, Inc
        p.dockerfile-language-server-nodejs # for helix
        p.docker-compose-language-service
        p.typescript-language-server
        p.yaml-language-server
        p.gopls
        p.terraform-ls
        p.vscode-json-languageserver
        p.vscode-css-languageserver
        # p.nodePackages.vscode-html-languageserver
        perSystem.nixpkgs-unstable.nil
        p.ty
        p.ruff
        p.taplo # toml
      ]
      ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
        perSystem.systemd-lsp.default
      ]);

    settings = {
      theme = "onedark";

      editor.file-picker = {
        # show hidden files in the filepicker
        hidden = false;
      };

      keys = {
        normal = {
          # make D behave like vim
          # NOTE: t⏎ will select to line end!
          D = ["kill_to_line_end"];
        };
      };
    };
  };

  home.sessionVariables = {
    EDITOR = "hx";
  };
}
