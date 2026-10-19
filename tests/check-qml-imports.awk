# Shell singletons must use their Commons namespace: QtQuick can introduce
# types with the same names (Color on Qt 6.12). Check plugin and harness QML.
# Usage: awk -f tests/check-qml-imports.awk <qml files...>

{
  line = $0
  sub(/\/\/.*$/, "", line)
  if (line ~ /(^|[^[:alnum:]_.])(Color|Style|Util|Border)[[:space:]]*\./) {
    printf "%s:%d: shell singleton needs the Commons namespace\n", FILENAME, FNR
    bad = 1
  }
}

END { if (bad) exit 1 }
