import unittest

from fake_seed_report import Sighting, network_of, parse_ipfilter, suspects


def sighting(ts, ip, port=31835, torrent="t1", client="Transmission 2.2.1", downloaded=0, country="ru"):
    return Sighting(ts=ts, torrent=torrent, ip=ip, port=port, client=client, country=country, downloaded=downloaded)


class NetworkOf(unittest.TestCase):
    def test_ipv4_is_grouped_by_slash_24(self):
        self.assertEqual(network_of("31.200.249.231"), "31.200.249.0/24")

    def test_ipv6_is_grouped_by_slash_48(self):
        self.assertEqual(network_of("240e:978:311:0:3498:51c7:ffd:175b"), "240e:978:311::/48")


class ParseIpfilter(unittest.TestCase):
    def test_reads_p2p_ranges_and_skips_comments(self):
        text = "# comment\nTeleport_Rus fake seeds (AS216158):31.200.249.0-31.200.249.255\n\nStart2:185.16.212.0-185.16.215.255\n"
        self.assertEqual(parse_ipfilter(text), [("31.200.249.0", "31.200.249.255"), ("185.16.212.0", "185.16.215.255")])


class Suspects(unittest.TestCase):
    def test_flags_a_network_that_keeps_reconnecting_without_sending_data(self):
        rows = [sighting(t, "31.200.249.231", port=p) for t, p in ((0, 31835), (20, 31836), (40, 31837))]
        found = suspects(rows, banned=[], min_connections=3)
        self.assertEqual([s.network for s in found], ["31.200.249.0/24"])
        self.assertEqual(found[0].connections, 3)
        self.assertEqual(found[0].ports, [31835, 31836, 31837])
        self.assertEqual(found[0].clients, ["Transmission 2.2.1"])

    def test_one_continuous_connection_counts_once(self):
        # the poller sees a connected peer on every tick; consecutive ticks of the
        # same ip:port on the same torrent are one connection, not many
        rows = [sighting(t, "31.200.249.231") for t in range(0, 20, 2)]
        self.assertEqual(suspects(rows, banned=[], min_connections=3), [])

    def test_a_gap_starts_a_new_connection(self):
        rows = [sighting(t, "31.200.249.231") for t in (0, 2, 60, 62, 120)]
        found = suspects(rows, banned=[], min_connections=3, gap=10)
        self.assertEqual(found[0].connections, 3)

    def test_a_seed_that_sent_data_is_not_a_suspect(self):
        rows = [sighting(t, "1.2.3.4", port=p, downloaded=(5_000_000 if t == 40 else 0)) for t, p in ((0, 1), (20, 2), (40, 3))]
        self.assertEqual(suspects(rows, banned=[], min_connections=3), [])

    def test_networks_already_in_the_ip_filter_are_skipped(self):
        rows = [sighting(t, "31.200.249.231", port=p) for t, p in ((0, 1), (20, 2), (40, 3))]
        self.assertEqual(suspects(rows, banned=[("31.200.249.0", "31.200.249.255")], min_connections=3), [])

    def test_too_few_connections_is_not_enough(self):
        rows = [sighting(t, "9.9.9.9", port=p) for t, p in ((0, 1), (20, 2))]
        self.assertEqual(suspects(rows, banned=[], min_connections=3), [])

    def test_counts_distinct_ips_and_torrents(self):
        rows = [
            sighting(0, "31.200.249.231", torrent="a"),
            sighting(20, "31.200.249.237", torrent="b"),
            sighting(40, "31.200.249.237", torrent="a", port=31836),
        ]
        found = suspects(rows, banned=[], min_connections=3)
        self.assertEqual(found[0].ips, ["31.200.249.231", "31.200.249.237"])
        self.assertEqual(found[0].torrents, 2)

    def test_most_connections_first(self):
        rows = [sighting(t, "1.1.1.1", port=t) for t in (0, 20, 40)] + [sighting(t, "2.2.2.2", port=t) for t in (0, 20, 40, 60)]
        self.assertEqual([s.network for s in suspects(rows, banned=[], min_connections=3)], ["2.2.2.0/24", "1.1.1.0/24"])


if __name__ == "__main__":
    unittest.main()
