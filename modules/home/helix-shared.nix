{
  pkgsUnstable,
  flake,
  ...
}: {
  imports = [
    flake.modules.common.nixpkgs-unstable # provides the pkgsUnstable argument
  ];

  programs.helix = {
    enable = true;
    package = pkgsUnstable.helix;

    extraPackages =
      [
        # language servers for helix
        pkgsUnstable.bash-language-server
        pkgsUnstable.docker-language-server # official from Docker, Inc
        pkgsUnstable.dockerfile-language-server # for helix
        pkgsUnstable.docker-compose-language-service
        pkgsUnstable.typescript-language-server
        pkgsUnstable.yaml-language-server
        pkgsUnstable.gopls
        pkgsUnstable.terraform-ls
        pkgsUnstable.vscode-json-languageserver
        pkgsUnstable.vscode-css-languageserver
        pkgsUnstable.nil
        pkgsUnstable.ty
        pkgsUnstable.ruff
        pkgsUnstable.taplo # for toml
      ]
      ++ (pkgsUnstable.lib.optionals pkgsUnstable.stdenv.isLinux [
        pkgsUnstable.systemd-lsp
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

          # X = "remove_primary_selection";
          # x = "keep_selections";
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

          # X = "remove_primary_selection";
          # x = "keep_selections";
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
