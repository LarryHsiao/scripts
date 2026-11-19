#!/usr/bin/env bash
# Tests for resize_jpg_fhd.sh, using images generated with ImageMagick itself.

here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
subject="$(dirname "$here")/resize_jpg_fhd.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if ! command -v magick >/dev/null 2>&1; then
  echo "skipped: ImageMagick (magick) is not installed, so no image can be generated"
  exit 0
fi

width() { magick identify -format '%w' "$1"; }

mkdir -p "$work/pics/sub"
magick -size 3000x1000 xc:red "$work/pics/big pic.jpg"
magick -size 3000x1000 xc:blue "$work/pics/sub/one.png"
before="$(cksum < "$work/pics/big pic.jpg")"

(cd "$work/pics" && sh "$subject" >/dev/null 2>&1)
(cd "$work/pics" && sh "$subject" >/dev/null 2>&1)

expected="$before"
check "the original is left byte-identical" "$expected" "$(cksum < "$work/pics/big pic.jpg")"

expected="2000"
check "a file with a space gets a 2000px-wide copy" "$expected" "$(width "$work/pics/resized/big pic.jpg")"

expected="2000"
check "a nested file keeps its relative path under resized/" "$expected" "$(width "$work/pics/resized/sub/one.png")"

expected="absent"
actual="absent"; [ -e "$work/pics/resized/resized" ] && actual="present"
check "resized/ is not processed on a second run" "$expected" "$actual"

# Windows: a bare `convert` there can be the system disk utility, not ImageMagick.
mkdir -p "$work/fakebin"
printf '#!/bin/sh\necho "Microsoft disk utility"\n' > "$work/fakebin/convert"
chmod +x "$work/fakebin/convert"
expected="1"
(cd "$work/pics" && PATH="$work/fakebin:/usr/bin:/bin" sh "$subject" >/dev/null 2>&1)
check "refuses a non-ImageMagick convert" "$expected" "$?"

finish
