# Every NixOS server's journal lives on tuckles, whose disk is a file on the
# NAS's volume1 (hard drives). The other servers keep theirs in RAM only and
# stream it there live, so journald's write amplification — it rewrites the
# same mmapped pages over and over, ~100x the logged bytes on nutmeg — lands on
# the NAS's disks instead of their own SSDs.
#
# tuckles, not the NAS itself: systemd-journal-remote needs Linux 5.8+ (statx
# mount IDs), and DSM's kernel is 4.4. HTTP, not HTTPS (nixpkgs builds systemd
# without TLS), so the receiver only listens on the tailnet, whose WireGuard
# encrypts it.
#
# Reading another host's logs, on tuckles (one file per sending address):
#   journalctl -D /var/log/journal/remote _HOSTNAME=nutmeg -b -1
#
# While tuckles is down, uploads stop and resume from their saved cursor; what
# fits in the sender's RAM journal (RuntimeMaxUse) survives the gap.
{
  config,
  lib,
  ...
}: let
  receiver = "tuckles";
  receiverAddr = "100.100.204.63"; # tuckles' tailnet IP (nutmeg runs --accept-dns=false)
  port = 19532;
in
  lib.mkMerge [
    (lib.mkIf (config.networking.hostName == receiver) {
      services.journald.remote = {
        enable = true;
        inherit port;
        settings.Remote = {
          SplitMode = "host";
          MaxUse = "50G";
          MaxFileSize = "256M";
        };
      };
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [port];
    })
    (lib.mkIf (config.networking.hostName != receiver) {
      services.journald.settings.Journal = {
        Storage = "volatile";
        RuntimeMaxUse = "1G";
      };
      services.journald.upload = {
        enable = true;
        settings.Upload.URL = "http://${receiverAddr}:${toString port}";
      };
    })
  ]
