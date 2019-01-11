#! /bin/sh

adb kill-server
adb devices > /dev/null 2>&1 &
