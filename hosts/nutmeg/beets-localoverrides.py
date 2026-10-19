"""Apply hand-written overrides from beets-overrides.yaml files beside the music.

A beets-overrides.yaml applies to every track in its directory and below. Files
are read from the track's directory up to the library root; where two files set
the same thing, the one nearer the track wins. Sections:

    artists:    # rename an artist, keyed by MusicBrainz artist ID
      92bb085a-2924-4479-b627-181a1835d2f5: 植松伸夫
    fields:     # set fields outright on every track below this directory
      genres: Soundtrack        # list fields take a string or a list
    releases:   # fields for one album, keyed by MusicBrainz release ID
      <mb_albumid>: {album: "..."}
    tracks:     # fields for one track, keyed by recording or release-track ID
      <mb_trackid>: {title: "..."}

Precedence on a single track: artists < fields < releases < tracks.

An artist rename applies only where that artist is credited alone (one
artist ID, at most one name, and a display name that is empty or contains
that artist's name): the artist/albumartist display name, the plural list,
and both credit fields are replaced. A joint credit ("Nobuo Uematsu & Masayoshi Soken") is left as
MusicBrainz has it. The one exception is an album artist collapsed to its
primary artist by primaryalbumartist: that value names one artist, so it is
renamed, while the joint list and credit fields are not.

Overrides are applied whenever beets writes a file (the `write` event), so
mbsync can never revert them. `beet applyoverrides [QUERY]` applies them to
items beets would not otherwise rewrite, e.g. after a sidecar is added or
edited. Deleting a sidecar does not undo its changes; `beet mbsync` the
affected albums to restore MusicBrainz's values.
"""

import os

import yaml

from beets import config
from beets.dbcore import types
from beets.library import Item
from beets.plugins import BeetsPlugin
from beets.ui import Subcommand

FILENAME = "beets-overrides.yaml"
SECTIONS = ("artists", "fields", "releases", "tracks")


