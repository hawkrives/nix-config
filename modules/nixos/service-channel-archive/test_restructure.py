import restructure as r

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
