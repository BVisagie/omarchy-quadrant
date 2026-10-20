#!/usr/bin/env bash
# Shared AMD eligibility checks. Sourced by the stream and one-shot helper.
# All operations are Bash builtins; no GPU telemetry is read here.
# Globals form the interface consumed by both callers.
# shellcheck disable=SC2034

gpu_policy_clock() {
  local uptime rest
  GPU_POLICY_NOW=0
  if read -r uptime rest < /proc/uptime && [[ $uptime =~ ^([0-9]+)\.([0-9]{2})$ ]]; then
    GPU_POLICY_NOW=$(( 10#${BASH_REMATCH[1]} * 1000 + 10#${BASH_REMATCH[2]} * 10 ))
  fi
}

# v1, generation, CLOCK_BOOTTIME expiry milliseconds, then demand/path/vendor
# for dedicated and integrated roles. '-' represents an absent target.
gpu_policy_control() {
  local file=$1 version extra
  GPU_POLICY_GEN=0 GPU_POLICY_EXPIRY=0
  GPU_POLICY_DEMAND=0 GPU_POLICY_PATH=- GPU_POLICY_VENDOR=-
  GPU_POLICY_IGPU_DEMAND=0 GPU_POLICY_IGPU_PATH=- GPU_POLICY_IGPU_VENDOR=-
  [[ -f $file && -r $file && ! -L $file ]] || return 1
  IFS=$'\t' read -r version GPU_POLICY_GEN GPU_POLICY_EXPIRY \
    GPU_POLICY_DEMAND GPU_POLICY_PATH GPU_POLICY_VENDOR \
    GPU_POLICY_IGPU_DEMAND GPU_POLICY_IGPU_PATH GPU_POLICY_IGPU_VENDOR extra < "$file" || return 1
  [[ $version == 1 && -z $extra && $GPU_POLICY_GEN =~ ^[1-9][0-9]{0,12}$ \
    && $GPU_POLICY_EXPIRY =~ ^[1-9][0-9]{0,14}$ \
    && $GPU_POLICY_DEMAND =~ ^[01]$ && $GPU_POLICY_IGPU_DEMAND =~ ^[01]$ \
    && $GPU_POLICY_VENDOR =~ ^(-|amd|intel)$ && $GPU_POLICY_IGPU_VENDOR =~ ^(-|amd|intel)$ ]] || return 1
  local target root=${QUADRANT_SYS_PATH:-/sys}
  root=${root%/}
  for target in "$GPU_POLICY_PATH" "$GPU_POLICY_IGPU_PATH"; do
    [[ $target == - ]] && continue
    [[ $target == "$root"/class/drm/* && $target =~ /class/drm/card[0-9]+/device$ \
      && $target != *..* && $target != *[$'\t\r\n ']* ]] || return 1
  done
  gpu_policy_clock
  (( GPU_POLICY_NOW > 0 && GPU_POLICY_EXPIRY >= GPU_POLICY_NOW \
    && GPU_POLICY_EXPIRY <= GPU_POLICY_NOW + 10000 ))
}

gpu_policy_requested() {
  local file=$1 generation=$2 target=$3
  gpu_policy_control "$file" || return 1
  [[ $generation == "$GPU_POLICY_GEN" ]] || return 1
  [[ $GPU_POLICY_DEMAND == 1 && $GPU_POLICY_PATH == "$target" ]] \
    || [[ $GPU_POLICY_IGPU_DEMAND == 1 && $GPU_POLICY_IGPU_PATH == "$target" ]]
}

# Missing optional PM attributes are distinct from unreadable/invalid ones.
# A successful status read is only a check, not a lock against a transition.
gpu_policy_pm() {
  local dev=$1 value="" path=$1/power/runtime_status
  GPU_POLICY_STATE=unavailable GPU_POLICY_PM=unavailable
  [[ -d $dev ]] || return 1
  if [[ ! -e $path ]]; then return 0; fi
  if ! { IFS= read -r value < "$path"; } 2>/dev/null; then
    GPU_POLICY_STATE=failed GPU_POLICY_PM=unreadable
    return 1
  fi
  GPU_POLICY_PM=$value
  case $value in
    suspended) GPU_POLICY_STATE=sleeping; return 1 ;;
    suspending|resuming) GPU_POLICY_STATE=transitioning; return 1 ;;
    unsupported) GPU_POLICY_STATE=unavailable; return 0 ;;
    active) GPU_POLICY_STATE=fresh ;;
    *) GPU_POLICY_STATE=failed; return 1 ;;
  esac
  for path in "$dev/power/control" "$dev/power/autosuspend_delay_ms"; do
    [[ -e $path ]] || continue
    if ! { IFS= read -r value < "$path"; } 2>/dev/null; then
      GPU_POLICY_STATE=failed GPU_POLICY_PM=unreadable
      return 1
    fi
    if [[ $path == */control ]]; then
      case $value in
        on) GPU_POLICY_PM=disabled ;;
        auto) ;;
        *) GPU_POLICY_STATE=failed; GPU_POLICY_PM=invalid; return 1 ;;
      esac
    elif [[ ! $value =~ ^-?[0-9]{1,10}$ ]]; then
      GPU_POLICY_STATE=failed GPU_POLICY_PM=invalid
      return 1
    elif [[ $value == -* && $value =~ [1-9] ]]; then GPU_POLICY_PM=disabled
    fi
  done
  return 0
}
