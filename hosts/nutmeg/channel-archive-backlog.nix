{ ... }:
{
  services.channelArchive = {
    channels."okarin-games" = {  # 1419 vids — needs cookies (heavy backfill)
      enable = false;
      url = "https://www.youtube.com/channel/UC4NplzfMrGpD8UYBqRpQ4oA/videos";
      destination = "/mnt/channels/videos/おかりん - OkarinGames";
      rateLimit = true;
    };
    channels."yanmo-splat-ch" = {  # 1128 vids — needs cookies (heavy backfill)
      enable = false;
      url = "https://www.youtube.com/channel/UC1n5554otlE3evhll_RH1Kg/videos";
      destination = "/mnt/channels/videos/やんもスプラch";
      rateLimit = true;
    };
    channels."kenshiro-salmonrun" = {  # 355 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCq8lZDyLorG0qRR4XUMYD1A/videos";
      destination = "/mnt/channels/videos/Kenshiro SalmonRun けんしろ";
      rateLimit = true;
    };
    channels."on-creating-games" = {  # 275 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCv1DvRY5PyHHt3KN9ghunuw/videos";
      destination = "/mnt/channels/videos/Masahiro Sakurai on Creating Games";
      rateLimit = true;
    };
    channels."smallant" = {  # 255 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC0VVYtw21rg2cokUystu2Dw/videos";
      destination = "/mnt/channels/videos/SmallAnt";
      rateLimit = true;
    };
    channels."shu3" = {  # 230 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCO-n0T-9rJ4f6smFPK3vFiQ/videos";
      destination = "/mnt/channels/videos/shu3";
      rateLimit = true;
    };
    channels."walter-no" = {  # 230 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCbOPMX9iWXlulmbNXrz6oLw/videos";
      destination = "/mnt/channels/videos/WaLter .NO";
      rateLimit = true;
    };
    channels."peco" = {  # 227 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCiHRLXRO262KdNSW_GcJVog/videos";
      destination = "/mnt/channels/videos/Peco";
      rateLimit = true;
    };
    channels."ryukahr" = {  # 221 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCNUzWfHUP_iXZ1GMHz8gBgw/videos";
      destination = "/mnt/channels/videos/ryukahr";
      rateLimit = true;
    };
    channels."wadelyjp" = {  # 195 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC-W9VjjLHfdTF3Nlvoy6G0Q/videos";
      destination = "/mnt/channels/videos/wadelyjp";
      rateLimit = true;
    };
    channels."the-noble-demon" = {  # 178 vids
      enable = true;
      url = "https://www.youtube.com/channel/UC90yjMp6aeAOy1BdWQR6Szw/videos";
      destination = "/mnt/channels/music/The Noble Demon";
      rateLimit = true;
    };
    channels."videogamedunkey" = {  # 157 vids
      enable = true;
      url = "https://www.youtube.com/channel/UCsvn_Po0SmunchJYOWpOxMg/videos";
      destination = "/mnt/channels/videos/videogamedunkey";
      rateLimit = true;
    };
    channels."ph1lza" = {  # 156 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCvsdQrg8SkOvS2WiVXA5S4A/videos";
      destination = "/mnt/channels/maybe-delete/Ph1LzA";
      rateLimit = true;
    };
    channels."game-center-cx-20th" = {  # 144 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCFBkdFQ3iYvh882EjPnreYw/videos";
      destination = "/mnt/channels/videos/【公式】ゲームセンターCX 20th チャンネル";
      rateLimit = true;
    };
    channels."darkness-yamamoto" = {  # 142 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC8Md6Zy3HPN5rHWKhm5qhqg/videos";
      destination = "/mnt/channels/videos/ダークネス山本";
      rateLimit = true;
    };
    channels."alice-games-music" = {  # 123 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCi4ryIObWKmmlDK1dhaGJ1A/videos";
      destination = "/mnt/channels/music/ALICE GAMES - MUSIC";
      rateLimit = true;
    };
    channels."darkness-yamamoto-2" = {  # 100 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCeKnDG3tNeOqlwsiRZyEZog/videos";
      destination = "/mnt/channels/videos/ダークネス山本2";
      rateLimit = true;
    };
    channels."dunk-tank" = {  # 96 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCGiJeCKTVKIxtaYZOidh19g/videos";
      destination = "/mnt/channels/videos/Dunk Tank";
      rateLimit = true;
    };
    channels."splashx" = {  # 57 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCOoNm5b1iDljFmYW-MYmeRA/videos";
      destination = "/mnt/channels/music/SplashX";
      rateLimit = true;
    };
    channels."summoning-salt" = {  # 51 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCtUbO6rBht0daVIOGML3c8w/videos";
      destination = "/mnt/channels/videos/Summoning Salt";
      rateLimit = true;
    };
    channels."f4mi" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCSWMraguMlNanVQgseTTr_Q/videos";
      destination = "/mnt/channels/music/f4mi";
      rateLimit = true;
    };
    channels."kukun-kun" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCuXH9J-zamUAOJPYc_nAQrA/videos";
      destination = "/mnt/channels/videos/kukun kun";
      rateLimit = true;
    };
    channels."yamatake" = {  # 34 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC1nvMNnbZY0hfHXAEdTCD0w/videos";
      destination = "/mnt/channels/videos/やまたけ「";
      rateLimit = true;
    };
    channels."vivivgm" = {  # 2564 vids — needs cookies (heavy backfill)
      enable = false;
      url = "https://www.youtube.com/channel/UCyMXuuk-eHgkLuaa6L95iMg/videos";
      destination = "/mnt/channels/music/ViviVGM";
      rateLimit = true;
    };
    channels."falkkone" = {  # 1001 vids — needs cookies (heavy backfill)
      enable = false;
      url = "https://www.youtube.com/channel/UChAHYPBvyaQIpjyTSdQhOMQ/videos";
      destination = "/mnt/channels/music/FalKKonE";
      rateLimit = true;
    };
    channels."marasy8" = {  # 487 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCcvLSRIWJIAGFDyWtzkbiHA/videos";
      destination = "/mnt/channels/music/marasy8";
      rateLimit = true;
    };
    channels."jonathan-young" = {  # 453 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC40gs0opj389ohjLnJIAJzA/videos";
      destination = "/mnt/channels/music/Jonathan Young";
      rateLimit = true;
    };
    channels."glitchxcity" = {  # 376 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC-lmdv0OTb4uQQSzwbzhLsg/videos";
      destination = "/mnt/channels/music/GlitchxCity";
      rateLimit = true;
    };
    channels."leeandlie-amalee" = {  # 363 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC8THb_fnOptyVgpi3xuCd-A/videos";
      destination = "/mnt/channels/music/LeeandLie (AmaLee)";
      rateLimit = true;
    };
    channels."annapantsu" = {  # 336 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCmuobr4DmrmLI1BaGZD3p5w/videos";
      destination = "/mnt/channels/music/annapantsu";
      rateLimit = true;
    };
    channels."jammin-sam-miller" = {  # 317 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCKaTWjXt6tJ9S6K0YFJVEfQ/videos";
      destination = "/mnt/channels/music/Jammin' Sam Miller";
      rateLimit = true;
    };
    channels."jubyphonic" = {  # 292 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCMsNS10PzxzEayT7UHS4p6g/videos";
      destination = "/mnt/channels/music/JubyPhonic";
      rateLimit = true;
    };
    channels."loeder" = {  # 286 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCg4w2hQ-Bqn9Z4VhqrV8X9Q/videos";
      destination = "/mnt/channels/music/Loeder";
      rateLimit = true;
    };
    channels."mewmore" = {  # 272 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCjfK3raSgrUD0Llq-j25YLg/videos";
      destination = "/mnt/channels/music/Mewmore";
      rateLimit = true;
    };
    channels."supershigi" = {  # 247 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCaYNVIORCDQ30YKHlCbFkCQ/videos";
      destination = "/mnt/channels/music/supershigi";
      rateLimit = true;
    };
    channels."kokoko6891" = {  # 241 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCIMdJx2EBZKydtSajPZwjVg/videos";
      destination = "/mnt/channels/music/kokoko6891";
      rateLimit = true;
    };
    channels."lizz-robinett" = {  # 240 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCq36dja_0U4SgB3wYVtr_Zw/videos";
      destination = "/mnt/channels/music/Lizz Robinett";
      rateLimit = true;
    };
    channels."smooth-mcgroove" = {  # 232 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCJvBEEqTaLaKclbCPgIjBSQ/videos";
      destination = "/mnt/channels/music/Smooth McGroove";
      rateLimit = true;
    };
    channels."active-neets" = {  # 226 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCYWJTcV_8ceDND5q4AJHiVQ/videos";
      destination = "/mnt/channels/music/Active NEETs";
      rateLimit = true;
    };
    channels."astrophysics" = {  # 225 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCWSC_-y9QsDmACXRY3rvtsQ/videos";
      destination = "/mnt/channels/music/Astrophysics";
      rateLimit = true;
    };
    channels."caleb-hyles" = {  # 205 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCmkTBtGbf0gSPnHN_slNrOQ/videos";
      destination = "/mnt/channels/music/Caleb Hyles";
      rateLimit = true;
    };
    channels."rush-garcia" = {  # 194 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCm2GrZjyqP5pF-wTa95r_AA/videos";
      destination = "/mnt/channels/music/Rush Garcia";
      rateLimit = true;
    };
    channels."alice-peralta" = {  # 185 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC05GmFj6cGE9mJoTl0dMdBg/videos";
      destination = "/mnt/channels/music/Alice Peralta";
      rateLimit = true;
    };
    channels."malinda" = {  # 136 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC8Zo5A8qICfNAzVGDY_VT7w/videos";
      destination = "/mnt/channels/music/MALINDA";
      rateLimit = true;
    };
    channels."lollia" = {  # 128 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCa9_8C9ebEphjva-P7OV7bA/videos";
      destination = "/mnt/channels/music/Lollia";
      rateLimit = true;
    };
    channels."warner-classics" = {  # 117 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC1pfwysp1EC5P4qE-Eo97HA/videos";
      destination = "/mnt/channels/music/Warner Classics";
      rateLimit = true;
    };
    channels."insaneintherainmusic" = {  # 116 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC_OtnV-9QZmBj6oWBelMoZw/videos";
      destination = "/mnt/channels/music/insaneintherainmusic";
      rateLimit = true;
    };
    channels."look-mum-no-computer" = {  # 107 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCafxR2HWJRmMfSdyZXvZMTw/videos";
      destination = "/mnt/channels/music/LOOK MUM NO COMPUTER";
      rateLimit = true;
    };
    channels."sully-orchestration" = {  # 102 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCmoIM2c1E_5dI7-ZDnFXJkQ/videos";
      destination = "/mnt/channels/music/Sully Orchestration";
      rateLimit = true;
    };
    channels."vetrom" = {  # 99 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCc8Z-QX87IY--16O9unVXpQ/videos";
      destination = "/mnt/channels/music/Vetrom";
      rateLimit = true;
    };
    channels."mama-symphonia" = {  # 83 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCUDPidlY7U0ULkZUTnJcTGQ/videos";
      destination = "/mnt/channels/music/Mama Symphonia";
      rateLimit = true;
    };
    channels."richaadeb" = {  # 75 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCPM1bCbT-dVAHAEIpUUpVLQ/videos";
      destination = "/mnt/channels/music/RichaadEB";
      rateLimit = true;
    };
    channels."give-heart-records" = {  # 68 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCAKdbp1bKIdjqjRLIKvXCRA/videos";
      destination = "/mnt/channels/music/Give Heart Records";
      rateLimit = true;
    };
    channels."dyltheis-productions" = {  # 58 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCF3n4iozc9ixXkfQ714vNEA/videos";
      destination = "/mnt/channels/music/DylTheis Productions";
      rateLimit = true;
    };
    channels."sixteen-in-mono" = {  # 54 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCb1gWOLQPCgUl_WY-zSvL7A/videos";
      destination = "/mnt/channels/music/SixteenInMono";
      rateLimit = true;
    };
    channels."the-second-narrator" = {  # 53 vids
      enable = false;
      url = "https://www.youtube.com/channel/UChcmd07Qpsl9AG58GeLnldQ/videos";
      destination = "/mnt/channels/music/The Second Narrator Music";
      rateLimit = true;
    };
    channels."happy-dragonite" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCT2BUnGjc2C_ZTUVzCEUHyA/videos";
      destination = "/mnt/channels/music/HappyDragonite";
      rateLimit = true;
    };
    channels."vanilluxe-pavilion" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCW3UeF_dWeNxbfMScx-v37g/videos";
      destination = "/mnt/channels/music/VanilluxePavilion";
      rateLimit = true;
    };
    channels."theophanyremix" = {  # 30 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCi3-9JwIykiwis4rrBKrDwg/videos";
      destination = "/mnt/channels/music/TheophanyRemix";
      rateLimit = true;
    };
    channels."mammatune" = {  # 21 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCAMuDTJHAv0mrIty1lcxkmA/videos";
      destination = "/mnt/channels/music/mammaTune";
      rateLimit = true;
    };
    channels."louie-zong" = {  # 362 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCdkkQvJoB0kGgYHCYwSkdww/videos";
      destination = "/mnt/channels/music/Louie Zong";
      rateLimit = true;
    };
    channels."amaury-guichon" = {  # 158 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC0fvGpDXi7sV2hbgD-O47yw/videos";
      destination = "/mnt/channels/videos/Amaury Guichon";
      rateLimit = true;
    };
    channels."namuzu" = {  # 145 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCKgoRPEs0r01H3d7bwd19gg/videos";
      destination = "/mnt/channels/music/The NAMUZU";
      rateLimit = true;
    };
    channels."simone-giertz" = {  # 126 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC3KEoMzNz8eYnwBC34RaKCQ/videos";
      destination = "/mnt/channels/videos/Simone Giertz";
      rateLimit = true;
    };
    channels."asianometry" = {  # 114 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC1LpsuAUaKoMzzJSEt5WImw/videos";
      destination = "/mnt/channels/videos/Asianometry";
      rateLimit = true;
    };
    channels."its-time-to-travel" = {  # 101 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCQDKpfTS6haXS6BAHebR8Hw/videos";
      destination = "/mnt/channels/videos/It's Time to Travel🇯🇵 - 旅する時間";
      rateLimit = true;
    };
    channels."john-sandwich" = {  # 78 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC9aYv-TebxoXw8Isi3MEGdg/videos";
      destination = "/mnt/channels/videos/John Sandwich";
      rateLimit = true;
    };
    channels."project-mstie" = {  # 78 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCUaXf7gH3Q8y8tFEJGwTMJQ/videos";
      destination = "/mnt/channels/maybe-delete/Project MSTie";
      rateLimit = true;
    };
    channels."technology-connections" = {  # 72 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCy0tKL1T7wFoYcxCe0xjN6Q/videos";
      destination = "/mnt/channels/videos/Technology Connections";
      rateLimit = true;
    };
    channels."cathode-ray-dude" = {  # 70 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCXnNibvR_YIdyPs8PZIBoEw/videos";
      destination = "/mnt/channels/videos/Cathode Ray Dude - CRD";
      rateLimit = true;
    };
    channels."leahbee" = {  # 59 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCq7D2jqBfjse5M18CaLlTjA/videos";
      destination = "/mnt/channels/videos/Leahbee";
      rateLimit = true;
    };
    channels."tom-scott" = {  # 50 vids
      enable = false;
      url = "https://www.youtube.com/channel/UCBa659QWEk1AI4Tg--mrJ2A/videos";
      destination = "/mnt/channels/videos/Tom Scott";
      rateLimit = true;
    };
    channels."harrypottercentral" = {  # 34 vids
      enable = false;
      url = "https://www.youtube.com/channel/UC6BFuqF6-l_Y2aDZmyuzqXA/videos";
      destination = "/mnt/channels/videos/HarryPotterCentral";
      rateLimit = true;
    };
    channels."timelab-pro" = {  # 30 vids
      enable = true;
      url = "https://www.youtube.com/channel/UC6zl_U-HEajk9JSHkuTlaZQ/videos";
      destination = "/mnt/channels/videos/Timelab Pro";
      rateLimit = true;
    };
    channels."villainous" = {  # 22 vids
      enable = true;
      url = "https://www.youtube.com/channel/UCmJHqZAxWDtCzAI26wvUw_Q/videos";
      destination = "/mnt/channels/music/VILLAINOUS";
      rateLimit = true;
    };
  };
}
