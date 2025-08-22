{
  pkgs,
  perSystem,
  ...
}: {
  programs.helix = {
    enable = true;
    package = perSystem.nixpkgs-unstable.helix;

    # TODO: enable
    # extraPackages =
    #   [
    #     # language servers for helix
    #     pkgs.bash-language-server
    #     pkgs.docker-language-server # official from Docker, Inc
    #     pkgs.dockerfile-language-server-nodejs # for helix
    #     pkgs.docker-compose-language-service
    #     pkgs.typescript-language-server
    #     pkgs.yaml-language-server
    #   ]
    #   ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
    #     pkgs.systemd-language-server
    #   ]);

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
