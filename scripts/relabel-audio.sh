#!/usr/bin/env -S nix shell nixpkgs#mkvtoolnix nixpkgs#jq nixpkgs#fzf -c bash
# shellcheck shell=bash
# Interactively relabel audio track languages (and optionally names) in MKV files.
# Edits headers in place with mkvpropedit, so no remux is needed.
#
# Usage: relabel-audio.sh [FILE_OR_DIR...]     (default: /mnt/movies/data)
# Dependencies (mkvtoolnix, jq, fzf) are loaded by the shebang's nix shell.
set -euo pipefail

roots=("$@")
[[ ${#roots[@]} -eq 0 ]] && roots=(/mnt/movies/data)

# Collect the MKVs to work on: explicit files as given, directories searched recursively
files=()
for root in "${roots[@]}"; do
  if [[ -d $root ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$root" -type f -iname '*.mkv' | sort)
  else
    files+=("$root")
  fi
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No MKV files found." >&2
  exit 1
fi

# Let the user pick from a directory search; explicit single files skip the picker
if [[ ${#roots[@]} -gt 0 && ! ( ${#roots[@]} -eq 1 && -f ${roots[0]} ) ]]; then
  mapfile -t files < <(printf '%s\n' "${files[@]}" | fzf --multi --height=80% --prompt='MKV> ' \
    --header='TAB to select several, ENTER to confirm' || true)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "Nothing selected."
  exit 0
fi

# Print audio tracks of $1 as: a<N>  id  language  codec  name
list_audio() {
  mkvmerge -J "$1" | jq -r '
    [.tracks[] | select(.type == "audio")] | to_entries[] |
    "a\(.key + 1)\tid=\(.value.id)\tlang=\(.value.properties.language // "und")\t\(.value.codec)\tname=\(.value.properties.track_name // "")"'
}

# Give $1 its own inode so other hard links to the old data stay unmodified
split_hard_link() {
  local file=$1 tmp="$1.relabel-part"
  cp -a --reflink=auto -- "$file" "$tmp" || { rm -f -- "$tmp"; exit 1; }
  mv -f -- "$tmp" "$file"
}

relabel_file() {
  local file=$1 links track lang name split
  echo
  echo "== $file"

  # mkvpropedit writes in place, so a hard-linked file changes under every name it has
  links=$(stat -c %h "$file")
  if [[ $links -gt 1 ]]; then
    echo "  this file has $links hard links; editing it would change all of them."
    read -rp "  Split it first (copy; the other links stay unmodified)? [Y/n] " split
    if [[ ${split:-y} == [yY] ]]; then
      split_hard_link "$file"
      echo "  split: $file is now its own copy."
    else
      echo "  not splitting: the edit will change all $links links."
    fi
  fi

  while true; do
    echo
    list_audio "$file" | sed 's/^/  /'
    read -rp "  Audio track to relabel (a1..., blank = next file): " track
    [[ -z $track ]] && return 0
    if ! [[ $track =~ ^a[0-9]+$ ]] || ! list_audio "$file" | cut -f1 | grep -qx "$track"; then
      echo "  invalid track: $track"
      continue
    fi

    read -rp "  New language, ISO 639-2 [jpn]: " lang
    lang=${lang:-jpn}
    if ! [[ $lang =~ ^[a-z]{3}$ ]]; then
      echo "  language must be three lowercase letters (jpn, eng, kor, zho, und)"
      continue
    fi

    read -rp "  New track name (blank = keep, '-' = clear): " name

    local args=(--edit "track:$track" --set "language=$lang")
    case $name in
      '') ;;
      -) args+=(--set name=) ;;
      *) args+=(--set "name=$name") ;;
    esac

    read -rp "  Apply ${track}: ${lang}${name:+, name=$name}? [y/N] " ok
    if [[ $ok == [yY] ]]; then
      mkvpropedit "$file" "${args[@]}" >/dev/null
      echo "  done:"
      list_audio "$file" | sed 's/^/    /'
    else
      echo "  skipped"
    fi
  done
}

for file in "${files[@]}"; do
  relabel_file "$file"
done
