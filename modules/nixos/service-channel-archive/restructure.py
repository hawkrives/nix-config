#!/usr/bin/env python3
"""Restructure a channelArchive channel dir into the date-based Plex TV layout
and (optionally) finalize the new episodes in Plex. See the design spec."""
import os, re, glob, json, sys, argparse, datetime, urllib.request, urllib.parse
from xml.sax.saxutils import escape

VEXT = (".mp4", ".mkv", ".webm")
MAX_BASE = 235  # bytes; headroom under the 255-byte filename limit


def date_of(info):
    ud = info.get("upload_date")
    if ud and len(str(ud)) == 8 and str(ud).isdigit():
        ud = str(ud)
        return ud, f"{ud[0:4]}-{ud[4:6]}-{ud[6:8]}"
    ts = info.get("timestamp") or info.get("release_timestamp")
    if isinstance(ts, (int, float)) and ts > 0:
        dt = datetime.datetime.fromtimestamp(int(ts), datetime.timezone.utc)
        return dt.strftime("%Y%m%d"), dt.strftime("%Y-%m-%d")
    return None, None


def is_clip(info):
    return "clip" in (info.get("extractor") or "").lower()


def _platform(info):
    return "twitch" if "twitch" in (info.get("extractor") or "").lower() else "youtube"


def sanitize(t):
    t = re.sub(r'[/\\:*?"<>|\x00-\x1f]', "-", t)
    return (re.sub(r"\s+", " ", t).strip().strip(".") or "Untitled")


def btrunc(s, maxb):
    b = s.encode("utf-8")[: max(maxb, 0)]
    while b:
        try:
            return b.decode("utf-8")
        except UnicodeDecodeError:
            b = b[:-1]
    return ""


def plan_episode(info, existing):
    """existing: {(season:int, ymd:str|None): max_seq_used}. Returns season/episode/token."""
    ymd, _ = date_of(info)
    clip = is_clip(info)
    if clip:
        season = 0
        base = int(ymd) if ymd else 0            # YYYYMMDD
    else:
        season = int(ymd[0:4]) if ymd else 0
        base = int(ymd[4:6]) * 100 + int(ymd[6:8]) if ymd else 0   # MMDD
    seq = existing.get((season, ymd), 0) + 1
    existing[(season, ymd)] = seq
    episode = base * 100 + seq
    if season == 0:
        token = f"S00E{ymd}{seq:02d}" if ymd else f"S00E{seq:02d}"
    else:
        token = f"S{season}E{episode:06d}"
    return {"season": season, "episode": episode, "token": token}


def build_episode_nfo(info, season, episode, aired):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', "<episodedetails>",
             f"  <title>{escape((info.get('title') or '').strip() or 'Untitled')}</title>",
             f"  <season>{season}</season>", f"  <episode>{episode}</episode>"]
    if aired:
        lines.append(f"  <aired>{escape(aired)}</aired>")
    if info.get("description"):
        lines.append(f"  <plot>{escape(info['description'])}</plot>")
    genres = [g for g in ([info.get("game")] + (info.get("categories") or [])) if g]
    genres += [c.get("title") for c in (info.get("chapters") or []) if isinstance(c, dict) and c.get("title")]
    for g in dict.fromkeys(genres):
        lines.append(f"  <genre>{escape(str(g))}</genre>")
    vid = info.get("id")
    if vid:
        lines.append(f'  <uniqueid type="{_platform(info)}" default="true">{escape(str(vid))}</uniqueid>')
    lines += ["</episodedetails>", ""]
    return "\n".join(lines)


def _existing_seqs(dest):
    """Scan Season dirs for used within-day seqs so new eps append."""
    existing = {}
    for sd in glob.glob(dest + "/Season *"):
        m = re.search(r"Season (\d+)", os.path.basename(sd))
        if not m:
            continue
        season = int(m.group(1))
        for f in os.listdir(sd):
            mm = re.search(r" - S\d+E(\d+) - ", f)
            if not mm:
                continue
            num = mm.group(1)
            if season == 0:
                if len(num) >= 10:          # S00E<YYYYMMDD><NN>
                    ymd, seq = num[:8], int(num[8:10])
                else:                        # S00E<NN> (undated)
                    ymd, seq = None, int(num)
            else:
                # MMDDSS -> ymd key needs the year (season) + MMDD
                mmdd, seq = num[:-2], int(num[-2:])
                ymd = f"{season}{int(mmdd):04d}"
            existing[(season, ymd)] = max(existing.get((season, ymd), 0), seq)
    return existing


def restructure_dir(dest):
    dest = dest.rstrip("/")
    folder = os.path.basename(dest)
    existing = _existing_seqs(dest)
    created = []
    candidates = []
    for jf in [f for f in os.listdir(dest) if f.endswith(".info.json")]:
        base = jf[: -len(".info.json")]
        vfile = next((os.path.join(dest, base + e) for e in VEXT
                      if os.path.exists(os.path.join(dest, base + e))), None)
        if not vfile:
            continue
        try:
            info = json.load(open(os.path.join(dest, jf), encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            print(f"restructure: skip {base}: {e}", file=sys.stderr)
            continue
        candidates.append((base, vfile, info))
    for base, vfile, info in sorted(candidates, key=lambda t: str(t[2].get("id") or t[0])):
        p = plan_episode(info, existing)
        _, aired = date_of(info)
        vid = str(info.get("id") or base)
        idtag = f" [{vid}]"
        prefix = f"{folder} - {p['token']} - "
        stitle = btrunc(sanitize((info.get("title") or vid)),
                        MAX_BASE - len(prefix.encode()) - len(idtag.encode())) or "Untitled"
        newbase = prefix + stitle + idtag
        sdir = os.path.join(dest, "Season 00" if p["season"] == 0 else f"Season {p['season']}")
        os.makedirs(sdir, exist_ok=True)
        dst = os.path.join(sdir, newbase)
        os.rename(vfile, dst + os.path.splitext(vfile)[1])
        for suf in (".jpg", ".info.json"):
            src = os.path.join(dest, base + suf)
            if os.path.exists(src):
                os.rename(src, dst + suf)
        with open(dst + ".nfo", "w", encoding="utf-8") as fh:
            fh.write(build_episode_nfo(info, p["season"], p["episode"], aired))
        old_nfo = os.path.join(dest, base + ".nfo")
        if os.path.exists(old_nfo):
            os.remove(old_nfo)
        created.append({"season": p["season"], "episode": p["episode"], "id": vid, "path": dst})
    return created
