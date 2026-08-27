#!/usr/bin/env python3
"""Report on the yt-dlp channel archivers.

For every channel-archive-<name> unit: when it last ran, what that run did
(new / already-had / left over), and a few facts about what is on disk.

Everything is read locally -- systemd state, the journal, archive.txt and the
destination directory. There are deliberately NO network calls. Answering "how
many videos does the channel have right now" would mean a yt-dlp playlist fetch
per channel, and this setup already fights YouTube 429/403 bot-checks (the unit
wrapper maps that case to exit 75). A status command must never be the thing
that gets the archiver throttled, so the run-derived numbers below are "as of
that channel's last check", not live.
"""

import os
import re
import subprocess
import sys
import time

UNIT_PREFIX = "channel-archive-"
NOTICES = "/var/lib/channel-archive-alerts/notices"
VIDEO_EXTS = {".mp4", ".mkv", ".webm", ".m4a", ".mov", ".ts", ".flv", ".mp3", ".opus"}

# yt-dlp progress lines are carriage-return separated, so the journal has to be
# re-split on \r before any of this matches.
RE_ITEM = re.compile(r"Downloading item (\d+) of (\d+)")
RE_FETCHED = re.compile(r"\[info\] ([\w.\-]+): Downloading \d+ format")
RE_PLAYLIST = re.compile(r"Downloading playlist: (.+?)\s*$")
RE_ERROR = re.compile(r"^ERROR:\s*(.+)$")
RE_ARCHIVE_ARG = re.compile(r"""--download-archive\s+(?:'([^']+)'|"([^"]+)"|(\S+))""")
RE_URL = re.compile(r"'(https?://[^']+)'")
RE_NOTICE = re.compile(r"^(.*?): (\S+) failed \(exit (\d+)\)")

RECORDED = "has already been recorded in the archive"
FINISHED = "Finished downloading playlist"
BLOCKED = "BLOCKED/RATE-LIMITED"


def sh(cmd):
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=60
        ).stdout
    except Exception:
        return ""


def show(unit, props):
    """systemctl show -> dict, with timestamps as unix epochs."""
    out = sh(
        ["systemctl", "show", unit, "--timestamp=unix"]
        + [f"--property={p}" for p in props]
    )
    d = {}
    for line in out.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            d[k] = v
    return d


def epoch(val):
    """systemd renders unix timestamps as '@1787756959'; 0/absent means never."""
    if not val or not val.startswith("@"):
        return 0
    try:
        n = int(val[1:])
    except ValueError:
        return 0
    return n


def discover():
    out = sh(["systemctl", "list-unit-files", f"{UNIT_PREFIX}*.service", "--no-legend", "--plain"])
    names = []
    for line in out.splitlines():
        unit = line.split()[0] if line.split() else ""
        if unit.startswith(UNIT_PREFIX) and unit.endswith(".service"):
            names.append(unit[len(UNIT_PREFIX) : -len(".service")])
    return sorted(set(names))


def unit_facts(name):
    """destination + url, parsed out of the generated ExecStart script."""
    svc = f"{UNIT_PREFIX}{name}.service"
    execstart = show(svc, ["ExecStart"]).get("ExecStart", "")
    m = re.search(r"path=(\S+?)[ ;]", execstart)
    dest, url, incremental = None, None, False
    if m:
        try:
            with open(m.group(1)) as fh:
                body = fh.read()
            a = RE_ARCHIVE_ARG.search(body)
            if a:
                # group 1/2 = quoted (destinations may contain spaces), 3 = bare
                dest = os.path.dirname(a.group(1) or a.group(2) or a.group(3))
            u = RE_URL.search(body)
            if u:
                url = u.group(1)
            # the wrapper also mentions --break-on-existing in a comment and an
            # echo, so only the actual yt-dlp command line is evidence
            for ln in body.splitlines():
                if "bin/yt-dlp" in ln and "--download-archive" in ln:
                    incremental = "--break-on-existing" in ln
                    break
        except OSError:
            pass
    return dest, url, incremental


