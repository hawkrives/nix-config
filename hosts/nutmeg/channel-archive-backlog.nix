# Staged (disabled) YouTube channel backlog — the 77 channels with >=20 on-disk
# videos from the old /mnt/channels/youtube tree. All enable=false: declared for
# tracking; activate in batches by flipping enable=true AND running the NAS
# migration for that batch (see channel-archive-migrate.sh). Slugs derive from
# the channel name (UC-id fallback for non-ASCII names); friendly name is the
# destination. "needs cookies" marks 1000+/heavy channels that will trip
# YouTube's bot-check on backfill until cookie auth is added. ~51 single-video
# one-offs and 3 unavailable channels are intentionally omitted (static files).
{ ... }:
{
  services.channelArchive = {
    channels."vivivgm" = {  # 2564 vids — needs cookies (heavy backfill)
      enable = false;
      url = "https://www.youtube.com/channel/UCyMXuuk-eHgkLuaa6L95iMg/videos";
      destination = "/mnt/channels/ViviVGM";
      rateLimit = true;
    };
    channels."okaringames" = {  # 1398 vids — needs cookies (heavy backfill)
      enable = false;
      url = "https://www.youtube.com/channel/UC4NplzfMrGpD8UYBqRpQ4oA/videos";
      destination = "/mnt/channels/おかりん - OkarinGames";
      rateLimit = true;
    };
    channels."uc1n5554otle3evhll_rh1kg" = {  # 1125 vids — needs cookies (heavy backfill)
      enable = false;
      url = "https://www.youtube.com/channel/UC1n5554otlE3evhll_RH1Kg/videos";
      destination = "/mnt/channels/やんもch";
      rateLimit = true;
    };
    channels."falkkone" = {  # 1001 vids — needs cookies (heavy backfill)
      enable = false;
      url = "https://www.youtube.com/channel/UChAHYPBvyaQIpjyTSdQhOMQ/videos";
      destination = "/mnt/channels/FalKKonE";
      rateLimit = true;
    };
    channels."marasy8" = {  # 485 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCcvLSRIWJIAGFDyWtzkbiHA/videos";
      destination = "/mnt/channels/marasy8";
      rateLimit = true;
    };
    channels."jonathan-young" = {  # 453 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC40gs0opj389ohjLnJIAJzA/videos";
      destination = "/mnt/channels/Jonathan Young";
      rateLimit = true;
    };
    channels."glitchxcity" = {  # 376 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC-lmdv0OTb4uQQSzwbzhLsg/videos";
      destination = "/mnt/channels/GlitchxCity";
      rateLimit = true;
    };
    channels."leeandlie-amalee" = {  # 363 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC8THb_fnOptyVgpi3xuCd-A/videos";
      destination = "/mnt/channels/LeeandLie (AmaLee)";
      rateLimit = true;
    };
    channels."louie-zong" = {  # 362 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCdkkQvJoB0kGgYHCYwSkdww/videos";
      destination = "/mnt/channels/Louie Zong";
      rateLimit = true;
    };
    channels."kenshiro-salmonrun" = {  # 353 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCq8lZDyLorG0qRR4XUMYD1A/videos";
      destination = "/mnt/channels/Kenshiro SalmonRun けんしろ";
      rateLimit = true;
    };
    channels."annapantsu" = {  # 336 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCmuobr4DmrmLI1BaGZD3p5w/videos";
      destination = "/mnt/channels/annapantsu";
      rateLimit = true;
    };
    channels."jammin-sam-miller" = {  # 317 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCKaTWjXt6tJ9S6K0YFJVEfQ/videos";
      destination = "/mnt/channels/Jammin' Sam Miller";
      rateLimit = true;
    };
    channels."jubyphonic" = {  # 291 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCMsNS10PzxzEayT7UHS4p6g/videos";
      destination = "/mnt/channels/JubyPhonic";
      rateLimit = true;
    };
    channels."loeder" = {  # 286 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCg4w2hQ-Bqn9Z4VhqrV8X9Q/videos";
      destination = "/mnt/channels/Loeder";
      rateLimit = true;
    };
    channels."masahiro-sakurai-on-creating-games" = {  # 275 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCv1DvRY5PyHHt3KN9ghunuw/videos";
      destination = "/mnt/channels/Masahiro Sakurai on Creating Games";
      rateLimit = true;
    };
    channels."mewmore" = {  # 272 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCjfK3raSgrUD0Llq-j25YLg/videos";
      destination = "/mnt/channels/Mewmore";
      rateLimit = true;
    };
    channels."supershigi" = {  # 246 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCaYNVIORCDQ30YKHlCbFkCQ/videos";
      destination = "/mnt/channels/supershigi";
      rateLimit = true;
    };
    channels."kokoko6891" = {  # 241 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCIMdJx2EBZKydtSajPZwjVg/videos";
      destination = "/mnt/channels/kokoko6891(桂尚子)";
      rateLimit = true;
    };
    channels."lizz-robinett" = {  # 240 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCq36dja_0U4SgB3wYVtr_Zw/videos";
      destination = "/mnt/channels/Lizz Robinett";
      rateLimit = true;
    };
    channels."smallant" = {  # 236 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC0VVYtw21rg2cokUystu2Dw/videos";
      destination = "/mnt/channels/SmallAnt";
      rateLimit = true;
    };
    channels."smooth-mcgroove" = {  # 232 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCJvBEEqTaLaKclbCPgIjBSQ/videos";
      destination = "/mnt/channels/Smooth McGroove";
      rateLimit = true;
    };
    channels."peco" = {  # 226 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCiHRLXRO262KdNSW_GcJVog/videos";
      destination = "/mnt/channels/Peco";
      rateLimit = true;
    };
    channels."tokyo-active-neets" = {  # 226 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCYWJTcV_8ceDND5q4AJHiVQ/videos";
      destination = "/mnt/channels/Tokyo Active NEETs";
      rateLimit = true;
    };
    channels."astrophysics" = {  # 223 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCWSC_-y9QsDmACXRY3rvtsQ/videos";
      destination = "/mnt/channels/Astrophysics";
      rateLimit = true;
    };
    channels."ryukahr" = {  # 220 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCNUzWfHUP_iXZ1GMHz8gBgw/videos";
      destination = "/mnt/channels/ryukahr";
      rateLimit = true;
    };
    channels."shu3" = {  # 220 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCO-n0T-9rJ4f6smFPK3vFiQ/videos";
      destination = "/mnt/channels/shu3";
      rateLimit = true;
    };
    channels."caleb-hyles" = {  # 205 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCmkTBtGbf0gSPnHN_slNrOQ/videos";
      destination = "/mnt/channels/Caleb Hyles";
      rateLimit = true;
    };
    channels."wadelyjp" = {  # 195 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC-W9VjjLHfdTF3Nlvoy6G0Q/videos";
      destination = "/mnt/channels/wadelyjp";
      rateLimit = true;
    };
    channels."rush-garcia" = {  # 194 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCm2GrZjyqP5pF-wTa95r_AA/videos";
      destination = "/mnt/channels/Rush Garcia";
      rateLimit = true;
    };
    channels."walter-no" = {  # 187 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCbOPMX9iWXlulmbNXrz6oLw/videos";
      destination = "/mnt/channels/WaLter .NO";
      rateLimit = true;
    };
    channels."alice-peralta" = {  # 185 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC05GmFj6cGE9mJoTl0dMdBg/videos";
      destination = "/mnt/channels/Alice Peralta";
      rateLimit = true;
    };
    channels."the-noble-demon" = {  # 178 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC90yjMp6aeAOy1BdWQR6Szw/videos";
      destination = "/mnt/channels/The Noble Demon";
      rateLimit = true;
    };
    channels."amaury-guichon" = {  # 157 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC0fvGpDXi7sV2hbgD-O47yw/videos";
      destination = "/mnt/channels/Amaury Guichon";
      rateLimit = true;
    };
    channels."videogamedunkey" = {  # 157 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCsvn_Po0SmunchJYOWpOxMg/videos";
      destination = "/mnt/channels/videogamedunkey";
      rateLimit = true;
    };
    channels."ph1lza" = {  # 150 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCvsdQrg8SkOvS2WiVXA5S4A/videos";
      destination = "/mnt/channels/Ph1LzA";
      rateLimit = true;
    };
    channels."the-namuzu" = {  # 145 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCKgoRPEs0r01H3d7bwd19gg/videos";
      destination = "/mnt/channels/The NAMUZU";
      rateLimit = true;
    };
    channels."ucfbkdfq3iyvh882ejpnreyw" = {  # 144 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCFBkdFQ3iYvh882EjPnreYw/videos";
      destination = "/mnt/channels/【公式】ゲームセンターCX チャンネル";
      rateLimit = true;
    };
    channels."uc8md6zy3hpn5rhwkhm5qhqg" = {  # 142 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC8Md6Zy3HPN5rHWKhm5qhqg/videos";
      destination = "/mnt/channels/ダークネス山本";
      rateLimit = true;
    };
    channels."malinda" = {  # 136 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC8Zo5A8qICfNAzVGDY_VT7w/videos";
      destination = "/mnt/channels/MALINDA";
      rateLimit = true;
    };
    channels."lollia" = {  # 128 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCa9_8C9ebEphjva-P7OV7bA/videos";
      destination = "/mnt/channels/Lollia";
      rateLimit = true;
    };
    channels."simone-giertz" = {  # 126 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC3KEoMzNz8eYnwBC34RaKCQ/videos";
      destination = "/mnt/channels/Simone Giertz";
      rateLimit = true;
    };
    channels."alice-games-music" = {  # 123 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCi4ryIObWKmmlDK1dhaGJ1A/videos";
      destination = "/mnt/channels/ALICE GAMES - MUSIC";
      rateLimit = true;
    };
    channels."warner-classics" = {  # 117 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC1pfwysp1EC5P4qE-Eo97HA/videos";
      destination = "/mnt/channels/Warner Classics";
      rateLimit = true;
    };
    channels."insaneintherainmusic" = {  # 115 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC_OtnV-9QZmBj6oWBelMoZw/videos";
      destination = "/mnt/channels/insaneintherainmusic";
      rateLimit = true;
    };
    channels."asianometry" = {  # 114 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC1LpsuAUaKoMzzJSEt5WImw/videos";
      destination = "/mnt/channels/Asianometry";
      rateLimit = true;
    };
    channels."look-mum-no-computer" = {  # 107 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCafxR2HWJRmMfSdyZXvZMTw/videos";
      destination = "/mnt/channels/LOOK MUM NO COMPUTER";
      rateLimit = true;
    };
    channels."sully-orchestration" = {  # 102 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCmoIM2c1E_5dI7-ZDnFXJkQ/videos";
      destination = "/mnt/channels/Sully Orchestration";
      rateLimit = true;
    };
    channels."it-s-time-to-travel" = {  # 101 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCQDKpfTS6haXS6BAHebR8Hw/videos";
      destination = "/mnt/channels/It's Time to Travel🇯🇵 - 旅する時間";
      rateLimit = true;
    };
    channels."ucekndg3tneoqlwsirzyezog" = {  # 100 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCeKnDG3tNeOqlwsiRZyEZog/videos";
      destination = "/mnt/channels/ダークネス山本2";
      rateLimit = true;
    };
    channels."vetrom" = {  # 99 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCc8Z-QX87IY--16O9unVXpQ/videos";
      destination = "/mnt/channels/Vetrom";
      rateLimit = true;
    };
    channels."mama-symphonia" = {  # 83 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCUDPidlY7U0ULkZUTnJcTGQ/videos";
      destination = "/mnt/channels/Mama Symphonia";
      rateLimit = true;
    };
    channels."dunk-tank" = {  # 81 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCGiJeCKTVKIxtaYZOidh19g/videos";
      destination = "/mnt/channels/Dunk Tank";
      rateLimit = true;
    };
    channels."john-sandwich" = {  # 78 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC9aYv-TebxoXw8Isi3MEGdg/videos";
      destination = "/mnt/channels/John Sandwich";
      rateLimit = true;
    };
    channels."project-mstie" = {  # 78 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCUaXf7gH3Q8y8tFEJGwTMJQ/videos";
      destination = "/mnt/channels/Project MSTie";
      rateLimit = true;
    };
    channels."richaadeb" = {  # 75 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCPM1bCbT-dVAHAEIpUUpVLQ/videos";
      destination = "/mnt/channels/RichaadEB";
      rateLimit = true;
    };
    channels."technology-connections" = {  # 72 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCy0tKL1T7wFoYcxCe0xjN6Q/videos";
      destination = "/mnt/channels/Technology Connections";
      rateLimit = true;
    };
    channels."cathode-ray-dude-crd" = {  # 70 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCXnNibvR_YIdyPs8PZIBoEw/videos";
      destination = "/mnt/channels/Cathode Ray Dude - CRD";
      rateLimit = true;
    };
    channels."give-heart-records" = {  # 68 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCAKdbp1bKIdjqjRLIKvXCRA/videos";
      destination = "/mnt/channels/Give Heart Records";
      rateLimit = true;
    };
    channels."leahbee" = {  # 59 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCq7D2jqBfjse5M18CaLlTjA/videos";
      destination = "/mnt/channels/Leahbee";
      rateLimit = true;
    };
    channels."dyltheis-productions" = {  # 58 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCF3n4iozc9ixXkfQ714vNEA/videos";
      destination = "/mnt/channels/DylTheis Productions";
      rateLimit = true;
    };
    channels."splashx" = {  # 57 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCOoNm5b1iDljFmYW-MYmeRA/videos";
      destination = "/mnt/channels/SplashX";
      rateLimit = true;
    };
    channels."sixteeninmono" = {  # 54 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCb1gWOLQPCgUl_WY-zSvL7A/videos";
      destination = "/mnt/channels/SixteenInMono";
      rateLimit = true;
    };
    channels."the-second-narrator-music" = {  # 53 vids
      enable = false;
      url = "https://www.youtube.com/channel/UChcmd07Qpsl9AG58GeLnldQ/videos";
      destination = "/mnt/channels/The Second Narrator Music";
      rateLimit = true;
    };
    channels."unavailable" = {  # 52 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCfm4bBx0sW4NGAFzfGkLCMg/videos";
      destination = "/mnt/channels/(unavailable)";
      rateLimit = true;
    };
    channels."summoning-salt" = {  # 51 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCtUbO6rBht0daVIOGML3c8w/videos";
      destination = "/mnt/channels/Summoning Salt";
      rateLimit = true;
    };
    channels."f4mi" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCSWMraguMlNanVQgseTTr_Q/videos";
      destination = "/mnt/channels/f4mi";
      rateLimit = true;
    };
    channels."happydragonite" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCT2BUnGjc2C_ZTUVzCEUHyA/videos";
      destination = "/mnt/channels/HappyDragonite";
      rateLimit = true;
    };
    channels."kukun-kun" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCuXH9J-zamUAOJPYc_nAQrA/videos";
      destination = "/mnt/channels/kukun kun";
      rateLimit = true;
    };
    channels."tom-scott" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCBa659QWEk1AI4Tg--mrJ2A/videos";
      destination = "/mnt/channels/Tom Scott";
      rateLimit = true;
    };
    channels."vanilluxepavilion" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCW3UeF_dWeNxbfMScx-v37g/videos";
      destination = "/mnt/channels/VanilluxePavilion";
      rateLimit = true;
    };
    channels."unavailable-2" = {  # 48 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCU9327_ngvVzoMAmnxQXrOQ/videos";
      destination = "/mnt/channels/(unavailable)";
      rateLimit = true;
    };
    channels."harrypottercentral" = {  # 34 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC6BFuqF6-l_Y2aDZmyuzqXA/videos";
      destination = "/mnt/channels/HarryPotterCentral";
      rateLimit = true;
    };
    channels."uc1nvmnnbzy0hfhxaedtcd0w" = {  # 34 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC1nvMNnbZY0hfHXAEdTCD0w/videos";
      destination = "/mnt/channels/やまたけ「";
      rateLimit = true;
    };
    channels."theophanyremix" = {  # 30 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCi3-9JwIykiwis4rrBKrDwg/videos";
      destination = "/mnt/channels/TheophanyRemix";
      rateLimit = true;
    };
    channels."timelab-pro" = {  # 30 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC6zl_U-HEajk9JSHkuTlaZQ/videos";
      destination = "/mnt/channels/Timelab Pro";
      rateLimit = true;
    };
    channels."villainous" = {  # 22 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCmJHqZAxWDtCzAI26wvUw_Q/videos";
      destination = "/mnt/channels/VILLAINOUS";
      rateLimit = true;
    };
    channels."mammatune-pixel-art-8-bit-music-creator" = {  # 21 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCAMuDTJHAv0mrIty1lcxkmA/videos";
      destination = "/mnt/channels/mammaTune - Pixel Art & 8-bit Music Creator";
      rateLimit = true;
    };
  };
}
