#!/usr/bin/env python3
"""Generate + upload a channel's show/season/background artwork to Plex, once.
Ships with the channelArchive module; runs (best-effort) after restructure.py.
Idempotent: only generates what's missing (avatar.jpg, poster.jpg, per-season
poster.jpg, background.jpg), so first run creates everything and later runs only
fill in a newly-appeared season.

  <dest>/avatar.jpg      raw square channel avatar (fetched once; Twitch: skipped)
  <dest>/poster.jpg      show poster = dimmed blurred bg + inset avatar (2:3)
  <dest>/Season YYYY/poster.jpg  2023-style season poster (avatar top, year band)
  <dest>/background.jpg  channel banner (fanart/art)

Args: channel-artwork.py <dest> [--section N --url URL --token-file PATH]
Needs `magick` (ImageMagick), `yt-dlp`, and a DejaVuSans-Bold.ttf on disk.
"""
import os, re, glob, json, subprocess, sys, argparse, urllib.request

FONTB = os.environ.get("CAW_FONT") or subprocess.run(
    ["bash", "-c", "find /nix/store -name DejaVuSans-Bold.ttf 2>/dev/null | head -1"],
    capture_output=True, text=True).stdout.strip()


def sh(script):
    subprocess.run(["bash", "-c", script], capture_output=True)


def channel_info(dest):
    """(platform, channel_url) from the first Season episode's info.json."""
    for ij in glob.glob(dest + "/Season */*.info.json"):
        try:
            d = json.load(open(ij, encoding="utf-8"))
        except Exception:
            continue
        plat = "twitch" if "twitch" in (d.get("extractor") or "").lower() else "youtube"
        cid = d.get("channel_id")
        url = d.get("channel_url") or (f"https://www.youtube.com/channel/{cid}" if cid else None)
        return plat, url
    return "youtube", None


def thumbs_of(url):
    r = subprocess.run(["yt-dlp", "--dump-single-json", "--playlist-items", "0", "--no-warnings", url],
                       capture_output=True, text=True, timeout=120)
    try:
        return (json.loads(r.stdout).get("thumbnails")) or []
    except Exception:
        return []


def pick_avatar(ts):
    av = [t for t in ts if "avatar" in str(t.get("id", "")).lower() and t.get("url")]
    if av:
        return max(av, key=lambda t: t.get("width", 0))["url"]
    sq = [t for t in ts if t.get("width") and t.get("height") and 0.8 <= t["width"] / t["height"] <= 1.25]
    pool = sq or [t for t in ts if t.get("url")]
    return max(pool, key=lambda t: t.get("width", 0))["url"] if pool else None


def pick_banner(ts):
    bn = [t for t in ts if t.get("width") and t.get("height")
          and (str(t.get("id", "")).lower().startswith("banner") or t["width"] / max(t["height"], 1) >= 2.0)]
    return max(bn, key=lambda t: t.get("width", 0))["url"] if bn else None


def api(url, token, path, method="GET", data=None):
    sep = "&" if "?" in path else "?"
    req = urllib.request.Request(f"{url}{path}{sep}X-Plex-Token={token}", data=data, method=method,
                                 headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        body = r.read()
        return json.loads(body) if body and method == "GET" else r.status


def post_art(url, token, rk, kind, img):
    with open(img, "rb") as f:
        data = f.read()
    return api(url, token, f"/library/metadata/{rk}/{kind}", method="POST", data=data)


def show_poster(avatar, out):
    sh(f'magick "{avatar}" -resize 1000x1500^ -gravity center -extent 1000x1500 -blur 0x30 -modulate 42 /tmp/_caw_bg.jpg; '
       f'magick /tmp/_caw_bg.jpg \\( "{avatar}" -resize 900x900 \\) -gravity center -composite "{out}"')


def season_poster(avatar, label, out):
    ps = "165" if label.isdigit() else "115"
    sh(f'magick -size 1000x1500 xc:black \\( "{avatar}" -resize 1000x1000 \\) -gravity north -geometry +0+0 -composite /tmp/_caw_gb.png; '
       f'magick -size 1000x500 xc:black -font "{FONTB}" -pointsize {ps} -fill white -gravity center -annotate +0+7 "{label}" /tmp/_caw_band.png; '
       f'magick /tmp/_caw_gb.png /tmp/_caw_band.png -gravity south -composite "{out}"')


def run(dest, section, url, token):
    dest = dest.rstrip("/")
    folder = os.path.basename(dest)
    avatar = dest + "/avatar.jpg"
    plat, ch_url = channel_info(dest)
    ts = thumbs_of(ch_url) if ch_url else []

    # avatar (fetch once; Twitch has none via yt-dlp -> leave for a user-supplied file)
    if not os.path.exists(avatar) and ts:
        av_url = pick_avatar(ts)
        if av_url:
            try:
                urllib.request.urlretrieve(av_url, "/tmp/_caw_av")
                sh(f'magick /tmp/_caw_av -resize 900x900^ -gravity center -extent 900x900 "{avatar}"')
            except Exception as e:
                print(f"channel-artwork: avatar fetch failed: {e}", file=sys.stderr)

    if not (section and url and token):
        return  # no Plex target -> filesystem-only avatar fetch done

    # locate the Plex show for this folder
    try:
        shows = api(url, token, f"/library/sections/{section}/all").get("MediaContainer", {}).get("Metadata", [])
        srk = None
        for s in shows:
            leaves = api(url, token, f"/library/metadata/{s['ratingKey']}/allLeaves").get("MediaContainer", {}).get("Metadata", [])
            if leaves and f"/{folder}/" in (leaves[0].get("Media", [{}])[0].get("Part", [{}])[0].get("file", "")):
                srk = s["ratingKey"]; break
        if srk is None:
            return
        # show poster
        if os.path.exists(avatar) and not os.path.exists(dest + "/poster.jpg"):
            show_poster(avatar, dest + "/poster.jpg")
            post_art(url, token, srk, "posters", dest + "/poster.jpg")
        # season posters (each Plex season missing a local poster)
        if os.path.exists(avatar):
            for s in api(url, token, f"/library/metadata/{srk}/children").get("MediaContainer", {}).get("Metadata", []):
                idx = s.get("index")
                if idx is None:
                    continue
                sdir = f"{dest}/Season {'00' if idx == 0 else idx}"
                if os.path.isdir(sdir) and not os.path.exists(sdir + "/poster.jpg"):
                    label = "Specials" if idx == 0 else str(idx)
                    season_poster(avatar, label, sdir + "/poster.jpg")
                    post_art(url, token, s["ratingKey"], "posters", sdir + "/poster.jpg")
        # background from banner
        if not os.path.exists(dest + "/background.jpg"):
            bn = pick_banner(ts)
            if bn:
                try:
                    urllib.request.urlretrieve(bn, "/tmp/_caw_bn")
                    sh(f'magick /tmp/_caw_bn "{dest}/background.jpg"')
                    post_art(url, token, srk, "arts", dest + "/background.jpg")
                except Exception as e:
                    print(f"channel-artwork: banner failed: {e}", file=sys.stderr)
    except Exception as e:
        print(f"channel-artwork: skipped ({e})", file=sys.stderr)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("dest")
    ap.add_argument("--section"); ap.add_argument("--url"); ap.add_argument("--token-file")
    a = ap.parse_args(argv)
    token = None
    if a.token_file and os.path.isfile(a.token_file):
        token = open(a.token_file).read().strip()
    run(a.dest, a.section, a.url, token)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
