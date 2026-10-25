mkdir -p /nix /etc/nix
mount -o bind /volume1/nix /nix
mount -o bind /volume1/nix/etc /etc/nix
/nix/var/nix/profiles/potato-bunny/bin/activate --boot || systemctl start nix-daemon
