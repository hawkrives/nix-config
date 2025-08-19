{...}: {
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.dates = "weekly";
    clean.extraArgs = "--keep-since 4d --keep 3";
  };

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      allowed-users = ["root" "natsume"];
      extra-substituters = ["https://cache.lix.systems"];
      extra-trusted-public-keys = [
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        "nutmeg:6F0E+NkIvpTI0d4QSvrDb3+LYhrQwXkYjqgI9etpuEw="
        "potato-bunny:i8Ab1IPNDKp9EWfmFDZIvMm70c+D435UlIsVFhJO3ts="
      ];
      secret-key-files = "/etc/nix/private-key";
    };
  };
}
