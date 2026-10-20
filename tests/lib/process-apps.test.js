import test from "node:test"
import assert from "node:assert/strict"
import { processAppIndex, processDesktopEntry, nameAndCollapse, processGroups, parseProcessSample,
  filterProcessGroups, sameProcessRow } from "../../lib/index.mjs"

const t3 = { id: "t3code", name: "T3 Code Nightly", startupClass: "t3code",
  icon: "t3code-nightly", command: ["t3code-nightly", "%U"] }
const brave = { id: "brave-origin", name: "Brave Origin", startupClass: "brave-origin",
  icon: "brave-origin", command: ["brave-origin", "%U"] }

test("T3 identities and the installed Brave Origin wrapper resolve after grouping", () => {
  const hidden = { id: "com.t3tools.T3Code", name: "T3 Code (Nightly)", noDisplay: true,
    command: ["/opt/t3code-nightly-bin/t3code", "%U"], icon: "/tmp/t3.png" }
  for (const entries of [[hidden, t3, brave], [brave, t3, hidden]]) {
    const index = processAppIndex(entries)
    const rows = nameAndCollapse([
      { pid: 1, start: 1, comm: "t3code", exe: "t3code", value: 1 },
      { pid: 2, start: 2, comm: "brave", exe: "brave", value: 2 }
    ], 10)
    assert.equal(rows[0].comm, "Brave")
    assert.equal(processDesktopEntry(index, rows[0]), brave)
    assert.equal(processDesktopEntry(index, rows[1]), t3)
    assert.equal(processDesktopEntry(index, { comm: "brave" }), brave)
    assert.equal(processDesktopEntry(index, { comm: "kworker events" }), null)
    assert.equal(filterProcessGroups(rows, "Origin", row => processDesktopEntry(index, row)?.name, 256).matches, 1)
  }
})

test("parsed launcher executable wins over a friendly name and preserves executable case", () => {
  const first = { id: "first", name: "Different label", command: ["/opt/My App/RealApp", "%U"] }
  const second = { id: "second", name: "Other", command: ["/opt/other/realapp", "%U"] }
  const index = processAppIndex([first, second])
  assert.equal(processDesktopEntry(index, { comm: "Other", exe: "RealApp" }), first)
  assert.equal(processDesktopEntry(index, { comm: "Different label", exe: "realapp" }), second)
})

test("ambiguous families and conflicting group identities never depend on inventory/member order", () => {
  const beta = { id: "brave-browser", name: "Brave Beta", command: ["brave-browser"] }
  const a = { id: "one", name: "One", command: ["app-one"] }
  const b = { id: "two", name: "Two", command: ["app-two"] }
  for (const entries of [[brave, beta, a, b], [b, a, beta, brave]]) {
    const index = processAppIndex(entries)
    assert.equal(processDesktopEntry(index, { comm: "Brave", appKeys: ["brave"] }), null)
    for (const keys of [["app-one", "app-two"], ["app-two", "app-one"]])
      assert.equal(processDesktopEntry(index, { comm: "workers", appKeys: keys }), null)
    assert.equal(processDesktopEntry(index, { comm: "brave-origin" }), brave)
  }
})

