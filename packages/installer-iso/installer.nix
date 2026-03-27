{...}: {
  # Enable SSH immediately on boot
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = "no";
    };
  };

  systemd.services.sshd.wantedBy = ["multi-user.target"];

  # Bake in your public key so nixos-anywhere can SSH in without interaction
  users.users.root.opensshAuthorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFhbHFf1LJ/NseB3yDEAKNu3CGNDs+ot8qdQA5LI4rU"
  ];

  # Optional: faster squashfs build during development
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
}
