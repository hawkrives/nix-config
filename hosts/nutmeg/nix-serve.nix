{...}: {
  services.nix-serve = {
    enable = true;
    openFirewall= true;
    port = 5000;
    secretKeyFile = "/etc/nix/binary-cache-secret-key";
  };
}
