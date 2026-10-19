import QtQuick

// The bar's platform-dependent layer-shell panel contract. Bar tests use
// this stand-in to exercise routing without opening a desktop window.
Item {
  property var bar: null
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null
  property bool opened: false
  property bool popoutSwitchClosing: false
  property bool settingsOpen: false
  property bool expandedProcesses: false
  property string currentTab: "cpu"
  property int steps: 0
  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
  function closeForPopoutSwitch() { opened = false }
  function showTab(tab) { currentTab = tab; opened = true }
  function stepTab(direction) { steps += direction }
}
