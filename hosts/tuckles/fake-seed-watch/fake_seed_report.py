"""Find networks whose peers keep joining qBittorrent swarms as 100% "seeds"
without ever sending data, from the sightings fake-seed-watch logs.

usage: fake-seed-report [--hours N] [--min-connections N] [--new-only FILE]
                        [SIGHTINGS] [IPFILTER]

SIGHTINGS is fake-seed-watch's TSV log (ts, torrent, ip, port, client, country,
downloaded bytes); IPFILTER is qBittorrent's P2P-format filter, whose ranges are
already handled and are left out. With --new-only, networks listed in FILE are
skipped and the reported ones are appended to it.
"""

import argparse
import dataclasses
import ipaddress
import sys
import time
from collections import defaultdict


@dataclasses.dataclass(frozen=True)
class Sighting:
    ts: int
    torrent: str
    ip: str
    port: int
    client: str
    country: str
    downloaded: int


@dataclasses.dataclass
class Suspect:
    network: str
    connections: int
    ips: list
    ports: list
    clients: list
    countries: list
    torrents: int
    first: int
    last: int


def network_of(ip):
    """The network a peer is grouped by: its /24 (IPv4) or /48 (IPv6)."""
    prefix = 24 if ipaddress.ip_address(ip).version == 4 else 48
    return str(ipaddress.ip_network(f"{ip}/{prefix}", strict=False))


def parse_ipfilter(text):
    """(first, last) address pairs from a P2P-format filter (name:first-last)."""
    ranges = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        first, _, last = line.rpartition(":")[2].partition("-")
        ranges.append((first.strip(), last.strip()))
    return ranges


def _is_banned(ip, banned):
    addr = ipaddress.ip_address(ip)
    for first, last in banned:
        lo, hi = ipaddress.ip_address(first), ipaddress.ip_address(last)
        if lo.version == addr.version and lo <= addr <= hi:
            return True
    return False


def _connections(rows, gap):
    """Count connections: the poller logs a connected peer on every tick, so
    sightings of one ip:port on one torrent belong to the same connection until
    there is a break longer than `gap` seconds."""
    ticks = defaultdict(list)
    for r in rows:
        ticks[(r.torrent, r.ip, r.port)].append(r.ts)
    count = 0
    for times in ticks.values():
        times.sort()
        count += 1 + sum(1 for a, b in zip(times, times[1:]) if b - a > gap)
    return count


def suspects(rows, banned, min_connections=3, gap=10):
    """Networks that connected as a seed at least `min_connections` times and
    never sent a byte, skipping any already covered by `banned`. Most
    connections first."""
    by_network = defaultdict(list)
    for r in rows:
        by_network[network_of(r.ip)].append(r)
    found = []
    for network, rs in by_network.items():
        if any(r.downloaded > 0 for r in rs):
            continue
        if all(_is_banned(r.ip, banned) for r in rs):
            continue
        connections = _connections(rs, gap)
        if connections < min_connections:
            continue
        found.append(
            Suspect(
                network=network,
                connections=connections,
                ips=sorted({r.ip for r in rs}, key=ipaddress.ip_address),
                ports=sorted({r.port for r in rs}),
                clients=sorted({r.client for r in rs if r.client}),
                countries=sorted({r.country for r in rs if r.country}),
                torrents=len({r.torrent for r in rs}),
                first=min(r.ts for r in rs),
                last=max(r.ts for r in rs),
            )
        )
    found.sort(key=lambda s: (-s.connections, s.network))
    return found


def read_sightings(path, since):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 7:
                continue
            ts, torrent, ip, port, client, country, downloaded = fields
            if int(ts) < since:
                continue
            rows.append(Sighting(int(ts), torrent, ip, int(port), client, country, int(downloaded or 0)))
    return rows


def describe(s):
    when = time.strftime("%Y-%m-%d %H:%M", time.localtime(s.first))
    return (
        f"{s.network}  {s.connections} connections, 0 bytes, {s.torrents} torrent(s), since {when}\n"
        f"  ips: {', '.join(s.ips)}\n"
        f"  ports: {', '.join(map(str, s.ports))}\n"
        f"  clients: {', '.join(s.clients) or '(none reported)'}  country: {', '.join(s.countries) or '?'}"
    )


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("sightings", nargs="?", default="/var/lib/fake-seed-watch/sightings.tsv")
    p.add_argument("ipfilter", nargs="?", default="/etc/qbittorrent/ipfilter.p2p")
    p.add_argument("--hours", type=float, default=24)
    p.add_argument("--min-connections", type=int, default=3)
    p.add_argument("--new-only", metavar="FILE")
    a = p.parse_args(argv)

    with open(a.ipfilter, encoding="utf-8") as f:
        banned = parse_ipfilter(f.read())
    rows = read_sightings(a.sightings, since=time.time() - a.hours * 3600)
    found = suspects(rows, banned, min_connections=a.min_connections)

    if a.new_only:
        try:
            with open(a.new_only, encoding="utf-8") as f:
                seen = {line.strip() for line in f}
        except FileNotFoundError:
            seen = set()
        found = [s for s in found if s.network not in seen]
        with open(a.new_only, "a", encoding="utf-8") as f:
            f.writelines(f"{s.network}\n" for s in found)

    print("\n\n".join(describe(s) for s in found))
    return 0


if __name__ == "__main__":
    sys.exit(main())
