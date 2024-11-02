all:
	darwin-rebuild switch --flake .#`hostname`

Techcyte-XMG7K2VM6F:
	/run/current-system/sw/bin/darwin-rebuild switch --flake .#$@

potato-bunny:
	nixos-rebuild switch --flake .#$@

nutmeg:
	nixos-rebuild switch --flake .#$@
	# nh os build .#$@

update-unstable:
	nix flake lock --update-input nixpkgs-unstable
