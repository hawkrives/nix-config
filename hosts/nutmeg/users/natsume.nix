{flake, ...}: {
  imports = [
    flake.homeModules.home-shared
    flake.homeModules.git-shared
    flake.homeModules.jj-shared
    flake.homeModules.jjui-shared
    flake.homeModules.helix-shared
    flake.homeModules.sqlite-shared
    flake.homeModules.ssh-shared
    flake.homeModules.mbx-shared
  ];

  # Personal projects (slime, ...). Token decrypted by hosts/nutmeg/mbx.nix.
  mbx = {
    namespace = "home";
    tokenFile = "/run/agenix/mbx-token";
  };
}
