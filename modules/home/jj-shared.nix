{
  pkgs,
  pkgsUnstable,
  flake,
  ...
}: {
  imports = [
    flake.modules.common.nixpkgs-unstable # provides the pkgsUnstable argument
  ];

  programs.jujutsu.enable = true;
  programs.jujutsu.package = pkgsUnstable.jujutsu;

  programs.jujutsu.settings = {
    "$schema" = "https://jj-vcs.github.io/jj/latest/config-schema.json";

    "--scope" = [
      {
        "--when".repositories = ["~/Developer/gitlab.com/"];
        user.email = "hawken.rives@techcyte.com";
      }
    ];

    user = {
      name = pkgs.lib.mkDefault "Hawken Rives";
      email = pkgs.lib.mkDefault "hawkrives@fastmail.fm";
    };

    experimental-advance-branches = {
      enabled-branches = ["glob:*"];
      disabled-branches = ["main" "master" "trunk" "glob:push-*"];
    };

    ui = {
      default-command = "log";
      paginate = "auto";
      diff-editor = ":builtin";
    };

    fix.tools = {
      terraform = {
        command = ["terraform" "fmt"];
        patterns = ["glob:'**/*.tfvars'" "glob:'**/*.tf'"];
      };
    };

    aliases = {
      # tug is from https://github.com/jj-vcs/jj/discussions/2425
      tug-closest = ["bookmark" "move" "--from" "closest_bookmark(@)" "--to" "closest_nonempty(@)"];
      # from https://andre.arko.net/2025/09/28/stupid-jj-tricks/
      lost = ["util" "exec" "--" "sh" "-c" "jj st && jj log --limit 15"];
      ll = ["log" "-T" "log_with_files"];
      lc = ["log" "-T" "log_compact"];
      tug = ["bookmark" "move" "--from" "heads(::@ & bookmarks())" "--to" "closest_pushable(@)"];
      # TODO: not yet working
      mr = [
        "util"
        "exec"
        "--"
        "sh"
        "-c"
        "gh pr create --head $(jj log -r 'closest_bookmark(@)' -T 'bookmarks' --no-graph | cut -d ' ' -f 1)"
      ];
    };

    revset-aliases = {
      "closest_bookmark(to)" = "heads(::to & bookmarks())";
      "closest_nonempty(to)" = "heads(::to ~ empty())";
      "recent_work" = "ancestors(visible_heads(), 3) & mutable()";
      "closest_pushable(to)" = ''heads(::to & mutable() & ~description(exact:" ") & (~empty() | merges()))'';
    };

    templates = {
      # This override of the log_node template returns a hollow diamond if the
      # change meets some pushable criteria, and otherwise returns the
      # builtin_log_node, which is the regular icon.
      log_node = ''
        if(self && !current_working_copy && !immutable && !conflict && in_branch(self),
          "◇",
          builtin_log_node
        )
      '';

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

    template-aliases = {
      # from https://andre.arko.net/2025/09/28/stupid-jj-tricks/
      "in_branch(commit)" = ''commit.contained_in("immutable_heads()..bookmarks()")'';

      log_with_files = ''
        if(
          root,
          format_root_commit(self),
          label(
            if(current_working_copy, "working_copy"),
            concat(
              format_short_commit_header(self) ++ "\n",
              separate(" ",
                if(empty, label("empty", "(empty)")),
                if(
                  description,
                  description.first_line(),
                  label(if(empty, "empty"), description_placeholder),
                ),
              ) ++ "\n",
              if(self.contained_in("recent_work"), diff.summary()),
            ),
          )
        )
      '';

      log_compact = ''
        if(
          root,
          format_root_commit(self),
          label(
            if(current_working_copy, "working_copy"),
            concat(
              separate(" ",
                format_short_change_id_with_hidden_and_divergent_info(self),
                if(empty, label("empty", "(empty)")),
                if(
                  description,
                  description.first_line(),
                  label(if(empty, "empty"), description_placeholder),
                ),
                bookmarks,
                tags,
                working_copies,
                if(git_head, label("git_head", "HEAD")),
                if(conflict, label("conflict", "conflict")),
                if(
                  config("ui.show-cryptographic-signatures").as_boolean(),
                  format_short_cryptographic_signature(signature)
                ),
                if(!description && !empty, "\n" ++ diff.summary()),
              ) ++ "\n",
            ),
          )
        )
      '';
    };
  };
}
