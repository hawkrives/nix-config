import os, json, tempfile
import restructure as r

def _mk(d, base, info):
    open(os.path.join(d, base + ".mp4"), "w").write("v")
    open(os.path.join(d, base + ".jpg"), "w").write("t")
    json.dump(info, open(os.path.join(d, base + ".info.json"), "w"))

def test_date_from_upload_date():
    assert r.date_of({"upload_date": "20250604"}) == ("20250604", "2025-06-04")

def test_date_from_timestamp_epoch():
    # 2026-07-25T... UTC
    ymd, aired = r.date_of({"timestamp": 1785011058})
    assert ymd is not None and aired.startswith("2026-")

def test_date_missing():
    assert r.date_of({}) == (None, None)

def test_is_clip():
    assert r.is_clip({"extractor": "twitch:clips"}) is True
    assert r.is_clip({"extractor": "twitch:vod"}) is False
    assert r.is_clip({"extractor": "youtube"}) is False

def test_plan_regular_episode_number():
    p = r.plan_episode({"extractor": "youtube", "upload_date": "20250604", "id": "a"}, {})
    assert p == {"season": 2025, "episode": 60401, "token": "S2025E060401"}

def test_plan_clip_episode_number():
    p = r.plan_episode({"extractor": "twitch:clips", "upload_date": "20260527", "id": "z"}, {})
    assert p == {"season": 0, "episode": 2026052701, "token": "S00E2026052701"}

def test_seq_appends_above_existing():
    # one regular ep already exists on 2025-06-04 (seq 1)
    existing = {(2025, "20250604"): 1}
    p = r.plan_episode({"extractor": "youtube", "upload_date": "20250604", "id": "b"}, existing)
    assert p["episode"] == 60402 and p["token"] == "S2025E060402"

def test_btrunc_multibyte_safe():
    s = "あ" * 100  # 300 bytes
    out = r.btrunc(s, 235)
    assert len(out.encode("utf-8")) <= 235 and out == out  # valid utf-8, no partial char

def test_nfo_has_season_episode_aired_uniqueid():
    xml = r.build_episode_nfo(
        {"title": "T", "id": "vid1", "extractor": "youtube", "description": "d",
         "categories": ["Gaming"]}, 2025, 60401, "2025-06-04")
    assert "<season>2025</season>" in xml and "<episode>60401</episode>" in xml
    assert "<aired>2025-06-04</aired>" in xml
    assert '<uniqueid type="youtube" default="true">vid1</uniqueid>' in xml
    assert "<genre>Gaming</genre>" in xml

def test_restructure_files_regular_and_clip():
    with tempfile.TemporaryDirectory() as d:
        os.rename(d, d)  # keep name; folder basename used as prefix
        _mk(d, "My Stream [aaa]", {"id": "aaa", "title": "My Stream",
             "extractor": "twitch:vod", "upload_date": "20250604"})
        _mk(d, "Cool Clip [bbb]", {"id": "bbb", "title": "Cool Clip",
             "extractor": "twitch:clips", "upload_date": "20260527"})
        folder = os.path.basename(d)
        created = r.restructure_dir(d)
        assert len(created) == 2
        # VOD -> Season 2025, clip -> Season 00
        assert os.path.isfile(os.path.join(d, "Season 2025",
            f"{folder} - S2025E060401 - My Stream [aaa].mp4"))
        assert os.path.isfile(os.path.join(d, "Season 00",
            f"{folder} - S00E2026052701 - Cool Clip [bbb].mp4"))
        # sidecars moved, nfo written, root cleaned
        assert not [f for f in os.listdir(d) if f.endswith(".info.json")]

def test_restructure_seq_against_existing_season_dir():
    with tempfile.TemporaryDirectory() as d:
        folder = os.path.basename(d)
        os.makedirs(os.path.join(d, "Season 2025"))
        # pre-existing ep on 2025-06-04 seq 01
        open(os.path.join(d, "Season 2025",
            f"{folder} - S2025E060401 - Old [old].mp4"), "w").write("v")
        _mk(d, "New [new]", {"id": "new", "title": "New",
             "extractor": "youtube", "upload_date": "20250604"})
        created = r.restructure_dir(d)
        assert created[0]["episode"] == 60402  # appended, not collided

def test_restructure_idempotent_second_run_noop():
    with tempfile.TemporaryDirectory() as d:
        _mk(d, "X [x]", {"id": "x", "title": "X", "extractor": "youtube",
             "upload_date": "20250101"})
        assert len(r.restructure_dir(d)) == 1
        assert r.restructure_dir(d) == []  # nothing flat left

def test_restructure_seq_by_video_id_not_title():
    """seq ordered by video id, not filename/title.
    Two videos same date: title "AAA" id "zzz", title "ZZZ" id "aaa".
    id "aaa" sorts first -> seq 01, id "zzz" -> seq 02."""
    with tempfile.TemporaryDirectory() as d:
        folder = os.path.basename(d)
        _mk(d, "AAA [zzz]", {"id": "zzz", "title": "AAA",
             "extractor": "youtube", "upload_date": "20250604"})
        _mk(d, "ZZZ [aaa]", {"id": "aaa", "title": "ZZZ",
             "extractor": "youtube", "upload_date": "20250604"})
        created = r.restructure_dir(d)
        assert len(created) == 2
        # id "aaa" processes first (sorts before "zzz") -> seq 01
        aaa_ep = next(c for c in created if c["id"] == "aaa")
        zzz_ep = next(c for c in created if c["id"] == "zzz")
        assert aaa_ep["episode"] == 60401
        assert zzz_ep["episode"] == 60402
        # both in Season 2025
        assert os.path.isfile(os.path.join(d, "Season 2025",
            f"{folder} - S2025E060401 - ZZZ [aaa].mp4"))
        assert os.path.isfile(os.path.join(d, "Season 2025",
            f"{folder} - S2025E060402 - AAA [zzz].mp4"))
