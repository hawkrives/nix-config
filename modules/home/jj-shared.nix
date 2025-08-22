{...}: {
  programs.jj.settings = {
    "$schema" = "https://jj-vcs.github.io/jj/latest/config-schema.json";

    user = {
      name = "Hawken Rives";
      email = "hawkrives@fastmail.fm";
    };

    ui = {
      default-command = "log";
      paginate = "auto";
      diff-editor = ":builtin";
    };

    aliases = {
      # tug is from https://github.com/jj-vcs/jj/discussions/2425
      # tug = ["bookmark", "move", "--from", "heads(::@- & bookmarks())", "--to", "@-"];
      tug = ["bookmark" "move" "--from" "closest_bookmark(@)" "--to" "closest_nonempty(@)"];
    };

    revset-aliases = {
      "closest_bookmark(to)" = "heads(::to & bookmarks())";
      "closest_nonempty(to)" = "heads(::to ~ empty())";
    };

    experimental-advance-branches = {
      enabled-branches = ["glob:*"];
      disabled-branches = ["main" "master" "trunk" "glob:push-*"];
    };

    templates = {
      draft_commit_description = ''
        concat(
          coalesce(description, default_commit_description, "\n"),
          surround(
            "\nJJ: This commit contains the following changes:\n", "",
            indent("JJ:     ", diff.stat(72)),
          ),
          "\nJJ: ignore-rest\n",
          diff.git(),
        )
      '';
    };
  };
}
