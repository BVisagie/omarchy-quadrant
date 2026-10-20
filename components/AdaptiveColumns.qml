import QtQuick
import qs.Commons as Commons

// Keep the same items and focus when the available width changes. The outer
// panel owns scrolling; neither column creates another scroll surface.
Item {
  id: root
  property alias primary: first.data
  property alias secondary: second.data
  property real gap: Commons.Style.space(12)
  property real primaryFraction: 0.5
  readonly property bool wide: width >= Math.max(Commons.Style.space(640), Commons.Style.font.body * 48)
  readonly property real firstWidth: wide ? Math.floor((width - gap) * primaryFraction) : width

  implicitHeight: wide ? Math.max(first.implicitHeight, second.implicitHeight)
                      : first.implicitHeight + (second.implicitHeight > 0 && first.implicitHeight > 0 ? gap : 0) + second.implicitHeight

  Column {
    id: first
    objectName: "primaryColumn"
    width: root.firstWidth
    spacing: Commons.Style.space(12)
  }
  Column {
    id: second
    objectName: "secondaryColumn"
    x: root.wide ? first.width + root.gap : 0
    y: root.wide ? 0 : first.implicitHeight + (implicitHeight > 0 && first.implicitHeight > 0 ? root.gap : 0)
    width: root.wide ? root.width - x : root.width
    spacing: Commons.Style.space(12)
  }
}
