# Tools for browsing and searching AI coding agent session history.
#
# sessionwiki needs no service: `sessionwiki mcp` runs over stdio, so Claude
# Code starts it per session. Register it once with
# `claude mcp add sessionwiki -- sessionwiki mcp`.
#
# agentsview runs as a launchd agent. config.toml is left unmanaged because
# agentsview writes to it (it generates an auth token and migrates old formats),
# so a read-only store symlink would break it.
{ perSystem, ... }:
{
  home.packages = [
    perSystem.self.sessionwiki
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
      ];
      RunAtLoad = true;
      # `serve` exits 0 when a server already runs (e.g. one a CLI command
      # started); restart only after a crash.
      KeepAlive.SuccessfulExit = false;
    };
  };
}
