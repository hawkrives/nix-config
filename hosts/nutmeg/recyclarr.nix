{ config, ... }:
{
  # Bare-key secrets (raw value, no KEY= prefix) — recyclarr's `_secret`
  # LoadCredential substitution wants the key itself. Same keys as the
  # *-api-key.age env-files used by radarr/sonarr, just unwrapped.
  age.secrets.radarr-api-key-bare.file = ../../secrets/radarr-api-key-bare.age;
  age.secrets.sonarr-api-key-bare.file = ../../secrets/sonarr-api-key-bare.age;

  # Rebuilt for recyclarr 8.6.0, which removed the old `include:` template system
  # entirely. Profiles are now pulled by trash_id (which yields the current
  # trash-guides names) and custom formats come from `custom_format_groups`
  # mirroring what the matching templates enable by default. base_url → localhost,
  # api_key → ragenix `_secret`. On its daily schedule recyclarr syncs these INTO
  # the live radarr/sonarr. The only non-template piece is the manual
  # "Remux-2160p - Anime" sonarr profile, carried over from the old config.
  services.recyclarr = {
    enable = true;

    configuration = {
      sonarr.series = {
        base_url = "http://localhost:8989";
        api_key._secret = config.age.secrets.sonarr-api-key-bare.path;

        quality_definition.type = "series";

        media_naming = {
          series = "plex-tvdb";
          season = "default";
          episodes = {
            rename = true;
            standard = "default";
            daily = "default";
            anime = "default";
          };
        };

        quality_profiles = [
          { trash_id = "9d142234e45d6143785ac55f5a9e8dc9"; reset_unmatched_scores.enabled = true; } # WEB-1080p (Alternative)
          { trash_id = "dfa5eaae7894077ad6449169b6eb03e0"; reset_unmatched_scores.enabled = true; } # WEB-2160p (Alternative)
          { trash_id = "20e0fc959f1f1704bed501f23bdae76f"; reset_unmatched_scores.enabled = true; } # [Anime] Remux-1080p
          {
            # Carried over from the old config — not a trash-guides template.
            # Named to match the guide's "[Anime] Remux-1080p" format.
            name = "[Anime] Remux-2160p";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-2160p";
              until_score = 10000;
            };
            score_set = "anime-sonarr";
            quality_sort = "top";
            qualities = [
              {
                name = "Bluray-2160p";
                qualities = [
                  "Bluray-2160p Remux"
                  "Bluray-2160p"
                ];
              }
              {
                name = "WEB 2160p";
                qualities = [
                  "WEBDL-2160p"
                  "WEBRip-2160p"
                  "HDTV-2160p"
                ];
              }
              {
                name = "Bluray-1080p";
                qualities = [
                  "Bluray-1080p Remux"
                  "Bluray-1080p"
                ];
              }
              {
                name = "WEB 1080p";
                qualities = [
                  "WEBDL-1080p"
                  "WEBRip-1080p"
                  "HDTV-1080p"
                ];
              }
              { name = "Bluray-720p"; }
              {
                name = "WEB 720p";
                qualities = [
                  "WEBDL-720p"
                  "WEBRip-720p"
                  "HDTV-720p"
                ];
              }
              { name = "Bluray-480p"; }
              {
                name = "WEB 480p";
                qualities = [
                  "WEBDL-480p"
                  "WEBRip-480p"
                ];
              }
              { name = "DVD"; }
              { name = "SDTV"; }
            ];
          }
        ];

        # Union of the web-1080p-alternative + web-2160p-alternative templates'
        # default-active groups (the anime template enables none).
        custom_format_groups.add = [
          {
            trash_id = "158188097a58d7687dee647e04af0da3"; # [Optional] Golden Rule HD
            select = [ "47435ece6b99a0b477caf360e79ba0bb" ]; # x265 (HD)
          }
          {
            trash_id = "e3f37512790f00d0e89e54fe5e790d1c"; # [Optional] Golden Rule UHD
            select = [ "9b64dff695c2115facf1b6ea59c9bd07" ]; # x265 (no HDR/DV)
          }
          {
            # Both members (HD/UHD Streaming Boost) are required CFs, so they're
            # auto-included — no `select` needed (selecting them warns as redundant).
            trash_id = "85fae4a2294965b75710ef2989c850eb"; # [Streaming Services] HD/UHD boost
          }
          {
            trash_id = "59c3af66780d08332fdc64e68297098f"; # [Unwanted] Unwanted Formats
            select = [
              "15a05bc7c1a36e2b57fd628f8977e2fc" # AV1
              "32b367365729d530ca1c124a0b180c64" # Bad Dual Groups
              "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
              "6f808933a71bd9666531610cb8c059cc" # BR-DISK (BTN)
              "fbcb31d8dabd2a319072b84fc0b7249c" # Extras
              "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
              "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
              "23297a736ca77c0fc8e70f8edd7ee56c" # Upscaled
            ];
          }
        ];
      };

      radarr.movies = {
        base_url = "http://localhost:7878";
        api_key._secret = config.age.secrets.radarr-api-key-bare.path;

        quality_definition.type = "movie";

        delete_old_custom_formats = true;

        media_naming = {
          folder = "plex-tmdb";
          movie = {
            rename = true;
            standard = "plex-tmdb";
          };
        };

        quality_profiles = [
          { trash_id = "d1d67249d3890e49bc12e275d989a7e9"; reset_unmatched_scores.enabled = true; } # HD Bluray + WEB
          { trash_id = "64fb5f9858489bdac2af690e27c8f42f"; reset_unmatched_scores.enabled = true; } # UHD Bluray + WEB
          { trash_id = "9ca12ea80aa55ef916e3751f4b874151"; reset_unmatched_scores.enabled = true; } # Remux + WEB 1080p
          { trash_id = "fd161a61e3ab826d3a22d53f935696dd"; reset_unmatched_scores.enabled = true; } # Remux + WEB 2160p
          { trash_id = "722b624f9af1e492284c4bc842153a38"; reset_unmatched_scores.enabled = true; } # [Anime] Remux-1080p
        ];

        # The hd/uhd-bluray-web + remux-web-1080p/2160p templates all share the
        # same two default-active groups (Golden Rule + Unwanted Formats).
        custom_format_groups.add = [
          {
            trash_id = "f8bf8eab4617f12dfdbd16303d8da245"; # [Optional] Golden Rule HD
            select = [ "dc98083864ea246d05a42df0d05f81cc" ]; # x265 (HD)
          }
          {
            trash_id = "ff204bbcecdd487d1cefcefdbf0c278d"; # [Optional] Golden Rule UHD
            select = [ "839bea857ed2c0a8e084f3cbdbd65ecb" ]; # x265 (no HDR/DV)
          }
          {
            trash_id = "a3ac6af01d78e4f21fcb75f601ac96df"; # [Unwanted] Unwanted Formats
            select = [
              "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
              "cae4ca30163749b891686f95532519bd" # AV1
              "b6832f586342ef70d9c128d40c07b872" # Bad Dual Groups
              "cc444569854e9de0b084ab2b8b1532b2" # Black and White Editions
              "ed38b889b31be83fda192888e2286d83" # BR-DISK
              "0a3f082873eb454bde444150b70253cc" # Extras
              "e6886871085226c3da1830830146846c" # Generated Dynamic HDR
              "90a6f9a284dff5103f6346090e6280c8" # LQ
              "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
              "712d74cd88bceb883ee32f773656b1f5" # Sing-Along Versions
              "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
            ];
          }
        ];
      };
    };
  };
}