def last_run(name, start, end):
    """Parse the journal window for one run. Returns a dict of counts."""
    r = {
        "offered": None,
        "fetched": 0,
        "had": 0,
        "playlist": None,
        "finished": False,
        "blocked": False,
        "errors": [],
        "have_log": False,
        # why the run stopped early, if it did (see the wrapper: yt-dlp exit 101)
        "early": None,
    }
    if not start:
        return r
    args = ["journalctl", "-u", f"{UNIT_PREFIX}{name}", "--no-pager", "-o", "cat",
            "-S", f"@{start}"]
    if end:
        args += ["-U", f"@{end + 2}"]
    out = sh(args)
    if not out.strip():
        return r
    r["have_log"] = True
    fetched = set()
    for line in out.replace("\r", "\n").splitlines():
        m = RE_ITEM.search(line)
        if m:
            r["offered"] = max(r["offered"] or 0, int(m.group(2)))
        m = RE_FETCHED.search(line)
        if m:
            fetched.add(m.group(1))
        if RECORDED in line:
            r["had"] += 1
        if r["playlist"] is None:
            m = RE_PLAYLIST.search(line)
            if m:
                r["playlist"] = m.group(1)
        if FINISHED in line:
            r["finished"] = True
        if BLOCKED in line:
            r["blocked"] = True
        if "stopped at the first already-archived video" in line:
            r["early"] = "caught-up"
        if "hit the --max-downloads cap" in line:
            r["early"] = "capped"
        m = RE_ERROR.match(line)
        if m:
            r["errors"].append(m.group(1)[:120])
    r["fetched"] = len(fetched)
    return r


def archive_stats(dest):
    path = os.path.join(dest or "", "archive.txt")
    total, kinds = 0, {}
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                total += 1
                kinds[line.split()[0]] = kinds.get(line.split()[0], 0) + 1
    except OSError:
        return None, {}
    return total, kinds


def disk_stats(dest):
    size, count, newest = 0, 0, 0
    if not dest:
        return None
    try:
        for root, _dirs, files in os.walk(dest):
            for f in files:
                if os.path.splitext(f)[1].lower() not in VIDEO_EXTS:
                    continue
                try:
                    st = os.stat(os.path.join(root, f))
                except OSError:
                    continue
                size += st.st_size
                count += 1
                newest = max(newest, int(st.st_mtime))
    except OSError:
        return None
    return {"size": size, "count": count, "newest": newest}


def notices():
    per = {}
    try:
        with open(NOTICES) as fh:
            for line in fh:
                m = RE_NOTICE.match(line.strip())
                if m:
                    per.setdefault(m.group(2), []).append((m.group(1), int(m.group(3))))
    except OSError:
        pass
    return per


def ago(ts, now):
    if not ts:
        return "never"
    d = now - ts
    if d < 0:
        d = 0
    for unit, s in (("d", 86400), ("h", 3600), ("m", 60)):
        if d >= s:
            return f"{d // s}{unit} ago"
    return "just now"


def until(ts, now):
    if not ts:
        return "-"
    d = ts - now
    if d <= 0:
        return "due"
    for unit, s in (("d", 86400), ("h", 3600), ("m", 60)):
        if d >= s:
            return f"in {d // s}{unit}"
    return "<1m"


def dur(a, b):
    if not a or not b or b < a:
        return "-"
    d = b - a
    if d >= 3600:
        return f"{d // 3600}h{(d % 3600) // 60:02d}m"
    if d >= 60:
        return f"{d // 60}m{d % 60:02d}s"
    return f"{d}s"


def human(n):
    if n is None:
        return "?"
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024 or unit == "T":
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024
    return "?"


