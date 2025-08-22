{pkgs, ...}: {
  programs.helix = {
    enable = true;
    # TODO: use pkgs-unstable.helix

    extraPackages = [
      # language servers for helix
      pkgs.bash-language-server
      pkgs.docker-language-server # official from Docker, Inc
      pkgs.dockerfile-language-server-nodejs # for helix
      pkgs.docker-compose-language-service
      pkgs.typescript-language-server
      # pkgs.systemd-language-server
      pkgs.yaml-language-server
    ];
  };

  home.sessionVariables = {
    EDITOR = "hx";
  };
}
