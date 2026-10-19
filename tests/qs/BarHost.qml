import QtQuick
import qs.Commons as Commons

// Offscreen host API. Input is routed through the same registered targets
// as the shell; commands are recorded instead of launching desktop apps.
QtObject {
  id: root
  property var service: null
  property var widgets: []
  property bool vertical: false
  property int barSize: 26
  property bool foregroundAnimationEnabled: false
  property string position: "top"
  property string fontFamily: Commons.Style.font.family
  property color barForeground: Commons.Color.foreground
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color urgent: Commons.Color.urgent
  property var targets: []
  property string tooltip: ""
  property var commands: []
  property QtObject shell: QtObject {
    function serviceFor(name) { return name === "dev.bvisagie.quadrant" ? root.service : null }
  }
  function registerClickTarget(item) { targets = targets.concat([item]) }
  function unregisterClickTarget(item) { targets = targets.filter(function (target) { return target !== item }) }
  function showTooltip(item, text) { tooltip = text }
  function hideTooltip(item) { }
  function moduleWidgets(name) { return widgets }
  function run(command) { commands = commands.concat([command]) }
}
