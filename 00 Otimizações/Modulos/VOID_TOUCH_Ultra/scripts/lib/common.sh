# VOID TOUCH Ultra v5.1.0 — Common Library
# Android /system/bin/sh compatible — ASCII only

# --- Colors ---
C='\033[36m'
G='\033[32m'
Y='\033[33m'
R='\033[31m'
B='\033[1m'
N='\033[0m'

# --- Counters ---
PASS=0; SKIP=0; WARN=0; FAIL_C=0; CHANGED=0

# --- Output (printf %b for colors) ---
say()  { printf '%b\n' "$*"; }
log()  { printf '%s\n' "$*" >> "$LOG"; }
report(){ printf '%s\n' "$*" >> "$REPORT"; }

ok()   { PASS=$((PASS+1));   printf '%b\n' "  ${G}[OK]${N}    $*"; log "[OK]   $*"; }
skip() { SKIP=$((SKIP+1));   printf '%b\n' "  ${Y}[SKIP]${N}  $*"; log "[SKIP] $*"; }
warn() { WARN=$((WARN+1));   printf '%b\n' "  ${Y}[WARN]${N}  $*"; log "[WARN] $*"; }
fail() { FAIL_C=$((FAIL_C+1)); printf '%b\n' "  ${R}[FAIL]${N}  $*"; log "[FAIL] $*"; }

# --- Getters ---
get()  { settings get "$1" "$2" 2>/dev/null; }
prop() { getprop "$1" 2>/dev/null; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
nonempty(){ [ -n "$1" ] && [ "$1" != "null" ] && [ "$1" != "NULL" ] && [ "$1" != "" ]; }

# --- Detect brand ---
detect_brand(){
    _m="$(prop ro.product.manufacturer | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
    _b="$(prop ro.product.brand | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
    _all="$_m $_b"
    case "$_all" in
        *samsung*)  BRAND="samsung" ;;
        *xiaomi*|*redmi*|*poco*) BRAND="xiaomi" ;;
        *oneplus*)  BRAND="oneplus" ;;
        *oppo*|*realme*) BRAND="oppo" ;;
        *google*)   BRAND="pixel" ;;
        *huawei*|*honor*) BRAND="huawei" ;;
        *motorola*|*lenovo*) BRAND="motorola" ;;
        *sony*)     BRAND="sony" ;;
        *vivo*)     BRAND="vivo" ;;
        *asus*)     BRAND="asus" ;;
        *nothing*)  BRAND="nothing" ;;
        *)          BRAND="generic" ;;
    esac
}

# --- REDESIGNED safe_set: TRY FIRST, verify after ---
# No longer skips on null — tries writing and checks if it sticks
# Usage: safe_set <namespace> <key> <value> <label>
safe_set(){
    _ns="$1"; _key="$2"; _val="$3"; _label="$4"
    _old="$(get "$_ns" "$_key")"

    # Already at target value?
    if [ "$_old" = "$_val" ]; then
        ok "$_label (ja otimizado: $_val)"
        return 0
    fi

    # Backup original value (even null)
    printf '%s %s %s\n' "$_ns" "$_key" "${_old:-null}" >> "$BACKUP/settings_backup.txt"

    # Try to write
    settings put "$_ns" "$_key" "$_val" >/dev/null 2>&1

    # Verify write
    _new="$(get "$_ns" "$_key")"
    if [ "$_new" = "$_val" ]; then
        CHANGED=$((CHANGED+1))
        if nonempty "$_old"; then
            ok "$_label ($_old -> $_val)"
        else
            ok "$_label (ativado: $_val)"
        fi
        report "$_ns.$_key: ${_old:-null} -> $_val"
        return 0
    else
        # Write failed or didn't stick
        skip "$_label (nao aplicavel)"
        return 1
    fi
}

# --- Convenience wrappers ---
safe_disable(){ safe_set "$1" "$2" "0" "$3"; }
safe_enable(){  safe_set "$1" "$2" "1" "$3"; }

# --- Numeric comparisons with safe_set ---
safe_set_max(){
    _ns="$1"; _key="$2"; _max="$3"; _label="$4"
    _old="$(get "$_ns" "$_key")"
    if [ -z "$_old" ] || [ "$_old" = "null" ]; then
        # Try writing the max value anyway
        safe_set "$_ns" "$_key" "$_max" "$_label"
        return
    fi
    case "$_old" in
        *[!0-9-]*) skip "$_label (valor nao numerico: $_old)"; return ;;
    esac
    if [ "$_old" -gt "$_max" ] 2>/dev/null; then
        safe_set "$_ns" "$_key" "$_max" "$_label"
    else
        ok "$_label (ja otimizado: $_old)"
    fi
}

safe_set_min(){
    _ns="$1"; _key="$2"; _min="$3"; _label="$4"
    _old="$(get "$_ns" "$_key")"
    if [ -z "$_old" ] || [ "$_old" = "null" ]; then
        safe_set "$_ns" "$_key" "$_min" "$_label"
        return
    fi
    case "$_old" in
        *[!0-9-]*) skip "$_label (valor nao numerico: $_old)"; return ;;
    esac
    if [ "$_old" -lt "$_min" ] 2>/dev/null; then
        safe_set "$_ns" "$_key" "$_min" "$_label"
    else
        ok "$_label (ja otimizado: $_old)"
    fi
}

# --- Try setting in multiple namespaces ---
# try_set <key> <value> <label> <ns1> [ns2] [ns3]
try_set(){
    _key="$1"; _val="$2"; _label="$3"
    shift 3
    for _ns in "$@"; do
        _old="$(get "$_ns" "$_key")"
        if [ "$_old" = "$_val" ]; then
            ok "$_label (ja otimizado: $_val)"
            return 0
        fi
        if nonempty "$_old"; then
            safe_set "$_ns" "$_key" "$_val" "$_label"
            return $?
        fi
    done
    # None had a value — try writing to first namespace
    safe_set "$1" "$_key" "$_val" "$_label"
}

# --- Snapshot ---
snapshot_cmd(){
    _name="$1"; shift
    "$@" > "$SNAP/$_name.txt" 2>/dev/null || true
}
