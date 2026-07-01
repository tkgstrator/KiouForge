#!/usr/bin/env bash
# pull_crash.sh — fetch iOS crash reports + sandbox logs from a JB device.
#
# Deterministic: bundle ID prefix is read from the Tweak filter plist, not
# inferred. Device IP comes from $THEOS_DEVICE_IP, or the project Makefile
# default, or the script's --ip argument. Output is logs/crashes/<prefix-
# sanitized>-<timestamp>/ relative to the repository root.
#
# Usage:
#   .claude/scripts/pull_crash.sh [--prefix com.example] [--ip 1.2.3.4]
#                                  [--plist KiouForge.plist] [--root .]
#
# All flags are optional. The script exits non-zero on hard failures
# (no SSH connectivity, no matching device application). Missing pieces
# inside the run (e.g. an app with no sandbox Logs dir) are logged and
# skipped — partial results are still written.

set -uo pipefail

PREFIX=""
IP=""
PLIST=""
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --ip)     IP="$2";     shift 2 ;;
        --plist)  PLIST="$2";  shift 2 ;;
        --root)   ROOT="$2";   shift 2 ;;
        -h|--help)
            sed -n '2,18p' "$0"; exit 0 ;;
        *)
            echo "pull_crash: unknown flag $1" >&2; exit 2 ;;
    esac
done

cd "$ROOT" || { echo "pull_crash: cannot cd to $ROOT" >&2; exit 2; }

# --- 1. bundle ID prefix ----------------------------------------------------
if [ -z "$PREFIX" ]; then
    if [ -z "$PLIST" ]; then
        PLIST=$(find . -maxdepth 2 -name '*.plist' \
                     -not -path './assets/*' \
                     -not -path './packages/*' \
                     -not -path './.theos/*' \
                     -not -path './vendor/*' 2>/dev/null \
                | head -1)
    fi
    if [ -z "$PLIST" ] || [ ! -f "$PLIST" ]; then
        echo "pull_crash: no Tweak plist found; pass --prefix or --plist" >&2
        exit 2
    fi
    # Extract first <string> inside the Bundles <array>. XML plist only —
    # the Tweak filter plist Theos generates is always XML, never binary.
    PREFIX=$(awk '
        /<key>Bundles<\/key>/ { in_b=1; next }
        in_b && /<string>/ {
            sub(/.*<string>/,"")
            sub(/<\/string>.*/,"")
            print
            exit
        }' "$PLIST" 2>/dev/null)
fi

# Sanity: prefix must be ASCII identifier-ish (letters, digits, dots, -, _).
if ! printf '%s' "$PREFIX" | grep -qE '^[A-Za-z0-9._-]+$'; then
    echo "pull_crash: extracted prefix is not a valid bundle id: '$PREFIX'" >&2
    exit 2
fi
if [ -z "$PREFIX" ]; then
    echo "pull_crash: could not read bundle ID prefix from $PLIST" >&2
    exit 2
fi

# --- 2. device IP -----------------------------------------------------------
if [ -z "$IP" ] && [ -n "${THEOS_DEVICE_IP:-}" ]; then
    IP="$THEOS_DEVICE_IP"
fi
if [ -z "$IP" ] && [ -f Makefile ]; then
    IP=$(grep -E '^THEOS_DEVICE_IP[[:space:]]*[?]=' Makefile \
         | head -1 \
         | sed -E 's/^THEOS_DEVICE_IP[[:space:]]*[?]=[[:space:]]*//' \
         | tr -d '[:space:]')
fi
if [ -z "$IP" ]; then
    echo "pull_crash: device IP not set; pass --ip or export THEOS_DEVICE_IP" >&2
    exit 2
fi

SSH_OPTS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes)
# -n keeps ssh from swallowing stdin (otherwise it eats lines from while-read loops).
SSH() { ssh -n "${SSH_OPTS[@]}" "root@$IP" "$@"; }
if ! SSH 'echo ok' >/dev/null 2>&1; then
    echo "pull_crash: cannot reach root@$IP via SSH" >&2
    exit 1
fi