class LocalOverridesPlugin(BeetsPlugin):
    def __init__(self):
        super().__init__()
        # directory -> (mtime_ns, parsed sidecar or None)
        self._cache = {}
        self.register_listener("write", self.on_write)

    def commands(self):
        cmd = Subcommand(
            "applyoverrides",
            help=f"apply {FILENAME} sidecars to matching items",
        )
        cmd.func = self.apply_command
        return [cmd]

    # ── loading ──

    def _load(self, directory):
        path = os.path.join(directory, FILENAME)
        try:
            mtime = os.stat(path).st_mtime_ns
        except FileNotFoundError:
            return None
        except OSError as exc:
            self._log.warning("cannot stat {}: {}", path, exc)
            return None

        cached = self._cache.get(directory)
        if cached and cached[0] == mtime:
            return cached[1]

        data = self._parse(path)
        self._cache[directory] = (mtime, data)
        return data

    def _parse(self, path):
        # A broken sidecar must never fail the whole sync, so problems are
        # logged and the offending file or entry is skipped.
        try:
            with open(path, encoding="utf-8") as f:
                raw = yaml.safe_load(f) or {}
        except (OSError, yaml.YAMLError) as exc:
            self._log.warning("ignoring {}: {}", path, exc)
            return None
        if not isinstance(raw, dict):
            self._log.warning("ignoring {}: top level is not a mapping", path)
            return None

        for key in raw.keys() - set(SECTIONS):
            self._log.warning("{}: unknown section {!r}", path, key)

        data = {}
        artists = raw.get("artists") or {}
        if isinstance(artists, dict):
            data["artists"] = {
                str(k): str(v) for k, v in artists.items() if v is not None
            }
        else:
            self._log.warning("{}: 'artists' is not a mapping", path)

        data["fields"] = self._fields(path, "fields", raw.get("fields"))
        for section in ("releases", "tracks"):
            entries = raw.get(section) or {}
            if not isinstance(entries, dict):
                self._log.warning("{}: {!r} is not a mapping", path, section)
                continue
            data[section] = {
                str(mbid): self._fields(path, f"{section}.{mbid}", fields)
                for mbid, fields in entries.items()
            }
        return data

    def _fields(self, path, where, fields):
        if not fields:
            return {}
        if not isinstance(fields, dict):
            self._log.warning("{}: {} is not a mapping", path, where)
            return {}
        out = {}
        for name, value in fields.items():
            if name not in Item._media_fields:
                self._log.warning(
                    "{}: {}: {!r} is not a taggable field", path, where, name
                )
                continue
            # List fields (genres, artists, …) accept a bare string as a
            # one-item list, which is what a hand-written sidecar usually has.
            if isinstance(Item._fields.get(name), types.DelimitedString):
                if isinstance(value, str):
                    value = [value]
                value = [str(v) for v in value or []]
            out[name] = value
        return out

    def _merged(self, item_path):
        root = os.path.abspath(config["directory"].as_filename())
        directory = os.path.dirname(os.path.abspath(os.fsdecode(item_path)))
        if os.path.commonpath([root, directory]) != root:
            return None

        chain = []  # nearest first
        while True:
            chain.append(directory)
            if directory == root:
                break
            directory = os.path.dirname(directory)

        merged = {section: {} for section in SECTIONS}
        found = False
        for d in reversed(chain):  # farthest first, so nearer files win
            data = self._load(d)
            if not data:
                continue
            found = True
            merged["artists"].update(data.get("artists", {}))
            merged["fields"].update(data.get("fields", {}))
            for section in ("releases", "tracks"):
                for mbid, fields in data.get(section, {}).items():
                    merged[section].setdefault(mbid, {}).update(fields)
        return merged if found else None

    # ── computing ──

    def overrides_for(self, item):
        """Return {field: value} this item's sidecars call for."""
        ov = self._merged(item.path)
        if not ov:
            return {}

        changes = {}
        for single, ids_field, id_field in (
            ("artist", "mb_artistids", "mb_artistid"),
            ("albumartist", "mb_albumartistids", "mb_albumartistid"),
        ):
            changes.update(
                self._rename(item, ov["artists"], single, ids_field, id_field)
            )

        changes.update(ov["fields"])
        changes.update(ov["releases"].get(item.get("mb_albumid") or "", {}))
        for key in ("mb_trackid", "mb_releasetrackid"):
            changes.update(ov["tracks"].get(item.get(key) or "", {}))
        return changes

    @staticmethod
    def _rename(item, renames, single, ids_field, id_field):
        if not renames:
            return {}
        plural = single + "s"
        ids = list(item.get(ids_field) or [])
        if not ids and item.get(id_field):
            ids = [item.get(id_field)]
        if not ids or ids[0] not in renames:
            return {}
        new = renames[ids[0]]
        names = list(item.get(plural) or [])

        if len(ids) > 1:
            # Joint credit: leave it, unless primaryalbumartist already
            # reduced the album artist to this one artist's name.
            if single == "albumartist" and names and item.get(single) == names[0]:
                return {single: new}
            return {}

        # One ID is not proof of a solo credit: tags from other taggers can
        # carry a joint name list or display string with only the first
        # artist's ID. Rename only when the names agree it is one artist.
        if len(names) > 1:
            return {}
        credits = list(item.get(plural + "_credit") or [])
        known = [n for n in names[:1] + credits[:1] if n]
        display = item.get(single)
        if display and display != new and not any(k in display for k in known):
            return {}

        return {
            single: _swap(display, known, new),
            plural: [new],
            single + "_credit": _swap(item.get(single + "_credit"), known, new),
            plural + "_credit": [new],
        }

    # ── applying ──

    def on_write(self, item, path, tags):
        changes = self.overrides_for(item)
        if not changes:
            return
        tags.update(changes)
        diff = {k: v for k, v in changes.items() if item.get(k) != v}
        if diff:
            # Every write path (mbsync, modify, write, import) stores the item
            # after writing, so the database ends up matching the file.
            item.update(diff)
            self._sync_album(item, diff)

    @staticmethod
    def _sync_album(item, diff):
        album = item.get_album()
        if album is None:
            return
        keys = {k: v for k, v in diff.items() if k in album.item_keys}
        if keys:
            album.update(keys)
            album.store(inherit=False)

    def apply_command(self, lib, opts, args):
        changed = 0
        for item in lib.items(args):
            diff = {
                k: v
                for k, v in self.overrides_for(item).items()
                if item.get(k) != v
            }
            if not diff:
                continue
            self._log.info("{}: {}", item.filepath, ", ".join(sorted(diff)))
            with lib.transaction():
                item.update(diff)
                self._sync_album(item, diff)
                item.try_sync(write=True, move=False)
            changed += 1
        self._log.info("applied overrides to {} item(s)", changed)


def _swap(current, known, new):
    """Replace a sole artist's name inside a display string.

    Keeps a join phrase MusicBrainz attached to the artist ("Eric Clapton &
    Friends"); falls back to the bare new name when no known name appears.
    """
    for old in known:
        if current and old in current:
            return current.replace(old, new)
    return new
