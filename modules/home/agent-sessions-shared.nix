# agentsview: browse and search AI coding agent session history.
#
# It runs as a launchd agent. agentsview has no XDG support: config.toml, the
# database, locks and its own debug log all share one data directory, set by
# AGENTSVIEW_DATA_DIR. That variable goes to the launchd agent and to the login
# shell, so CLI commands and `agentsview mcp` find the same daemon.
#
# config.toml is left unmanaged because agentsview writes to it (it generates an
# auth token and migrates old formats), so a read-only store symlink would
# break it.
#
# `agentsview mcp` runs over stdio and reads through this daemon, so Claude Code
# starts it per session. Register it once with
# `claude mcp add agentsview -- agentsview mcp`.
{
  config,
  perSystem,
  ...
}: let
  dataDir = "${config.xdg.dataHome}/agentsview";
  logDir = "${config.xdg.stateHome}/agentsview";
in {
  home.packages = [
    perSystem.self.agentsview
  ];

  home.sessionVariables.AGENTSVIEW_DATA_DIR = dataDir;

  # launchd opens StandardErrorPath without creating its directory.
  home.file."${logDir}/.keep".text = "";

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
      EnvironmentVariables.AGENTSVIEW_DATA_DIR = dataDir;
      RunAtLoad = true;
      StandardErrorPath = "${logDir}/agentsview.log";
      # `serve` exits 0 when a server already runs (e.g. one a CLI command
      # started); restart only after a crash.
      KeepAlive.SuccessfulExit = false;
    };
  };
}
