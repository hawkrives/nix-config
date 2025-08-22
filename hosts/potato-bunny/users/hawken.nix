{pkgs, ...}: {
  home.packages = [
    pkgs.jj
  ];

  home.stateVersion = "23.05";
}
