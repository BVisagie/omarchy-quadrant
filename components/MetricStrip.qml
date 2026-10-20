import QtQuick
import qs.Commons as Commons

// Related headline readings within a card, wrapping at larger font sizes.
Grid {
  id: root
  property var metrics: []
  columns: metrics.length > 1 && width >= Math.max(Commons.Style.space(260), Commons.Style.font.body * 20) ? 2 : 1
  columnSpacing: Commons.Style.space(12)
  rowSpacing: Commons.Style.space(10)

  Repeater {
    model: root.metrics
    delegate: MetricReadout {
      required property var modelData
      objectName: modelData.name || ""
      width: Math.max(0, (root.width - root.columnSpacing * (root.columns - 1)) / root.columns)
      label: modelData.label || ""
      value: modelData.value || "--"
      hint: modelData.hint || ""
      valueColor: modelData.color || Commons.Color.foreground
    }
  }
}
