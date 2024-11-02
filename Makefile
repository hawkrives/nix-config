all:
	darwin-rebuild switch --flake .#`hostname`

Techcyte-XMG7K2VM6F:
	darwin-rebuild switch --flake .#$@

potato-bunny:
	nixos-rebuild switch --flake .#$@

nutmeg:
	nixos-rebuild switch --flake .#$@
	# nh os build .#$@

pmx-sonarr:
	nixos-rebuild --flake .#$@ --target-host user@$@ --use-remote-sudo

update:
	nix flake update