test("shared launcher and icon keys do not hide an application's desktop identity", () => {
  const fixtures = [
    { comm: "foot", exe: "foot", app: { id: "foot", name: "Foot", icon: "foot", command: ["foot"] },
      shortcut: { id: "foot-server", name: "Foot Server", icon: "foot", startupClass: "foot", command: ["foot", "--server"] } },
    { comm: "steam", exe: "steam", app: { id: "steam", name: "Steam", icon: "steam", command: ["steam", "%U"] },
      shortcut: { id: "steam-game-570", name: "Dota 2", icon: "steam", command: ["steam", "steam://rungameid/570"] } },
    { comm: "chromium", exe: "chromium", app: { id: "chromium", name: "Chromium", icon: "chromium", command: ["chromium", "%U"] },
      shortcut: { id: "chromium-pwa", name: "Web App", icon: "chromium", command: ["/usr/bin/chromium", "--app-id=example"] } },
    { comm: "lutris", exe: "python3.13", app: { id: "lutris", name: "Lutris", icon: "lutris", command: ["lutris"] },
      shortcut: { id: "lutris-game", name: "Game", icon: "lutris", command: ["env", "LUTRIS_SKIP_INIT=1", "lutris", "lutris:rungame/test"] } }
  ]
  for (const fixture of fixtures) {
    const row = nameAndCollapse([{ pid: 1, start: 1, comm: fixture.comm, exe: fixture.exe, value: 1 }], 1)[0]
    for (const entries of [[fixture.app, fixture.shortcut], [fixture.shortcut, fixture.app]]) {
      const index = processAppIndex(entries)
      assert.equal(processDesktopEntry(index, row), fixture.app, fixture.comm)
      assert.equal(processDesktopEntry(index, { comm: fixture.comm, appKeys: [] }), fixture.app, "friendly identity: " + fixture.comm)
    }
  }
})

test("desktop IDs and startup classes outrank shared display and icon names", () => {
  const app = { id: "actual-app", name: "Shared name", startupClass: "app-window", icon: "shared-icon" }
  const other = { id: "other", name: "Shared name", icon: "actual-app", command: ["different-executable"] }
  for (const entries of [[app, other], [other, app]]) {
    const index = processAppIndex(entries)
    assert.equal(processDesktopEntry(index, { comm: "actual-app" }), app)
    assert.equal(processDesktopEntry(index, { comm: "app-window" }), app)
    assert.equal(processDesktopEntry(index, { comm: "Shared name" }), null)
    assert.equal(processDesktopEntry(index, { comm: "worker", appKeys: ["actual-app", "other"] }), null)
  }
})

test("conflicting retained identities remain unresolved across matching tiers", () => {
  const one = { id: "one", name: "First", command: ["sh", "-c", "one"] }
  const two = { id: "two", name: "Second", startupClass: "second", command: ["sh", "-c", "second"] }
  for (const entries of [[one, two], [two, one]]) {
    const index = processAppIndex(entries)
    for (const appKeys of [["one", "second"], ["second", "one"]])
      assert.equal(processDesktopEntry(index, { comm: "worker", appKeys }), null)
  }
})

test("generated friendly labels do not override retained raw identities", () => {
  const origin = { id: "brave-origin", name: "Brave Origin", command: ["origin-wrapper"] }
  const other = { id: "brave", name: "Other Brave", command: ["brave-browser"] }
  const row = nameAndCollapse([{ pid: 1, comm: "chrome", exe: "brave-origin", value: 1 }], 1)[0]
  assert.equal(row.comm, "Brave")
  assert.deepEqual(row.appKeys, ["brave-origin"])
  for (const entries of [[origin, other], [other, origin]]) {
    const index = processAppIndex(entries)
    assert.equal(processDesktopEntry(index, row), origin)
    assert.equal(processDesktopEntry(index, { comm: "Brave", appKeys: [] }), other)
  }
})

