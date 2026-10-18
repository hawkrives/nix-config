# agentsview: browse and search AI coding agent session history.
#
# It runs as a launchd agent. config.toml is left unmanaged because
# agentsview writes to it (it generates an auth token and migrates old formats),
# so a read-only store symlink would break it.
#
# `agentsview mcp` runs over stdio and reads through this daemon, so Claude Code
# starts it per session. Register it once with
# `claude mcp add agentsview -- agentsview mcp`.
{
  config,
  perSystem,
  ...
}: {
  home.packages = [
    perSystem.self.agentsview
  ];

  launchd.agents.agentsview = {
    enable = true;
    config = {
      ProgramArguments = [
        "${perSystem.self.agentsview}/bin/agentsview"
        "serve"
        "--no-browser"
        "--no-update-check"
        "--port"
        "4398"
      ];
      RunAtLoad = true;
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agentsview.log";
      # `serve` exits 0 when a server already runs (e.g. one a CLI command
      # started); restart only after a crash.
      KeepAlive.SuccessfulExit = false;
    };
  };
}
