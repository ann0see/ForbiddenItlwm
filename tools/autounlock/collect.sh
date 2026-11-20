#!/bin/bash
# Apple Watch Auto Unlock ranging probe: read-only report for issue #85.
#
# Read-only, no sudo, no installs, no network. Writes one text file in the
# current folder (or the folder you name) for you to read and then share.
#
# Usage: bash collect.sh [output-folder] [--window 15m]
#
# What it collects: macOS build, boot flags, the loaded kext, the driver's
# ranging counters and last call, System Report's Auto Unlock line, a short
# unified-log excerpt for sharingd/wifip2pd, and the ranging-related symbol
# names of those two binaries.
#
# What it leaves out: serial numbers, hardware UUIDs, MAC and Bluetooth
# addresses, network names, paired/nearby devices, your user name and home
# folder. Anything shaped like one of those is replaced. Read the file anyway.

set -u
export LC_ALL=C

OUT_DIR="."
WINDOW="15m"
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) sed -n '2,16p' "$0"; exit 0;;
        --window) WINDOW=${2:-15m}; shift 2;;
        *) OUT_DIR=$1; shift;;
    esac
done
if [ "$(uname -s)" != "Darwin" ]; then
    echo "This collector runs on macOS."
    exit 2
fi
mkdir -p "$OUT_DIR" || exit 1
OUT_DIR_ABS=$(cd "$OUT_DIR" && pwd)
OUT="$OUT_DIR_ABS/autounlock-ranging-$(date +%Y%m%d-%H%M%S).txt"
echo "Collecting. The report will be saved as:"
echo "  $OUT"

# Escape a string before using it as a sed pattern (audit T04). Short names
# aren't replaced, because they would match too much; the reader is warned.
sed_escape() { printf '%s' "$1" | sed -e 's/[][\/.^$*+?(){}|]/\\&/g'; }
REDACT_ARGS=(-e 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/<mac>/g'
             -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<uuid>/g'
             -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g'
             -e 's/\b(C02|FVF|FVC|G02|W02|VMW)[A-Z0-9]{9,14}\b/<serial>/g'
             -e 's/(SSID|BSSID|Network Name|Device Name)[ =:]+[^,;]*/<network>/g')
SHORT_NAMES=""
add_redaction() {
    local value=$1 label=$2
    [ -n "$value" ] || return 0
    if [ "${#value}" -lt 3 ]; then SHORT_NAMES="$SHORT_NAMES $label"; return 0; fi
    REDACT_ARGS+=(-e "s/$(sed_escape "$value")/<$label>/g")
}
add_redaction "${HOME:-}" home
add_redaction "$(scutil --get ComputerName 2>/dev/null || true)" host
add_redaction "$(scutil --get LocalHostName 2>/dev/null || true)" host
add_redaction "$(id -un 2>/dev/null || true)" user
redact() { sed -E "${REDACT_ARGS[@]}"; }
section() { printf '\n===== %s =====\n' "$1"; }

{
echo "Auto Unlock ranging probe report"
echo "Collector version 1, written $(date -u +%Y-%m-%dT%H:%MZ)"
echo "Share this file only after reading it."

section "System"
echo "macOS: $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
echo "Kernel: $(uname -r) $(uname -m)"
echo "Model identifier: $(sysctl -n hw.model 2>/dev/null)"

section "Boot flags of interest"
for t in $(sysctl -n kern.bootargs 2>/dev/null); do
    case "$t" in -itlawdl*|itlawdl*|-btleadv*|-btlenoscan|itlwm_he=*) printf '%s ' "$t";; esac
done
echo

section "Loaded driver"
kmutil showloaded --list-only 2>/dev/null | awk '{print $6, $7}' | grep -E -i 'forbiddenitlwm|BTLEAdvFixup|itlwm' | redact
echo "Build marker: $(ioreg -l -w0 2>/dev/null | sed -n 's/.*"ItlwmAWDLInterfaceBuild" = "\([^"]*\)".*/\1/p' | head -1)"

section "Ranging probe (read immediately after an unlock attempt)"
# Only counters and selector numbers: the driver never touches a payload.
ioreg -l -w0 2>/dev/null |
    grep -o '"\(ItlwmRangingProbe\|ItlwmRangingProbeLast\|ItlwmUnhandledRequest\|ItlwmAWDLInterfaceTestEnabled\)" = \([^,]*\)' |
    sort -u | redact
echo "(no lines above means the probe wasn't loaded, or the driver was restarted)"

section "System Report"
system_profiler SPAirPortDataType 2>/dev/null |
    awk '/(Auto Unlock|AirDrop|Status|Card Type|Firmware Version):/ { sub(/^ +/, ""); print }' | redact

section "Interfaces"
ifconfig -l 2>/dev/null | redact
ifconfig awdl0 2>/dev/null | awk '/^(awdl0|[ \t]*(flags|status)):/ {print}' | redact

section "Unified log, last $WINDOW"
# No addresses are printed by these calls, but the redaction still applies.
log show --last "$WINDOW" --style compact \
    --predicate '(process == "sharingd" OR process == "wifip2pd" OR eventMessage CONTAINS[c] "ranging" OR eventMessage CONTAINS[c] "Auto Unlock")' \
    2>/dev/null | head -300 | redact

section "Ranging symbols on disk"
for bin in /usr/libexec/sharingd /usr/libexec/wifip2pd; do
    [ -x "$bin" ] || continue
    echo "--- $bin"
    nm -m "$bin" 2>/dev/null |
        grep -i -E 'rang|awdl|unlock|localLTK|wifiRanging|peerDiscovery' |
        head -120 | redact
done
} > "$OUT" 2>&1

echo
echo "Done. Report saved to:"
echo "  $OUT"
echo
echo "Read it before sharing. It should contain no serial numbers, addresses,"
echo "network names or device names."
if [ -n "$SHORT_NAMES" ]; then
    echo "Your$SHORT_NAMES name is shorter than 3 characters, so it wasn't replaced."
    echo "Search the report for it and remove it by hand before sharing."
fi