test("hidden launchers cannot claim visible apps or executable-only processes", () => {
  const quickshell = { id: "org.quickshell", name: "Quickshell", icon: "org.quickshell", noDisplay: true }
  const xwayland = { id: "org.freedesktop.Xwayland", name: "Xwayland", command: ["Xwayland", "-decorate"], noDisplay: true }
  const handler = { id: "claude-code-url-handler", name: "Claude Code URL Handler", command: ["claude", "--handle-uri", "%u"], noDisplay: true }
  const hiddenT3 = { id: "com.t3tools.T3Code", name: "T3 Code (Nightly)", startupClass: "t3code", icon: "hidden-t3", command: ["t3code"], noDisplay: true }
  const entries = [quickshell, xwayland, handler, hiddenT3, t3]
  for (const values of [entries, entries.slice().reverse()]) {
    const index = processAppIndex(values)
    assert.equal(processDesktopEntry(index, { comm: "quickshell" }), null)
    assert.equal(processDesktopEntry(index, { comm: "Xwayland" }), null)
    assert.equal(processDesktopEntry(index, { comm: "t3code" }), t3)
    assert.equal(processDesktopEntry(index, { comm: "claude", exe: "claude" }), null)
    assert.equal(processDesktopEntry(index, { comm: "hidden-t3" }), null, "hidden icon names do not identify a process")
  }
  assert.equal(processDesktopEntry(processAppIndex([hiddenT3]), { comm: "t3code", exe: "t3code" }), null)
  const visible = { id: "visible-shell", name: "Quickshell", icon: "visible" }
  assert.equal(processDesktopEntry(processAppIndex([quickshell, visible]), { comm: "quickshell" }), visible)
})

test("generic runtimes and arbitrary command arguments are not application identities", () => {
  const entries = [
    { id: "idle", name: "IDLE", command: ["python3", "-m", "idlelib"] },
    { id: "flat", name: "Flat App", command: ["flatpak", "run", "org.example.flat"] },
    { id: "wrapper", name: "Wrapper", command: ["sh", "-c", "brave-origin"] },
    { id: "electron-app", name: "Electron App", command: ["electron", "/opt/application"] },
    { id: "firefox", name: "Firefox", command: ["firefox", "%u"] },
    { id: "environment", name: "Env App", command: ["env", "APP_MODE=1", "/opt/My App/runner", "%U"] }
  ]
  const index = processAppIndex(entries)
  for (const comm of ["python3", "python3.13", "flatpak", "sh", "electron", "org.example.flat", "application"])
    assert.equal(processDesktopEntry(index, { comm, cmd: "https://example.com/brave-origin" }), null)
  assert.equal(processDesktopEntry(index, { comm: "runner" }), entries[5])
  assert.equal(processDesktopEntry(index, { comm: "firefox" }), entries[4])
  const wrapped = nameAndCollapse([{ pid: 1, comm: "chrome", exe: "chrome", cmd: "/opt/brave/brave", value: 1 }], 1)[0]
  assert.equal(processDesktopEntry(processAppIndex([brave, { id: "chrome", name: "Chrome", command: ["chrome"] }]), wrapped), brave)
})

test("compact and expanded groups retain bounded executable evidence without changing totals or identity", () => {
  const rows = [
    { pid: 1, start: 1, comm: "worker", exe: "actual-app", cpu: 3, memory: 20, read: 1, write: 2, value: 3 },
    { pid: 2, start: 2, comm: "worker", exe: "actual-app", cpu: 4, memory: 30, read: 2, write: 3, value: 4 }
  ]
  const compact = nameAndCollapse(rows, 10)[0]
  assert.deepEqual(compact.appKeys, ["actual-app", "worker"])
  assert.equal(compact.value, 7)
  assert.deepEqual(compact.members, [{ pid: 1, start: 1 }, { pid: 2, start: 2 }])
  const sample = parseProcessSample({ mode: "expanded", rows })
  for (const metric of ["cpu", "mem", "io"]) {
    const expanded = processGroups(sample, metric)[0]
    assert.deepEqual(expanded.appKeys, compact.appKeys)
    assert.equal(sameProcessRow(compact, expanded), true)
  }
  const crowded = nameAndCollapse(Array.from({ length: 20 }, (_, i) => ({ pid: i + 1, comm: "worker", exe: "app" + i, value: 1 })), 1)[0]
  assert.equal(crowded.appKeys.length, 8)
  assert.equal(crowded.appKeysTruncated, true)
  assert.equal(crowded.value, 20)
  assert.equal(processDesktopEntry(processAppIndex([{ id: "worker", name: "Worker" }]), crowded), null)
})
