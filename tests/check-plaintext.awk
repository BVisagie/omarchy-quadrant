# check-plaintext.awk — Quadrant's injection guard.
#
# Every Text block in the plugin's QML must declare
# `textFormat: Text.PlainText`: Qt's default AutoText can interpret
# HTML-like strings (including inline images), and several labels render
# attacker-controlled process names. Run under both mawk and gawk in CI.
#
# WidgetButton.tooltipText is rendered by the shell's own tooltip Text,
# which is already PlainText. Quadrant's tooltip strings are rates and
# percentages — never process comm — so they are not in scope for this
# check. The matcher covers `Text {` on one line and a bare `Text` whose
# brace opens on the following line.
#
# Usage: awk -f tests/check-plaintext.awk *.qml tabs/*.qml components/*.qml

BEGIN { bad = 0; pending = 0 }

function open_block(line_no) {
  inblock = 1
  startline = line_no
  depth = 0
  found = 0
}

# `Text {` on one line.
!inblock && /^[[:space:]]*Text[[:space:]]*\{/ {
  open_block(NR)
  pending = 0
}

# A bare `Text` line: the brace must come on the next non-blank line.
!inblock && /^[[:space:]]*Text[[:space:]]*$/ {
  pending = 1
  pendingline = NR
  next
}

pending && !inblock {
  if ($0 ~ /^[[:space:]]*$/) next
  if ($0 ~ /^[[:space:]]*\{/) {
    open_block(pendingline)
  }
  pending = 0
}

inblock {
  line = $0
  if (line ~ /textFormat:[[:space:]]*Text\.PlainText/) found = 1
  if (line ~ /textFormat:[[:space:]]*Text\.(RichText|AutoText|MarkdownText|StyledText)/) {
    printf "%s:%d: forbidden rich text format\n", FILENAME, NR
    bad++
  }
  depth += gsub(/\{/, "{", line)
  depth -= gsub(/\}/, "}", line)
  if (depth <= 0) {
    if (!found) {
      printf "%s:%d: Text block missing textFormat: Text.PlainText\n", FILENAME, startline
      bad++
    }
    inblock = 0
  }
}

END {
  if (bad > 0) {
    printf "check-plaintext: %d violation(s)\n", bad > "/dev/stderr"
    exit 1
  }
}
