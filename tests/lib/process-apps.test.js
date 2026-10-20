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
