#! /bin/sh

for file in `find . -name '*.jpg' -o -name '*.JPG' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpeg' -o -name '*.JPEG'`
do
    echo $file
    convert $file -resize 2000x $file
done
