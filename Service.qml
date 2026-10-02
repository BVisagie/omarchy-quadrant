import QtQuick
import "components" as Components

// Service entry point: the shell creates exactly one of these per plugin
// (not one per monitor), injects `shell` and `manifest`, and every bar
// widget copy binds to it through bar.shell.serviceFor(). All sampling,
// history and persistence live in the Store; this file only names it.
Components.Store {
  id: service
  property var manifest: null
}
