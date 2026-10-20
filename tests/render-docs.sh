#!/usr/bin/env bash
# Refresh every current documentation screenshot using native QML fixtures.
# Usage: tests/render-docs.sh [output-directory]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=${1:-docs/screenshots}
mkdir -p "$out"

# A caller's previous layout experiment must not change the published set.
for variable in "${!QUADRANT_RENDER_@}"; do unset "$variable"; done
export TZ=UTC QT_SCALE_FACTOR=1 QT_FONT_DPI=96
export QUADRANT_RENDER_DOCUMENTATION=1 QUADRANT_RENDER_WIDTH=752
export QUADRANT_RENDER_FIT=1 QUADRANT_RENDER_HEADER=1 QUADRANT_RENDER_PALETTE=dark

bash tests/render.sh cpu "$out/cpu.png"
QUADRANT_RENDER_PALETTE=light bash tests/render.sh gpu "$out/gpu.png"
QUADRANT_RENDER_PALETTE=mono bash tests/render.sh mem "$out/memory.png"
bash tests/render.sh disk "$out/drives.png"
QUADRANT_RENDER_PALETTE=light bash tests/render.sh net "$out/network.png"
bash tests/render.sh hardware "$out/hardware.png"
bash tests/render.sh settings "$out/settings.png"
QUADRANT_RENDER_PALETTE=light QUADRANT_RENDER_EXPANDED=1 \
  bash tests/render.sh mem "$out/process-exploration.png"

unset QUADRANT_RENDER_DOCUMENTATION QUADRANT_RENDER_WIDTH QUADRANT_RENDER_FIT QUADRANT_RENDER_HEADER
export QUADRANT_RENDER_ORDER=cpu,gpu,memory,disk,network
QT_SCALE_FACTOR=2 QUADRANT_RENDER_BARE=1 QUADRANT_RENDER_BAR_STYLE=text QUADRANT_RENDER_SEGMENTS=cpu,gpu,memory,network \
  bash tests/render-bar.sh "$out/bar.png"
QUADRANT_RENDER_BAR_STYLE=text bash tests/render-bar.sh "$out/bar-text.png"
bash tests/render-bar.sh "$out/bar-trends.png"
QUADRANT_RENDER_VERTICAL=1 QUADRANT_RENDER_PALETTE=light \
  bash tests/render-bar.sh "$out/bar-vertical.png"
QUADRANT_RENDER_VERTICAL=1 QUADRANT_RENDER_PALETTE=light QUADRANT_RENDER_GPU_VENDOR=amd \
  bash tests/render-bar.sh "$out/bar-vertical-amd.png"
QUADRANT_RENDER_ORDER=network,disk,cpu,gpu,memory QUADRANT_RENDER_MISSING_GPU=1 \
  bash tests/render-bar.sh "$out/bar-fallback.png"

bash tests/render-graphs.sh "$out/graph-layouts-dark.png"
QUADRANT_RENDER_PALETTE=light QUADRANT_RENDER_WIDTH=320 QUADRANT_RENDER_LONG=1 \
  QUADRANT_RENDER_PATTERN=gaps QUADRANT_RENDER_HOVER=1 \
  bash tests/render-graphs.sh "$out/graph-layouts-light-hour.png"
QUADRANT_RENDER_PALETTE=mono QUADRANT_RENDER_PATTERN=low \
  bash tests/render-graphs.sh "$out/graph-layouts-mono-low.png"

echo "render-docs: refreshed 17 screenshots in $out"
