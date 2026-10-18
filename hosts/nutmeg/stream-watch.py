"""Watch a Twitch stream from both ends and report where frame drops come from.

While OBS (on the streaming Mac) reports an active stream, three probes run
side by side and are folded into 10-second windows:

  * OBS itself, over obs-websocket: frames dropped for bandwidth (the network
    leg to Twitch), frames skipped for encoder lag, frames missed for render
    lag, reconnects, congestion and bytes sent.
  * The stream as viewers get it: the source rendition's HLS playlist (found
    via streamlink), every segment fetched and its frame timestamps checked
    for gaps, plus playlist-level gaps, discontinuities and stalls.
  * The path from this house to Twitch's ingest: a TCP handshake to port 1935
    over IPv4 and IPv6 every few seconds. nutmeg shares the Mac's uplink, so a
    degraded route shows up here too; a clean probe during OBS drops points at
    OBS's own connection instead.

Consecutive bad windows form an incident; when it has been clean for a minute
the incident is attributed (Mac / connection / Twitch) and, if it was big
enough to see, sent to Telegram. A reconnect is sent immediately. When the
stream ends, a summary is sent. Every window is also appended as a JSON line
to $STATE_DIRECTORY for later digging.
"""

import asyncio
import base64
import hashlib
import json
import os
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timedelta

import websockets

OBS_URL = os.environ.get("OBS_URL", "ws://192.168.1.179:4455")
OBS_PASSWORD = os.environ.get("OBS_PASSWORD", "")
LOGIN = os.environ["TWITCH_LOGIN"]
STATE_DIR = os.environ.get("STATE_DIRECTORY", ".")
TG_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TG_CHAT = os.environ.get("TELEGRAM_CHAT_ID", "")
DRY_RUN = os.environ.get("DRY_RUN") == "1"

INGEST_HOST = "ingest.global-contribute.live-video.net"
WINDOW = 10  # seconds per aggregation window
CLEAN_TO_CLOSE = 6  # clean windows before an incident is closed and reported
SLOW_HANDSHAKE_MS = 150  # baseline to Twitch's ingest is ~15 ms
MIN_SESSION = 60  # seconds; shorter sessions (a test start) get no summary

# Window keys that hold a peak rather than a running count.
PEAK_KEYS = {"congestion", "reconnecting", "twitch_offline", "tcp4_rtt_max", "tcp6_rtt_max"}

_background = set()


def log(msg):
    print(msg, flush=True)


def clock(ts):
    return datetime.fromtimestamp(ts).strftime("%H:%M")


