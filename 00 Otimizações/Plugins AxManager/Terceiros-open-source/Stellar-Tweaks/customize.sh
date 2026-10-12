#!/system/bin/sh

# Copyright (C) 2024-2025 Kanao
# Licensed under the Apache License, Version 2.0
# See http://www.apache.org/licenses/LICENSE-2.0

SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=true
LATESTARTSERVICE=true

BASEDIR="/data/adb/.config/stellar"

ENVIRONMENT=""
USE_SKIPMOUNT=false

ui_print() {
    echo "- $1"
    sleep 0.1
}

abort_clean() {
    echo " "
    echo "******************************************** "
    echo "! ERROR: $1"
    echo "! Installation failed! $2" 
    echo "******************************************** "
    echo " "
    exit 1
}

set_perm_recursive() {
    chown -R $2:$3 "$1" 2>/dev/null
    find "$1" -type d -exec chmod $4 {} \; 2>/dev/null
    find "$1" -type f -exec chmod $5 {} \; 2>/dev/null
}

remove_config() {
    if [ "$AXERON" = "true" ]; then
        rm -rf /data/user_de/0/com.android.shell/axeron/plugins/stellar/.config 2>/dev/null
    else
        rm -rf /data/adb/.config/stellar 2>/dev/null
    fi

    pm uninstall bellavita.toast >/dev/null 2>&1
    ui_print "Clean up old config"
}

detect_environment() {
    ui_print "Detecting device environment..."
    
    if [ "$AXERON" = "true" ]; then
        ENVIRONMENT="AXERON"
        BASEDIR="/data/user_de/0/com.android.shell/axeron/plugins/stellar/.config"
        USE_SKIPMOUNT=true
        ui_print "Axeron detected"
        return
    fi
    
    if [ "$(id | grep -c root)" -gt 0 ]; then
        if [ -d "/data/adb/ksu" ]; then
            ENVIRONMENT="KSU"
            USE_SKIPMOUNT=true
            ui_print "KernelSU detected"
            return
        fi
        
        if [ -d "/data/adb/ap" ]; then
            ENVIRONMENT="APATCH"
            USE_SKIPMOUNT=true
            ui_print "APatch detected"
            return
        fi
        
        ENVIRONMENT="OTHER"
        ui_print "Root environment detected"
        return
    fi
    
    abort_clean "No environment detected" "Ensure you have one"
}

apply_skipmount() {
    if $USE_SKIPMOUNT; then
        ui_print "Applying some rules for $ENVIRONMENT"
        touch "$MODPATH/skip_mount"
        [ -f "$MODPATH/action.sh" ] && rm -f "$MODPATH/action.sh" && ui_print "Removed action.sh"
    fi
}

setup_directories_and_configs() {
    ui_print "Setting up default directories..."
    mkdir -p "$BASEDIR" || abort_clean "Failed to create directory"
    chmod 0755 "$BASEDIR"
}

install_stellar_binary() {
    ui_print "Setting up Stellar binaries..."

    local ABI="armeabi-v7a"
    local RAW_ABI="$(getprop ro.product.cpu.abi 2>/dev/null)"
    case "$RAW_ABI" in
        arm64-v8a*|aarch64*) ABI="arm64-v8a" ;;
        *)
            if [ "$(uname -m 2>/dev/null)" = "aarch64" ]; then
                ABI="arm64-v8a"
            else
                ABI="armeabi-v7a"
            fi
            ;;
    esac

    ui_print "Selected architecture: $ABI"

    local SRC_FILE="$MODPATH/libs/$ABI/stellar-daemon"
    if [ ! -f "$SRC_FILE" ]; then
        abort_clean "Binary for architecture $ABI not found in package!"
    fi

    local SRC_BIN="$MODPATH/system/bin"
    local DEST_BIN=""

    case $ENVIRONMENT in
        "AXERON") DEST_BIN="/data/user_de/0/com.android.shell/axeron/bin" ;;
        "KSU")    DEST_BIN="/data/adb/ksu/bin" ;;
        "APATCH") DEST_BIN="/data/adb/ap/bin" ;;
        "OTHER")  DEST_BIN="" ;;
    esac

    mkdir -p "$SRC_BIN"

    if [ -n "$DEST_BIN" ]; then
        mkdir -p "$DEST_BIN"
        rm -f "$DEST_BIN/stellar-daemon"
        cp -f "$SRC_FILE" "$DEST_BIN/stellar-daemon"
        chmod 0777 "$DEST_BIN/stellar-daemon"
        ln -sf "$DEST_BIN/stellar-daemon" "$SRC_BIN/stellar-daemon" 2>/dev/null
        ui_print "Binary installed to: $DEST_BIN/stellar-daemon (symlinked)"
    else
        cp -f "$SRC_FILE" "$SRC_BIN/stellar-daemon"
        chmod 0777 "$SRC_BIN/stellar-daemon"
        ui_print "Binary installed to: $SRC_BIN/stellar-daemon"
    fi

    rm -rf "$MODPATH/libs"
}

set_permissions() {
    ui_print "Setting all permissions for bin..."
    
    [ -d "$MODPATH" ] && set_perm_recursive "$MODPATH" 0 0 0755 0644
    [ -d "$MODPATH/system/bin" ] && set_perm_recursive "$MODPATH/system/bin" 0 2000 0755 0755
    [ -f "$MODPATH/service.sh" ] && chmod 0755 "$MODPATH/service.sh"
    [ -f "$MODPATH/action.sh" ] && chmod 0755 "$MODPATH/action.sh"
    [ -f "$MODPATH/uninstall.sh" ] && chmod 0755 "$MODPATH/uninstall.sh"
}

finalize_installation() {
    case $((RANDOM % 9 + 1)) in
        1) ui_print "Stars orbit until they die." ;;
        2) ui_print "Still Stellar-Stellar?" ;;
        3) ui_print "Against The Law, Dont Soft." ;;
        4) ui_print "Dead Stars, Exploding, Lost, Forgotten." ;;
        5) ui_print "Feed Me Donate Wen." ;;
        6) ui_print "Try Be Honest, May Can Safe You (?)" ;;
        7) ui_print "Anyone Would Seen This?!" ;;
        8) ui_print "Save the world? Save the cat!" ;;
        9) ui_print "The glitches that never saw again." ;;
    esac
    
    ui_print "Join our channel for keep updated!"
}

detect_environment
remove_config
apply_skipmount
setup_directories_and_configs
install_stellar_binary
set_permissions
finalize_installation
