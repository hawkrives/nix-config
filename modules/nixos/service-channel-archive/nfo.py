#!/usr/bin/env python3
"""Generate Kodi/Jellyfin .nfo sidecars from yt-dlp .info.json files.

Usage: nfo.py <directory>

For every "<name>.info.json" in <directory> that has no sibling "<name>.nfo",
write "<name>.nfo" (Kodi 'movie' schema). Existing .nfo files are left alone.
"""
import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape

INFO_SUFFIX = ".info.json"


def _fmt_date(upload_date):
    # yt-dlp upload_date is "YYYYMMDD"
    if upload_date and len(upload_date) == 8 and upload_date.isdigit():
        return f"{upload_date[0:4]}-{upload_date[4:6]}-{upload_date[6:8]}"
    return None


def build_nfo(info):
    """Return a Kodi 'movie'-schema .nfo XML string for a yt-dlp info dict."""
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', "<movie>"]

    def add(tag, value):
        if value is None or value == "":
            return
        lines.append(f"  <{tag}>{escape(str(value))}</{tag}>")

    add("title", info.get("title"))
    add("plot", info.get("description"))
    date = _fmt_date(info.get("upload_date"))
    add("premiered", date)
    add("aired", date)
    if date:
        add("year", date[:4])  # Plex populates the year field from <year>, not <premiered>
    uploader = info.get("uploader") or info.get("channel")
    add("studio", uploader)
    add("director", uploader)
    duration = info.get("duration")
    if isinstance(duration, (int, float)) and duration > 0:
        add("runtime", round(duration / 60))
    # Genre: YouTube exposes it in `categories`; Twitch VODs don't, but the
    # game(s) played are the `chapters[].title` segments — unify both.
    genres = []
    cats = info.get("categories")
    if isinstance(cats, list):
        genres.extend(c for c in cats if c)
    chapters = info.get("chapters")
    if isinstance(chapters, list):
        genres.extend(
            ch.get("title") for ch in chapters if isinstance(ch, dict) and ch.get("title")
        )
    for g in dict.fromkeys(genres):  # de-dup, preserve order
        add("genre", g)
    tags = info.get("tags")
    if isinstance(tags, list):
        for t in dict.fromkeys(t for t in tags if t):  # de-dup, preserve order
            add("tag", t)
    vid = info.get("id")
    if vid:
        extractor = (info.get("extractor") or "").lower()
        uid_type = "twitch" if "twitch" in extractor else "youtube"
        lines.append(
            f'  <uniqueid type="{uid_type}" default="true">{escape(str(vid))}</uniqueid>'
        )
    lines.append("</movie>")
    lines.append("")  # trailing newline
    return "\n".join(lines)


def generate_dir(directory, force=False):
    """Write a .nfo for each .info.json lacking one. Return count written.

    With force=True, overwrite existing .nfo files (e.g. to pick up schema
    changes like the added <year> tag).
    """
    d = Path(directory)
    written = 0
    for info_path in sorted(d.glob("*" + INFO_SUFFIX)):
        base = info_path.name[: -len(INFO_SUFFIX)]
        nfo_path = info_path.with_name(base + ".nfo")
        if nfo_path.exists() and not force:
            continue
        try:
            info = json.loads(info_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            print(f"skip {info_path}: {e}", file=sys.stderr)
            continue
        nfo_path.write_text(build_nfo(info), encoding="utf-8")
        written += 1
    return written


def main(argv):
    force = "--force" in argv
    argv = [a for a in argv if a != "--force"]
    if len(argv) != 2:
        print("usage: nfo.py <directory> [--force]", file=sys.stderr)
        return 2
    n = generate_dir(argv[1], force=force)
    print(f"generated {n} .nfo file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
