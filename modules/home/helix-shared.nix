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
        p.dockerfile-language-server # for helix
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
        p.systemd-lsp
      ]);

    settings = {
      theme = "onedark";

      editor.file-picker = {
        # show hidden files in the filepicker
        hidden = false;
      };

      editor.soft-wrap.enable = true;

      editor.end-of-line-diagnostics = "hint";
      editor.inline-diagnostics.cursor-line = "error";

      keys = {
        normal = {
          # make D behave like vim
          # NOTE: t⏎ will select to line end!
          D = ["kill_to_line_end"];

          # from https://github.com/helix-editor/helix/pull/9080#issuecomment-2008964831
          J = "select_line_below";
          K = "select_line_above";

          "A-j" = "join_selections";
          "A-J" = "join_selections_space";

          X = "remove_primary_selection";
          x = "keep_selections";
          "A-x" = "remove_selections";

          "H" = ["select_mode" "goto_line_start" "exit_select_mode"];
          "L" = ["select_mode" "goto_line_end" "exit_select_mode"];
        };

        select = {
          # from https://github.com/helix-editor/helix/pull/9080#issuecomment-2008964831
          J = "select_line_below";
          K = "select_line_above";

          "A-j" = "join_selections";
          "A-J" = "join_selections_space";

          X = "remove_primary_selection";
          x = "keep_selections";
          "A-x" = "remove_selections";

          "H" = "goto_line_start";
          "L" = "goto_line_end";
        };
      };
    };
  };

  home.sessionVariables = {
    EDITOR = "hx";
  };
}