def main():
    now = int(time.time())
    names = discover()
    if not names:
        print("no channel-archive units found", file=sys.stderr)
        return 1

    note = notices()
    rows, attention = [], []
    dest_owner = {}

    for name in names:
        svc = f"{UNIT_PREFIX}{name}.service"
        s = show(svc, ["Result", "ExecMainStatus", "ExecMainStartTimestamp",
                       "ExecMainExitTimestamp", "ActiveState"])
        t = show(f"{UNIT_PREFIX}{name}.timer", ["NextElapseUSecRealtime"])
        start = epoch(s.get("ExecMainStartTimestamp"))
        exit_ts = epoch(s.get("ExecMainExitTimestamp"))
        nxt = epoch(t.get("NextElapseUSecRealtime"))
        dest, url, incremental = unit_facts(name)
        run = last_run(name, start, exit_ts)

        # Several channels deliberately share one destination (VODs + clips use
        # a single archive.txt to dedup). Attribute the folder-level numbers to
        # the first channel using it so they are not counted twice.
        shared = bool(dest) and dest in dest_owner
        if dest and not shared:
            dest_owner[dest] = name

        total, kinds = archive_stats(dest) if not shared else (None, {})
        disk = disk_stats(dest) if not shared else None

        code = s.get("ExecMainStatus", "")
        if not start:
            status = "never run"
        elif run["blocked"] or code == "75":
            status = "RATE-LIMITED"
        elif s.get("Result") == "success" and code == "0":
            # An incremental channel stopping at the first archived video, or a
            # run hitting the --max-downloads cap, is the HEALTHY case -- both
            # exit 101 which the wrapper maps to 0. Report them as such rather
            # than as the "finished early, why?" ok* below.
            if run["early"] == "caught-up":
                status = "up-to-date"
            elif run["early"] == "capped":
                status = "capped"
            else:
                status = "ok" if run["finished"] or not run["have_log"] else "ok*"
        else:
            status = f"FAILED({code})"

        left = ""
        if run["offered"] is not None:
            rem = run["offered"] - run["had"] - run["fetched"]
            left = str(max(rem, 0))

        rows.append({
            "name": name, "status": status, "last": ago(start, now),
            "took": dur(start, exit_ts), "new": str(run["fetched"]) if run["have_log"] else "-",
            "had": str(run["had"]) if run["have_log"] else "-",
            "left": left or "-",
            "total": "^shared" if shared else (str(total) if total is not None else "?"),
            "size": "^shared" if shared else (human(disk["size"]) if disk else "?"),
            "vids": "" if shared else (str(disk["count"]) if disk else "?"),
            "inc": "yes" if incremental else "no", "inc_bool": incremental,
            "next": until(nxt, now), "start": start,
            "kinds": kinds, "url": url, "dest": dest, "run": run,
            "fails": note.get(name, []),
        })

        if status not in ("ok", "up-to-date", "capped"):
            attention.append((name, status, run))

    rows.sort(key=lambda r: (r["start"] or 0))

    cols = [("channel", "name", "<"), ("last check", "last", ">"), ("took", "took", ">"),
            ("status", "status", "<"), ("new", "new", ">"), ("had", "had", ">"),
            ("left", "left", ">"), ("archived", "total", ">"), ("videos", "vids", ">"),
            ("size", "size", ">"),
            ("inc", "inc", ">"), ("next", "next", ">")]
    w = {k: max(len(h), max((len(str(r[k])) for r in rows), default=0)) for h, k, _ in cols}
    print("  ".join(f"{h:{a}{w[k]}}" for h, k, a in cols))
    print("  ".join("-" * w[k] for _h, k, _a in cols))
    for r in rows:
        print("  ".join(f"{str(r[k]):{a}{w[k]}}" for _h, k, a in cols))

    print()
    print(f"{len(rows)} channels; run-derived columns are as of each channel's last check (no live queries).")
    shared_dests = [d for d, o in dest_owner.items()
                    if sum(1 for r in rows if r["dest"] == d) > 1]
    if shared_dests:
        print(f"^shared = destination counted once; {len(shared_dests)} folder(s) serve multiple channels.")

    ready = [
        r for r in rows
        if not r["inc_bool"] and r["status"] == "ok" and r["run"]["finished"]
    ]
    if ready:
        print()
        print("ready for incremental (finished the whole listing; still re-walking it every run):")
        for r in ready:
            print(f'  {r["name"]}')
            print(f'      services.channelArchive.channels."{r["name"]}".incremental = true;')


    if attention:
        print()
        print("needs attention:")
        for name, status, run in attention:
            detail = ""
            if run["errors"]:
                detail = f" — {run['errors'][0]}"
            elif status == "never run":
                detail = " — timer armed but no run recorded yet"
            print(f"  {name}: {status}{detail}")
            for when, code in note.get(name, [])[-2:]:
                print(f"      prior failure: {when} (exit {code})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
