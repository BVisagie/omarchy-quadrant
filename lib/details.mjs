// Use the same scope for the pointer affordance and D shortcut. Hidden
// devices and inactive tabs keep their disclosure state.
export function visibleDetails(item) {
  var details = []
  function collect(parent) {
    if (!parent || !parent.visible) return
    if (parent.detailsDisclosure === true) details.push(parent)
    for (var child of parent.children) collect(child)
  }
  collect(item)
  return details
}

export function toggleDetails(item) {
  var details = visibleDetails(item)
  var expand = details.some(function (detail) { return !detail.expanded })
  for (var detail of details) detail.expanded = expand
}
