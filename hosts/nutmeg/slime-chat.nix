{ config, inputs, ... }:
{
  # nixosModules.default (rather than .slime-chat) also applies the flake's
  # overlay, so the module's `package` default (`pkgs.slime-chat`) resolves
  # without wiring the overlay ourselves.
  imports = [ inputs.slime-chat.nixosModules.default ];

  # TWITCH_CLIENT_ID / TWITCH_CLIENT_SECRET for the Twitch OAuth app, kept out
  # of the world-readable store. Values mirror the hand-run copy's mise.toml.
  # (TWITCH_ACCESS_TOKEN is deliberately NOT set — it flips the server into test
  # mode; real tokens are minted by the OAuth flow and stored in SQLite.)
  age.secrets.slime-chat-env.file = ../../secrets/slime-chat-env.age;

  services.slime-chat = {
    enable = true;

    # 9100 is taken by the hand-run local copy (see the `# for slime` firewall
    # block in configuration.nix), so the packaged service lives on 9111.
    # Reached over the tailnet via tsnsrv below, so no LAN firewall hole.
    port = 9111;

    environmentFile = config.age.secrets.slime-chat-env.path;

    # Twitch OAuth callback. Must match a redirect URI registered on the Twitch
    # application. Points at the tsnsrv-exposed tailnet URL below.
    redirectUri = "https://slime.vaquita-woodpecker.ts.net/auth/callback";
  };

  # Expose on the tailnet: https://slime.vaquita-woodpecker.ts.net -> the local
  # server. The server binds dual-stack ([::]:port, accepts IPv4 too), so the
  # tsnsrv "localhost" default (which resolves to ::1 first) connects fine; just
  # set the port and inherit the host default.
  services.tsnsrv.services.slime.urlParts.port = config.services.slime-chat.port;
}
