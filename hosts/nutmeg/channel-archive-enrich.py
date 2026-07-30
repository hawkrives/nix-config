#!/usr/bin/env python3
"""Enrich a directory of lean "<video-id>.<ext>" files with metadata rescued
from TubeArchivist's Elasticsearch export.

For every video file (*.mp4/*.mkv/*.webm) in VIDEO_DIR whose id is found in the
metadata JSONL, write a yt-dlp-shaped "<id>.info.json" and copy the cached
thumbnail "<THUMBS_DIR>/<id>.jpg" -> "<VIDEO_DIR>/<id>-thumb.jpg". Then, if a
sibling nfo.py is present, run it to generate "<id>.nfo" from each info.json
(same .nfo format the channelArchive module produces for fresh downloads).

Run ON THE NAS as root (the youtube/<UC> dirs are root-owned, and the metadata
+ thumbnails live there):
  python3 channel-archive-enrich.py VIDEO_DIR METADATA.jsonl THUMBS_DIR

Idempotent: skips a video whose .info.json already exists (pass --force to
overwrite). Video id = filename up to the first '.' (YouTube ids never contain
a dot).
"""
import json
import os
import shutil
import subprocess
import sys

VIDEO_EXTS = (".mp4", ".mkv", ".webm")


def load_meta(path):
    """id -> ES doc, from a JSONL file of ta_video _source objects."""
    meta = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                doc = json.loads(line)
            except json.JSONDecodeError:
                continue
            yid = doc.get("youtube_id")
            if yid:
                meta[yid] = doc
    return meta


def info_from_doc(doc):
    """Map a TubeArchivist ta_video doc to a yt-dlp-shaped info dict."""
    yid = doc.get("youtube_id")
    ch = doc.get("channel") or {}
    published = str(doc.get("published") or "")  # usually "YYYY-MM-DD"
    if len(published) == 10 and published[4] == "-":
        upload_date = published.replace("-", "")  # -> YYYYMMDD
    elif published.isdigit() and len(published) == 8:
        upload_date = published
    else:
        upload_date = None
    info = {
        "id": yid,
        "title": doc.get("title"),
        "description": doc.get("description"),
        "upload_date": upload_date,  # YYYYMMDD, as yt-dlp / nfo.py expect
        "uploader": ch.get("channel_name"),
        "channel": ch.get("channel_name"),
        "channel_id": ch.get("channel_id"),
        "categories": doc.get("category"),
        "tags": doc.get("tags"),
        "webpage_url": f"https://www.youtube.com/watch?v={yid}",
        "extractor": "youtube",
        "_enriched_from": "tubearchivist-es",
    }
    if ch.get("channel_id"):
        info["channel_url"] = f"https://www.youtube.com/channel/{ch['channel_id']}"
    return {k: v for k, v in info.items() if v is not None}


def main(argv):
    force = "--force" in argv
    argv = [a for a in argv if a != "--force"]
    if len(argv) != 4:
        print("usage: channel-archive-enrich.py VIDEO_DIR METADATA.jsonl THUMBS_DIR [--force]",
              file=sys.stderr)
        return 2
    video_dir, meta_path, thumbs_dir = argv[1], argv[2], argv[3]

    meta = load_meta(meta_path)
    print(f"loaded {len(meta)} metadata docs")

    ids = set()
    for name in os.listdir(video_dir):
        base, ext = os.path.splitext(name)
        if ext.lower() in VIDEO_EXTS:
            ids.add(name.split(".", 1)[0])

    wrote_info = wrote_thumb = missing_meta = missing_thumb = skipped = 0
    for yid in sorted(ids):
        doc = meta.get(yid)
        if not doc:
            missing_meta += 1
            continue
        info_path = os.path.join(video_dir, f"{yid}.info.json")
        if os.path.exists(info_path) and not force:
            skipped += 1
        else:
            with open(info_path, "w", encoding="utf-8") as fh:
                json.dump(info_from_doc(doc), fh, ensure_ascii=False, indent=1)
            wrote_info += 1
        thumb_src = os.path.join(thumbs_dir, f"{yid}.jpg")
        thumb_dst = os.path.join(video_dir, f"{yid}-thumb.jpg")
        if os.path.exists(thumb_src):
            if not os.path.exists(thumb_dst) or force:
                shutil.copyfile(thumb_src, thumb_dst)
                wrote_thumb += 1
        else:
            missing_thumb += 1

    print(f"videos={len(ids)} info.json+={wrote_info} thumb+={wrote_thumb} "
          f"skipped={skipped} no-metadata={missing_meta} no-thumb={missing_thumb}")

    nfo = os.path.join(os.path.dirname(os.path.abspath(__file__)), "nfo.py")
    if os.path.exists(nfo):
        print("generating .nfo via nfo.py ...")
        subprocess.run([sys.executable, nfo, video_dir], check=False)
    else:
        print("(nfo.py not alongside — skipping .nfo generation)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
