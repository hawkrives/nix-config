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
