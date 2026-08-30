# shellcheck shell=bash
# Intel GT frequency sysfs lookup. Sourced by gpu-stats and quadrant-stream.
# $1 is the PCI device directory (.../cardN/device). Frequency files may live
# on that device node (classic i915), on the parent DRM card node (current
# i915), under gt/gt0 (newer i915), or under tile*/gt*/freq0 (xe).
#
# Not executable on its own. Keep this file free of `set -e` side effects:
# callers decide how a missing path is handled.

intel_card_dir() {
  local dev=$1
  local card=${dev%/device}
  if [[ -z $dev || $card == "$dev" ]]; then
    return 1
  fi
  printf '%s' "$card"
}

intel_pick_readable() {
  local cand
  for cand in "$@"; do
    [[ -n $cand && -r $cand ]] || continue
    printf '%s' "$cand"
    return 0
  done
  return 1
}

# Append matching globs to the nameref array in $1. Unmatched globs are skipped.
intel_append_glob() {
  # shellcheck disable=SC2178,SC2034
  local -n _intel_out=$1
  shift
  local cand
  for cand in "$@"; do
    [[ -e $cand ]] || continue
    _intel_out+=("$cand")
  done
}

intel_freq_cur_path() {
  local dev=$1 card=""
  local -a cands=()
  [[ -n $dev ]] || return 1
  card=$(intel_card_dir "$dev") || card=""
  cands+=("$dev/gt_cur_freq_mhz")
  [[ -n $card ]] && cands+=("$card/gt_cur_freq_mhz")
  cands+=("$dev/gt/gt_cur_freq_mhz")
  [[ -n $card ]] && cands+=("$card/gt/gt0/rps_cur_freq_mhz")
  intel_append_glob cands "$dev"/tile*/gt*/freq0/cur_freq
  [[ -n $card ]] && intel_append_glob cands "$card"/tile*/gt*/freq0/cur_freq
  intel_pick_readable "${cands[@]}"
}

intel_freq_max_path() {
  local dev=$1 card=""
  local -a cands=()
  [[ -n $dev ]] || return 1
  card=$(intel_card_dir "$dev") || card=""
  # rp0 / max are the peak; rpn is the floor and must not be used as max.
  cands+=("$dev/gt_max_freq_mhz")
  [[ -n $card ]] && cands+=("$card/gt_max_freq_mhz")
  cands+=("$dev/gt/gt_max_freq_mhz")
  [[ -n $card ]] && cands+=("$card/gt/gt0/rps_max_freq_mhz")
  intel_append_glob cands "$dev"/tile*/gt*/freq0/rp0_freq
  [[ -n $card ]] && intel_append_glob cands "$card"/tile*/gt*/freq0/rp0_freq
  intel_append_glob cands "$dev"/tile*/gt*/freq0/max_freq
  [[ -n $card ]] && intel_append_glob cands "$card"/tile*/gt*/freq0/max_freq
  intel_pick_readable "${cands[@]}"
}
