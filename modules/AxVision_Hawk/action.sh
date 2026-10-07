echo "--------- Re-Detected Package Game -----------"

VERSION="$(getprop ro.build.version.release 2>/dev/null)"
VERSION_INT="${VERSION%%.*}"

GAME_TXT="/data/local/tmp/game.txt"

GAME_LIST="$(dumpsys game 2>/dev/null | grep -oE 'Name:[^ ]+|package [^ ]+' | sed 's/Name://;s/package //')"

if [ -z "$VERSION_INT" ]; then
    echo "[ERROR] Gagal membaca versi Android" >&2
    exit 1
fi

if [ "$VERSION_INT" -ge 12 ] 2>/dev/null; then
    # Android 12+ langsung pakai dumpsys game
    if [ -n "$GAME_LIST" ]; then
        printf "%s\n" "$GAME_LIST" > "$GAME_TXT"
    else
        echo "[WARN] GAME_LIST kosong" >&2
    fi
else
    package_list="$(cmd package list packages 2>/dev/null | cut -d':' -f2)"
    filtered=""

    if [ ! -f "$MODDIR/game.txt" ]; then
        echo "[ERROR] $MODDIR/game.txt tidak ditemukan" >&2
        exit 1
    fi

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if printf "%s\n" "$package_list" | grep -qx "$pkg"; then
            filtered="${filtered}${pkg}"$'\n'
        fi
    done < "$MODDIR/game.txt"

    printf "%s" "$filtered" > "$GAME_TXT"
fi

# Tampilkan list game
if [ -f "$GAME_TXT" ]; then
    while IFS= read -r p || [ -n "$p" ]; do
        [ -z "$p" ] && continue
        echo "   Package Game : $p"
    done < "$GAME_TXT"
else
    echo "[WARN] File game.txt tidak ditemukan" >&2
fi

echo "How to Use CLI Add Game and Add Whitelist"
echo "Add Game: vision --add_game <package>"
echo "Add Whitelist: vision --add_whitelist <package>"
echo
echo "Or more complete information is here"
echo
vision
