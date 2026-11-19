#! /bin/sh
# Writes a 2000px-wide copy of every jpg/jpeg/png under the current folder into
# ./resized/ (same relative paths), leaving the originals untouched.

width=2000

if command -v magick >/dev/null 2>&1; then
    resize="magick"
elif convert -version 2>/dev/null | grep -q ImageMagick; then
    resize="convert"
else
    echo "ImageMagick not found (on Windows, a bare 'convert' is the system disk utility)" >&2
    exit 1
fi

find . -path ./resized -prune -o -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print |
while IFS= read -r file
do
    echo "$file"
    mkdir -p "resized/$(dirname "$file")"
    $resize "$file" -resize "${width}x" "resized/$file"
done
