#! /bin/sh

for file in `ls *.JPG *.jpg *.jpeg *.JPEG`
do
    echo $file
    convert $file -resize 2000x $file
done
