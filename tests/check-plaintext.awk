# check-plaintext.awk — Quadrant's injection guard.
#
# Every Text block in the plugin's QML must declare
# `textFormat: Text.PlainText`: Qt's default AutoText can interpret
# HTML-like strings (including inline images), and several labels render
# attacker-controlled process names. Run under both mawk and gawk in CI.
#
# Usage: awk -f tests/check-plaintext.awk *.qml tabs/*.qml components/*.qml

BEGIN { bad = 0 }

/^[[:space:]]*Text[[:space:]]*\{/ {
  inblock = 1
  startline = NR
  depth = 0
  found = 0
}

inblock {
  line = $0
  if (line ~ /textFormat:[[:space:]]*Text\.PlainText/) found = 1
  if (line ~ /textFormat:[[:space:]]*Text\.(RichText|AutoText|MarkdownText)/) {
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
