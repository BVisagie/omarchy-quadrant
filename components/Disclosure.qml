import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Column {
  id: root
  default property alias content: body.data
  property string title: "Details"
  property bool expanded: false
  readonly property bool detailsDisclosure: true
  spacing: Commons.Style.space(4)

  data: [
    Ui.Button {
      objectName: "disclosureButton"
      width: Math.min(implicitWidth, root.width)
      text: (root.expanded ? "− " : "+ ") + root.title
      fontSize: Commons.Style.font.caption
      tooltipText: root.title + " (D expands or collapses all details)"
      Accessible.name: root.title
      Accessible.role: Accessible.Button
      Accessible.checkable: true
      Accessible.checked: root.expanded
      Accessible.onPressAction: root.expanded = !root.expanded
      onClicked: root.expanded = !root.expanded
    },
    Column {
      id: body
      width: root.width
      visible: root.expanded
      spacing: Commons.Style.space(6)
    }
  ]
}
