#!/bin/sh

# Copyright (C) 2024-2025 Kanao
# Licensed under the Apache License, Version 2.0
# See http://www.apache.org/licenses/LICENSE-2.0

# Resetting Default Value
packages=$(dumpsys settings | grep -Eo 'pkg:[^ ]+' | sort | uniq | cut -f2 -d:)
for package in $packages; do
    cmd settings reset global "$package"
    cmd settings reset secure "$package"
done

# Resetting Fully
pm uninstall bellavita.toast
pkill -9 stellar-daemon
stellar-daemon clean all

# Old binary
BINS="stellar-daemon"
for DIR in /data/adb/*/bin /system/bin /data/user_de/0/com.android.shell/axeron/bin/; do
    [ -d "$DIR" ] && for BIN in $BINS; do
        rm -f "$DIR/$BIN"
    done
done