# --- 3. output directory ----------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
SAFE_PREFIX=${PREFIX//./-}
OUT="logs/crashes/${SAFE_PREFIX}-${TS}"
mkdir -p "$OUT/crashreporter" "$OUT/sandbox"

# --- 4. crash reports -------------------------------------------------------
# Match by JSON-header bundleID OR by filename prefix (proc_name resource
# diagnostics like KIOU.wakeups_resource-*.ips carry the proc name as the
# filename prefix but a different bundleID in the JSON).
ESCAPED_PREFIX=$(printf '%s' "$PREFIX" | sed 's/[.[\*^$/]/\\&/g')
LIST_FILE="$OUT/crash-list.txt"
SSH "for f in /var/mobile/Library/Logs/CrashReporter/*.ips; do
        [ -f \"\$f\" ] || continue
        head -1 \"\$f\" | grep -qE '\"bundleID\":\"${ESCAPED_PREFIX}([.][^\"]*)?\"' && echo \"\$f\"
     done" > "$LIST_FILE" 2>/dev/null

CRASH_COUNT=0
if [ -s "$LIST_FILE" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if scp -q "${SSH_OPTS[@]}" "root@$IP:$f" "$OUT/crashreporter/" 2>/dev/null; then
            CRASH_COUNT=$((CRASH_COUNT + 1))
        fi
    done < "$LIST_FILE"
fi

# --- 5. sandbox discovery ---------------------------------------------------
# All applications whose MCMMetadataIdentifier starts with the prefix.
# Binary plists pack strings without surrounding whitespace, so `strings`
# can split the id into multiple chunks. Use `grep -ao` to extract the
# bundle id straight from the raw bytes.
SANDBOX_FILE="$OUT/sandbox-list.txt"
SSH "for d in /var/mobile/Containers/Data/Application/*/; do
        p=\"\${d}.com.apple.mobile_container_manager.metadata.plist\"
        [ -f \"\$p\" ] || continue
        grep -aq '${PREFIX}' \"\$p\" 2>/dev/null || continue
        id=\$(grep -aoE '${ESCAPED_PREFIX}([.][A-Za-z0-9_-]+)*' \"\$p\" 2>/dev/null | sort -u | head -1)
        [ -n \"\$id\" ] && echo \"\$id|\$d\"
     done" > "$SANDBOX_FILE" 2>/dev/null

SANDBOX_COUNT=0
LOG_COUNT=0
if [ -s "$SANDBOX_FILE" ]; then
    while IFS='|' read -r bundle dir; do
        [ -n "$dir" ] || continue
        safe_bundle=${bundle//./-}
        dest="$OUT/sandbox/$safe_bundle"
        mkdir -p "$dest"
        for sub in Documents/Logs Library/Logs tmp/Logs; do
            # Probe existence first so missing dirs don't pollute stderr.
            if SSH "[ -d \"${dir}${sub}\" ]"; then
                mkdir -p "$dest/$sub"
                if scp -q -r "${SSH_OPTS[@]}" "root@$IP:${dir}${sub}/." "$dest/$sub/" 2>/dev/null; then
                    n=$(find "$dest/$sub" -type f 2>/dev/null | wc -l)
                    LOG_COUNT=$((LOG_COUNT + n))
                fi
            fi
        done
        SANDBOX_COUNT=$((SANDBOX_COUNT + 1))
    done < "$SANDBOX_FILE"
fi

# --- 6. summary -------------------------------------------------------------
LATEST_IPS=""
if [ "$CRASH_COUNT" -gt 0 ]; then
    LATEST_IPS=$(ls -t "$OUT/crashreporter"/*.ips 2>/dev/null | head -1 | xargs -I{} basename {})
fi

cat <<EOF
pull_crash: done
  prefix:        $PREFIX
  device:        root@$IP
  output:        $OUT
  crash reports: $CRASH_COUNT$([ -n "$LATEST_IPS" ] && echo " (latest: $LATEST_IPS)")
  sandboxes:     $SANDBOX_COUNT
  log files:     $LOG_COUNT
EOF