def span(seconds):
    m = int(seconds // 60)
    return f"{m // 60}h{m % 60:02d}m" if m >= 60 else f"{m}m{int(seconds % 60):02d}s"


def _send_telegram(text):
    data = urllib.parse.urlencode(
        {"chat_id": TG_CHAT, "text": text[:4000], "disable_web_page_preview": "true"}
    ).encode()
    url = f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage"
    for _ in range(16):
        try:
            urllib.request.urlopen(url, data, timeout=30).read()
            return
        except urllib.error.HTTPError as e:
            # A rejection (bad token, bad chat id) won't fix itself.
            log(f"telegram rejected the message: {e}")
            return
        except OSError as e:
            log(f"telegram unreachable ({e}); retrying in 30s")
            time.sleep(30)
    log("telegram unreachable for ~8min; message lost")


def notify(text):
    log("NOTIFY: " + text.replace("\n", " | "))
    if DRY_RUN or not (TG_TOKEN and TG_CHAT):
        return
    # Sent in the background so a slow Telegram never stalls the probes.
    task = asyncio.create_task(asyncio.to_thread(_send_telegram, text))
    _background.add(task)
    task.add_done_callback(_background.discard)


class Obs:
    """Minimal obs-websocket v5 client: requests plus Outputs events."""

    def __init__(self):
        self.ws = None
        self.reader = None
        self.pending = {}
        self.next_id = 0
        # Called with each event's data; set by whoever is listening.
        self.on_event = None

    async def connect(self):
        self.ws = await websockets.connect(
            OBS_URL,
            subprotocols=["obswebsocket.json"],
            open_timeout=5,
            ping_interval=10,
            ping_timeout=10,
        )
        hello = json.loads(await self.ws.recv())["d"]
        # Outputs events (1 << 6): a reconnect can begin and end between polls.
        identify = {"rpcVersion": 1, "eventSubscriptions": 1 << 6}
        auth = hello.get("authentication")
        if auth:
            if not OBS_PASSWORD:
                raise RuntimeError("OBS wants a password but OBS_PASSWORD is not set")
            secret = base64.b64encode(
                hashlib.sha256((OBS_PASSWORD + auth["salt"]).encode()).digest()
            ).decode()
            identify["authentication"] = base64.b64encode(
                hashlib.sha256((secret + auth["challenge"]).encode()).digest()
            ).decode()
        await self.ws.send(json.dumps({"op": 1, "d": identify}))
        reply = json.loads(await self.ws.recv())
        if reply.get("op") != 2:
            raise RuntimeError(f"OBS refused identify: {reply}")
        self.reader = asyncio.create_task(self._read())

    async def _read(self):
        try:
            async for raw in self.ws:
                msg = json.loads(raw)
                if msg.get("op") == 7:
                    fut = self.pending.pop(msg["d"]["requestId"], None)
                    if fut and not fut.done():
                        fut.set_result(msg["d"])
                elif msg.get("op") == 5 and self.on_event is not None:
                    self.on_event(msg["d"])
        except websockets.ConnectionClosed:
            pass
        finally:
            for fut in self.pending.values():
                if not fut.done():
                    fut.set_exception(ConnectionError("OBS connection closed"))
            self.pending.clear()

    async def request(self, request_type):
        if self.reader is None or self.reader.done():
            raise ConnectionError("OBS connection closed")
        self.next_id += 1
        rid = str(self.next_id)
        fut = asyncio.get_running_loop().create_future()
        self.pending[rid] = fut
        await self.ws.send(
            json.dumps({"op": 6, "d": {"requestType": request_type, "requestId": rid, "requestData": {}}})
        )
        reply = await asyncio.wait_for(fut, 10)
        if not reply["requestStatus"]["result"]:
            raise RuntimeError(f"{request_type} failed: {reply['requestStatus']}")
        return reply.get("responseData", {})

    async def close(self):
        if self.ws is not None:
            await self.ws.close()
        if self.reader is not None:
            await asyncio.gather(self.reader, return_exceptions=True)


def parse_playlist(text):
    """Return the segments of a Twitch media playlist, oldest first."""
    segments, seq, pending = [], 0, {}
    for line in text.splitlines():
        if line.startswith("#EXT-X-MEDIA-SEQUENCE:"):
            seq = int(line.split(":", 1)[1])
        elif line.startswith("#EXT-X-PROGRAM-DATE-TIME:"):
            pending["pdt"] = datetime.fromisoformat(line.split(":", 1)[1].replace("Z", "+00:00"))
        elif line.startswith("#EXT-X-DISCONTINUITY"):
            pending["discontinuity"] = True
        elif line.startswith("#EXTINF:"):
            duration, _, title = line[8:].partition(",")
            pending["duration"] = float(duration)
            pending["title"] = title
        elif line and not line.startswith("#"):
            segments.append({"seq": seq, "uri": line, **pending})
            seq += 1
            pending = {}
    return segments


async def run(*argv, stdin=None, timeout=60):
    proc = await asyncio.create_subprocess_exec(
        *argv,
        stdin=asyncio.subprocess.PIPE if stdin is not None else asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(stdin), timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise
    return out.decode(errors="replace")


async def playlist_url():
    """The source rendition's media playlist, or None if Twitch isn't live."""
    out = await run("streamlink", "--stream-url", f"twitch.tv/{LOGIN}", "best")
    url = out.strip().splitlines()[-1] if out.strip() else ""
    return url if url.startswith("http") else None


def fetch(url):
    with urllib.request.urlopen(url, timeout=10) as resp:
        return resp.read()


async def frame_times(segment):
    out = await run(
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "packet=pts_time", "-of", "csv=p=0", "-i", "pipe:0",
        stdin=segment, timeout=20,
    )
    times = []
    for line in out.split():
        value = line.strip().rstrip(",")
        if value and value != "N/A":
            times.append(float(value))
    return sorted(times)


def missing_frames(times, fps):
    frame = 1 / fps
    return sum(max(0, round((b - a) / frame) - 1) for a, b in zip(times, times[1:]) if b - a > 1.5 * frame)


def new_window():
    return defaultdict(float)


def merge(into, window):
    for key, value in window.items():
        into[key] = max(into[key], value) if key in PEAK_KEYS else into[key] + value


def is_bad(w):
    return bool(
        w["net_drop"] or w["reconnecting"] or w["enc_skip"] or w["render_skip"] >= 3
        or w["v_missing"] >= 3 or w["gap_s"] or w["stall_s"] or w["discont"]
        or w["twitch_offline"] or w["tcp4_fail"] or w["tcp6_fail"]
    )


def is_visible(w):
    """Whether an incident was big enough that viewers could have noticed."""
    frames = w["net_drop"] + w["enc_skip"] + w["render_skip"] + w["v_missing"]
    return frames >= 30 or w["reconnecting"] or w["stall_s"] >= 4 or w["gap_s"] >= 1 or w["twitch_offline"]


def attribute(w):
    """Return (verdict, explanation lines) for one incident's merged window."""
    verdicts, lines = [], []
    mac = w["enc_skip"] + w["render_skip"]
    if mac >= 10:
        verdicts.append("Mac")
        lines.append(
            f"Mac couldn't keep up: {int(w['render_skip'])} frames missed rendering, "
            f"{int(w['enc_skip'])} skipped encoding"
        )
    if w["net_drop"] or w["reconnecting"]:
        verdicts.append("connection")
        line = f"OBS dropped {int(w['net_drop'])} frames it couldn't get to Twitch"
        if w["reconnecting"]:
            line += ", and the connection broke and reconnected"
        lines.append(line)
        fails = int(w["tcp4_fail"] + w["tcp6_fail"])
        worst = max(w["tcp4_rtt_max"], w["tcp6_rtt_max"])
        if fails or worst > SLOW_HANDSHAKE_MS:
            lines.append(
                f"nutmeg's probes to Twitch's ingest suffered too ({fails} failed, worst "
                f"{worst:.0f} ms) → the route from the house to Twitch"
            )
        else:
            lines.append(
                f"nutmeg's probes to Twitch's ingest stayed clean (worst {worst:.0f} ms) → "
                "specific to OBS's own connection (its ingest server, or the Mac's network)"
            )
    viewer = w["v_missing"] >= 3 or w["stall_s"] or w["gap_s"] >= 0.25 or w["discont"] or w["twitch_offline"]
    if viewer:
        parts = []
        if w["v_missing"]:
            parts.append(f"{int(w['v_missing'])} frames missing")
        if w["stall_s"]:
            parts.append(f"{w['stall_s']:.0f}s stalled")
        if w["gap_s"]:
            parts.append(f"{w['gap_s']:.1f}s of gaps")
        if w["discont"]:
            parts.append(f"{int(w['discont'])} discontinuities")
        if w["twitch_offline"]:
            parts.append("Twitch showed the channel offline while OBS was streaming")
        lines.append("viewers saw: " + ", ".join(parts))
        if not verdicts:
            verdicts.append("Twitch")
            lines.append("OBS sent every frame cleanly → this happened inside Twitch")
    if not verdicts:
        verdicts.append("unclear")
    return " + ".join(verdicts), lines


class Session:
    def __init__(self, obs):
        self.obs = obs
        self.start = time.time()
        self.w = new_window()
        self.totals = Counter()
        self.prev = {}
        self.fps = 60.0
        self.incident = None
        self.incidents = []
        path = os.path.join(STATE_DIR, datetime.now().strftime("%Y-%m-%d-%H%M.jsonl"))
        self.logfile = open(path, "a")
        log(f"stream session started; windows logged to {path}")
        obs.on_event = self.on_event

    def on_event(self, event):
        if (
            event.get("eventType") == "StreamStateChanged"
            and event["eventData"].get("outputState") == "OBS_WEBSOCKET_OUTPUT_RECONNECTING"
        ):
            self.w["reconnecting"] = 1

    async def poll_obs(self):
        video = await self.obs.request("GetVideoSettings")
        self.fps = video["fpsNumerator"] / video["fpsDenominator"]
        while True:
            status = await self.obs.request("GetStreamStatus")
            stats = await self.obs.request("GetStats")
            if not status["outputActive"]:
                return
            counters = {
                "net_drop": status["outputSkippedFrames"],
                "net_total": status["outputTotalFrames"],
                "bytes": status["outputBytes"],
                "enc_skip": stats["outputSkippedFrames"],
                "render_skip": stats["renderSkippedFrames"],
            }
            for key, value in counters.items():
                old = self.prev.get(key)
                self.prev[key] = value
                if old is not None:
                    # OBS restarts the output's counters when it reconnects.
                    self.w[key] += value - old if value >= old else value
            if status["outputReconnecting"]:
                self.w["reconnecting"] = 1
            self.w["congestion"] = max(self.w["congestion"], status.get("outputCongestion") or 0)
            await asyncio.sleep(2)

    async def watch_viewer(self):
        url, seen, last_new = None, {}, time.time()
        prev_end = prev_last = None
        while True:
            try:
                if url is None:
                    url = await playlist_url()
                    if url is None:
                        if time.time() - self.start > 90:
                            self.w["twitch_offline"] = 1
                        await asyncio.sleep(10)
                        continue
                    first = True
                try:
                    text = (await asyncio.to_thread(fetch, url)).decode()
                except urllib.error.HTTPError:
                    # Playlist tokens expire; fetch a fresh URL.
                    url = None
                    continue
                segments = parse_playlist(text)
                if first:
                    # Start at the live edge rather than replaying the backlog.
                    for s in segments[:-1]:
                        seen[s["uri"]] = True
                    first = False
                for s in segments:
                    if s["uri"] in seen:
                        continue
                    seen[s["uri"]] = True
                    last_new = time.time()
                    duration = s.get("duration", 2.0)
                    if s.get("title") != "live":
                        # Ads or Twitch's slate: not the broadcaster's video.
                        self.w["nonlive_s"] += duration
                        prev_end = prev_last = None
                        continue
                    if s.get("discontinuity") and prev_end is not None:
                        self.w["discont"] += 1
                        prev_last = None
                    pdt = s.get("pdt")
                    if pdt is not None and prev_end is not None:
                        gap = (pdt - prev_end).total_seconds()
                        if gap > 0.25:
                            self.w["gap_s"] += gap
                    prev_end = pdt + timedelta(seconds=duration) if pdt is not None else None
                    data = await asyncio.to_thread(fetch, s["uri"])
                    self.w["v_bytes"] += len(data)
                    self.w["v_seconds"] += duration
                    times = await frame_times(data)
                    if prev_last is not None and times:
                        times = [prev_last] + times
                    self.w["v_missing"] += missing_frames(times, self.fps)
                    self.w["v_frames"] += len(times)
                    prev_last = times[-1] if times else None
                while len(seen) > 200:
                    del seen[next(iter(seen))]
                if time.time() - last_new > 8:
                    self.w["stall_s"] += 2
            except asyncio.CancelledError:
                raise
            except Exception as e:  # the viewer probe must never end the session
                log(f"viewer probe error: {e!r}")
                self.w["viewer_errors"] += 1
            await asyncio.sleep(2)

    async def probe_path(self):
        targets, resolved_at = [], 0.0
        while True:
            if time.time() - resolved_at > 300:
                try:
                    infos = await asyncio.get_running_loop().getaddrinfo(
                        INGEST_HOST, 1935, type=socket.SOCK_STREAM
                    )
                    by_family = {}
                    for family, *_, addr in infos:
                        by_family.setdefault(family, addr[0])
                    targets = [
                        ("tcp4" if fam == socket.AF_INET else "tcp6", addr) for fam, addr in by_family.items()
                    ]
                    resolved_at = time.time()
                except OSError as e:
                    log(f"cannot resolve {INGEST_HOST}: {e}")
            for name, addr in targets:
                t0 = time.monotonic()
                try:
                    _, writer = await asyncio.wait_for(asyncio.open_connection(addr, 1935), 3)
                    rtt = (time.monotonic() - t0) * 1000
                    writer.close()
                    self.w[f"{name}_ok"] += 1
                    self.w[f"{name}_rtt_max"] = max(self.w[f"{name}_rtt_max"], rtt)
                except (OSError, asyncio.TimeoutError):
                    self.w[f"{name}_fail"] += 1
            await asyncio.sleep(5)

    async def tick(self):
        while True:
            await asyncio.sleep(WINDOW)
            window, self.w = self.w, new_window()
            self.close_window(window)

    def close_window(self, w):
        self.logfile.write(json.dumps({"t": round(time.time()), **w}) + "\n")
        self.logfile.flush()
        for key, value in w.items():
            if key not in PEAK_KEYS:
                self.totals[key] += value
        if is_bad(w):
            if self.incident is None:
                self.incident = {"start": time.time() - WINDOW, "end": time.time(), "w": new_window(), "clean": 0, "told": False}
            inc = self.incident
            inc["clean"] = 0
            inc["end"] = time.time()
            merge(inc["w"], w)
            if w["reconnecting"] and not inc["told"]:
                inc["told"] = True
                notify(f"🔴 {LOGIN}: OBS lost its connection to Twitch at {clock(time.time())} and is reconnecting")
        elif self.incident is not None:
            merge(self.incident["w"], w)
            self.incident["clean"] += 1
            if self.incident["clean"] >= CLEAN_TO_CLOSE:
                self.finish_incident()

    def finish_incident(self):
        inc, self.incident = self.incident, None
        verdict, lines = attribute(inc["w"])
        inc["verdict"] = verdict
        inc["visible"] = is_visible(inc["w"])
        self.incidents.append(inc)
        if inc["visible"]:
            when = f"{clock(inc['start'])}–{clock(inc['end'])} ({span(inc['end'] - inc['start'])})"
            notify(f"⚠️ {LOGIN} stream problem {when}: {verdict}\n" + "\n".join("• " + l for l in lines))

    def summary(self, reason):
        if self.incident is not None:
            self.finish_incident()
        t = self.totals
        duration = time.time() - self.start
        lines = [f"📺 {LOGIN} stream {reason} after {span(duration)}"]
        sent = t["net_total"] + t["net_drop"]
        pct = f" ({100 * t['net_drop'] / sent:.1f}%)" if sent else ""
        lines.append(
            f"OBS sent avg {t['bytes'] * 8 / duration / 1000:,.0f} kbps; "
            f"dropped {int(t['net_drop']):,} frames for bandwidth{pct}"
        )
        lines.append(f"Mac: {int(t['render_skip'])} render-lag, {int(t['enc_skip'])} encoder-lag frames")
        if t["v_seconds"]:
            lines.append(
                f"Viewers (source): {t['v_bytes'] * 8 / t['v_seconds'] / 1000:,.0f} kbps; "
                f"{int(t['v_missing']):,} missing frames, {t['stall_s']:.0f}s stalled, {t['gap_s']:.1f}s gaps"
            )
        visible = [i for i in self.incidents if i["visible"]]
        minor = len(self.incidents) - len(visible)
        if visible:
            lines.append(f"Problems ({len(visible)}):")
            for i in visible:
                lines.append(f"• {clock(i['start'])}–{clock(i['end'])} {i['verdict']}")
        else:
            lines.append("No visible problems.")
        if minor:
            lines.append(f"(+{minor} minor blips)")
        notify("\n".join(lines))
        self.logfile.close()


async def run_session(obs):
    session = Session(obs)
    tasks = [
        asyncio.create_task(session.poll_obs()),
        asyncio.create_task(session.watch_viewer()),
        asyncio.create_task(session.probe_path()),
        asyncio.create_task(session.tick()),
    ]
    done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    for task in pending:
        task.cancel()
    await asyncio.gather(*pending, return_exceptions=True)
    session.close_window(session.w)
    failure = next((t.exception() for t in done if t.exception()), None)
    obs.on_event = None
    if time.time() - session.start >= MIN_SESSION:
        session.summary("ended" if failure is None else "lost contact with OBS")
    if failure is not None:
        raise failure


async def main():
    quiet = False
    while True:
        obs = Obs()
        try:
            await obs.connect()
        except Exception as e:
            # The Mac is asleep or OBS is closed most of the time; say so once.
            if not quiet:
                log(f"OBS not reachable ({e!r}); retrying every 30s")
                quiet = True
            await asyncio.sleep(30)
            continue
        quiet = False
        log("connected to OBS")
        try:
            while True:
                status = await obs.request("GetStreamStatus")
                if status["outputActive"]:
                    await run_session(obs)
                else:
                    await asyncio.sleep(10)
        except Exception as e:
            log(f"lost OBS: {e!r}")
        finally:
            await obs.close()
        await asyncio.sleep(10)


if __name__ == "__main__":
    asyncio.run(main())
