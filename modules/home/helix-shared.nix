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
  };

  home.sessionVariables = {
    EDITOR = "hx";
  };
}
