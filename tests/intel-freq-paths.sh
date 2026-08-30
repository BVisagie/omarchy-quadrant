#!/usr/bin/env bash
# Fake-sysfs coverage for Intel GT frequency lookup.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../scripts/gpu-intel-paths.sh
source "$ROOT/scripts/gpu-intel-paths.sh"

fail() { echo "intel-freq-paths: $*" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Card-node i915 (Meteor Lake / Ultra 9): freq lives beside device/, not in it.
mkdir -p "$TMP/card1/device"
printf '1300\n' > "$TMP/card1/gt_cur_freq_mhz"
printf '2350\n' > "$TMP/card1/gt_max_freq_mhz"
cur=$(intel_freq_cur_path "$TMP/card1/device") || fail "card-node cur missing"
max=$(intel_freq_max_path "$TMP/card1/device") || fail "card-node max missing"
[[ $cur == "$TMP/card1/gt_cur_freq_mhz" ]] || fail "card-node cur path: $cur"
[[ $max == "$TMP/card1/gt_max_freq_mhz" ]] || fail "card-node max path: $max"

# Newer i915 GT sysfs.
mkdir -p "$TMP/card2/device" "$TMP/card2/gt/gt0"
printf '500\n' > "$TMP/card2/gt/gt0/rps_cur_freq_mhz"
printf '1800\n' > "$TMP/card2/gt/gt0/rps_max_freq_mhz"
cur=$(intel_freq_cur_path "$TMP/card2/device") || fail "gt0 cur missing"
max=$(intel_freq_max_path "$TMP/card2/device") || fail "gt0 max missing"
[[ $cur == "$TMP/card2/gt/gt0/rps_cur_freq_mhz" ]] || fail "gt0 cur path: $cur"
[[ $max == "$TMP/card2/gt/gt0/rps_max_freq_mhz" ]] || fail "gt0 max path: $max"

# xe: cur_freq + rp0_freq (not rpn_freq).
mkdir -p "$TMP/card0/device/tile0/gt0/freq0"
printf '400\n' > "$TMP/card0/device/tile0/gt0/freq0/cur_freq"
printf '100\n' > "$TMP/card0/device/tile0/gt0/freq0/rpn_freq"
printf '2000\n' > "$TMP/card0/device/tile0/gt0/freq0/rp0_freq"
cur=$(intel_freq_cur_path "$TMP/card0/device") || fail "xe cur missing"
max=$(intel_freq_max_path "$TMP/card0/device") || fail "xe max missing"
[[ $cur == "$TMP/card0/device/tile0/gt0/freq0/cur_freq" ]] || fail "xe cur path: $cur"
[[ $max == "$TMP/card0/device/tile0/gt0/freq0/rp0_freq" ]] || fail "xe max path: $max"

# No freq files → failure, not a bogus glob path.
mkdir -p "$TMP/card9/device"
if intel_freq_cur_path "$TMP/card9/device" >/dev/null; then
  fail "expected no cur path on empty card"
fi

echo "intel-freq-paths: ok"
