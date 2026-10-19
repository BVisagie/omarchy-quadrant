"use strict";

// Quadrant Model.js test suite — run with `node --test`.
// Fixtures are captured real tool outputs plus hostile variants.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const Model = require("../../lib/index.mjs");

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "..", "fixtures", name), "utf8");
}

// ---------------------------------------------------------- stream parsing

test("parsePs parses pid, metric, and comm with spaces", () => {
  const rows = Model.parsePs(fixture("ps-cpu.txt"), 10);
  assert.equal(rows.length, 5);
  assert.deepEqual(rows[0], { pid: 10011, value: 33.3, comm: "bash" });
});

test("parsePs keeps hostile comm inert and skips broken rows", () => {
  const rows = Model.parsePs(fixture("ps-hostile.txt"), 10);
  // 7 lines: html-comm, "Other traffic", tabbed name, "bad", orphan "row"
  // (skipped), non-numeric metric (skipped), init
  assert.equal(rows.length, 5);
  assert.equal(rows[0].comm, "<img src=x onerror=alert(1)>");
  assert.equal(rows[1].comm, "Other traffic");
  assert.equal(rows[1].pid, 2759);           // a real process, NOT the catch-all pid 0
  assert.equal(rows[2].comm, "name\twith\ttab");
  assert.equal(rows[3].comm, "bad");
  assert.equal(rows[4].comm, "init");
});

test("parsePs honors the row cap", () => {
  assert.equal(Model.parsePs(fixture("ps-cpu.txt"), 2).length, 2);
  assert.equal(Model.parsePs("", 5).length, 0);
  assert.equal(Model.parsePs(null, 5).length, 0);
});

test("displayName maps wrappers and kernel threads", () => {
  assert.equal(Model.displayName("electron", "brave", "/usr/lib/brave-bin/brave --type=gpu"), "Brave");
  assert.equal(Model.displayName("electron", "codium", "/usr/share/codium/codium"), "Codium");
  assert.equal(Model.displayName("chrome", "chrome", "/opt/google/chrome/chrome --type=renderer"), "Chrome");
  assert.equal(Model.displayName("electron", "electron", "/usr/lib/electron/electron"), "electron");
  assert.equal(Model.displayName("kworker/3:5-events", "", ""), "kworker events");
  assert.equal(Model.displayName("kworker/u88:1-kec", "", ""), "kworker");
  assert.equal(Model.displayName("kworker/0:1-btrfs-endio", "", ""), "kworker btrfs");
  assert.equal(Model.displayName("kswapd0", "", ""), "kswapd");
  assert.equal(Model.displayName("quickshell", "quickshell", ""), "quickshell");
  assert.equal(Model.displayName("", "", ""), "");
});

test("nameAndCollapse sums same-app rows and keeps the lowest pid", () => {
  const rows = Model.parseProcRows(JSON.stringify([
    { pid: 200, value: 11.1, comm: "electron", exe: "brave", cmd: "/usr/lib/brave/brave" },
    { pid: 100, value: 7.4, comm: "electron", exe: "brave", cmd: "/usr/lib/brave/brave --type=renderer" },
    { pid: 50, value: 3.0, comm: "quickshell", exe: "quickshell", cmd: "" }
  ]));
  const collapsed = Model.nameAndCollapse(rows, 5);
  assert.equal(collapsed.length, 2);
  assert.equal(collapsed[0].comm, "Brave");
  assert.equal(Math.round(collapsed[0].value * 10) / 10, 18.5);
  assert.equal(collapsed[0].pid, 100);
  assert.equal(collapsed[1].comm, "quickshell");
});

test("mergeRoster keeps sticky order and updates in place", () => {
  const prev = [
    { pid: 1, comm: "a", valueText: "1%", sortKey: 10 },
    { pid: 2, comm: "b", valueText: "2%", sortKey: 20 }
  ];
  const next = [
    { pid: 2, comm: "b", valueText: "9%", sortKey: 90 },   // now heaviest
    { pid: 3, comm: "c", valueText: "5%", sortKey: 50 },   // newcomer
    { pid: 1, comm: "a", valueText: "1%", sortKey: 5 }
  ];
  const merged = Model.mergeRoster(prev, next, 5);
  // pid 1 keeps its old top slot even though pid 2 is now heavier
  assert.deepEqual(merged.map(r => r.pid), [1, 2, 3]);
  assert.equal(merged[1].valueText, "9%");
});

test("mergeRoster drops vanished rows and caps length", () => {
  const prev = [{ pid: 1, comm: "a", sortKey: 1 }, { pid: 2, comm: "b", sortKey: 2 }];
  const merged = Model.mergeRoster(prev, [{ pid: 2, comm: "b", sortKey: 2 }], 5);
  assert.deepEqual(merged.map(r => r.pid), [2]);
  const capped = Model.mergeRoster([], [
    { pid: 1, sortKey: 1 }, { pid: 2, sortKey: 3 }, { pid: 3, sortKey: 2 }
  ], 2);
  assert.deepEqual(capped.map(r => r.pid), [2, 3]);
});

test("mergeRoster keys the catch-all row on pid 0 only", () => {
  const prev = [{ pid: 0, comm: "", valueText: "old", sortKey: 1 }];
  const next = [
    { pid: 0, comm: "", valueText: "new", sortKey: 1 },
    { pid: 42, comm: "Other traffic", valueText: "x", sortKey: 2 }
  ];
  const merged = Model.mergeRoster(prev, next, 5);
  assert.equal(merged[0].pid, 0);
  assert.equal(merged[0].valueText, "new");
  assert.equal(merged[1].pid, 42);
  assert.equal(merged[1].comm, "Other traffic");
});

test("parseProcessSample validates the merged sampler payload", () => {
  const payload = JSON.stringify({
    dt: 2.01, ncpu: 8, procs: 300, running: 2, threads: 1200, ioVisible: 120, ioHidden: 180,
    cpu: [
      { pid: 10, value: 12.5, core: 100, comm: "python3", exe: "python3.12", cmd: "python3 /opt/app/worker.py", script: "worker.py" },
      { pid: -1, value: 1, comm: "bad" },
      { pid: 11, value: "x", comm: "bad" },
      "junk"
    ],
    mem: [{ pid: 20, value: 204800, kind: "pss", comm: "brave" }, { pid: 21, value: 1024, kind: "weird", comm: "x" }],
    io: [{ pid: 30, value: 300, read: 100, write: 200, comm: "rsync" }]
  });
  const s = Model.parseProcessSample(payload);
  assert.equal(s.ncpu, 8);
  assert.equal(s.threads, 1200);
  assert.equal(s.ioHidden, 180);
  assert.equal(s.cpu.length, 1);
  assert.equal(s.cpu[0].core, 100);
  assert.equal(s.cpu[0].script, "worker.py");
  assert.equal(s.mem[0].kind, "pss");
  assert.equal(s.mem[1].kind, undefined);
  assert.deepEqual([s.io[0].read, s.io[0].write], [100, 200]);
  assert.equal(Model.parseProcessSample("nope"), null);
  assert.equal(Model.parseProcessSample(null), null);
  // Interpreter rows are named after their script and collapse per script.
  const rows = Model.nameAndCollapse([
    { pid: 10, value: 5, comm: "python3", exe: "python3.12", cmd: "", script: "worker.py" },
    { pid: 12, value: 3, comm: "python3", exe: "python3.12", cmd: "", script: "worker.py" },
    { pid: 13, value: 2, comm: "python3", exe: "python3.12", cmd: "", script: "other.py" },
    { pid: 14, value: 1, comm: "node", exe: "node", cmd: "", script: "server.js" },
    { pid: 15, value: 9, comm: "brave", exe: "brave", cmd: "", script: "" }
  ], 10);
  assert.deepEqual(rows.map((r) => [r.comm, r.value, r.pid]), [["Brave", 9, 15], ["worker.py", 8, 10], ["other.py", 2, 13], ["server.js", 1, 14]]);
  assert.equal(Model.displayName("python3", "python3.12", "", "../evil"), "python3");
  assert.equal(Model.displayName("brave", "brave", "", "x.py"), "Brave");
  // io rows sum read and write per app.
  const io = Model.nameAndCollapse([
    { pid: 1, value: 30, read: 10, write: 20, comm: "rsync" },
    { pid: 2, value: 5, read: 5, write: 0, comm: "rsync" }
  ], 5);
  assert.deepEqual([io[0].read, io[0].write, io[0].value], [15, 20, 35]);
});

test("expanded grouping covers members beyond 32 before searching and capping", () => {
  const rows = Array.from({ length: 400 }, (_, i) => ({ pid: i + 1, start: 10, comm: i < 80 ? "workers" : `job-${i}`,
    memory: 10, kind: "rss", cpu: 1, core: 8, read: 0, write: 0, ioVisible: true }));
  const sample = Model.parseProcessSample({ mode: "expanded", rows, procs: 400 });
  const groups = Model.processGroups(sample, "mem", 10000);
  assert.equal(groups.length, 321);
  assert.equal(groups[0].n, 80);
  assert.equal(groups[0].value, 800);
  assert.equal(groups[0].pct, 8);
  assert.equal(groups[0].members.length, 80);
  const capped = Model.filterProcessGroups(groups, "", {}, 256, "value");
  assert.equal(capped.rows.length, 256);
  assert.equal(capped.matches, 321);
  assert.equal(capped.limited, true);
  const deepMatch = Model.filterProcessGroups(groups, "job-399", {}, 256, "value");
  assert.equal(deepMatch.matches, 1);
  assert.equal(deepMatch.rows[0].pid, 400);
  const pidMatch = Model.filterProcessGroups(groups, "79", {}, 256, "value");
  const workers = pidMatch.rows.find(r => r.comm === "workers");
  assert.deepEqual(workers.matchedPids, [79]);
  assert.equal(workers.value, 800);
  assert.equal(workers.pid, 1); // representative is explicitly distinct
  assert.equal(Model.filterProcessGroups(groups, "Worker Application", { nworkers: "Worker Application" }, 256).matches, 1);
});

test("mixed memory and partial or restricted metrics keep their meaning", () => {
  const mixed = Model.nameAndCollapse([
    { pid: 1, start: 1, comm: "app", kind: "pss", value: 100 },
    { pid: 2, start: 2, comm: "app", kind: "rss", value: 200 },
    { pid: 3, start: 3, comm: "app", kind: "pss", value: 50 }
  ], 10)[0];
  assert.equal(mixed.kind, "mixed");
  assert.equal(mixed.n, 3);
  assert.equal(mixed.value, 350);
  const sample = Model.parseProcessSample({ mode: "expanded", rows: [
    { pid: 1, start: 1, comm: "app", cpu: null, read: null, write: null, memory: 100, kind: "rss", ioVisible: false },
    { pid: 2, start: 2, comm: "app", cpu: 2, read: 0, write: 0, memory: 100, kind: "rss", ioVisible: true },
    { pid: 3, start: 3, comm: "hidden", cpu: null, read: null, write: null, memory: null, ioVisible: false }
  ] });
  const cpu = Model.processGroups(sample, "cpu");
  assert.equal(cpu[0].value, 2);
  assert.equal(cpu[0].known, 1);
  assert.equal(cpu[0].n, 2);
  assert.equal(cpu[1].value, null);
  const io = Model.processGroups(sample, "io");
  assert.equal(io[0].value, 0); // known idle member, partial group
  assert.equal(io[0].hidden, 1);
  assert.equal(io[1].value, null); // restricted, not idle
});

test("group identity requires a surviving PID and start time", () => {
  const group = (members) => Model.nameAndCollapse(members.map(([pid, start]) => ({ pid, start, comm: "workers", value: 1 })), 10)[0];
  const old = group([[1, 10], [2, 20]]);
  const surviving = group([[2, 20], [3, 30]]);
  const reused = group([[1, 99], [2, 99]]);
  assert.equal(Model.sameProcessRow(old, surviving), true);
  assert.equal(Model.sameProcessRow(old, reused), false);
  const other = { pid: 7, start: 7, comm: "other", sortKey: 10 };
  assert.deepEqual(Model.mergeRoster([old, other], [reused, other], 5).map(r => r.comm), ["other", "workers"]);
  assert.equal(Model.sameProcessRow({ pid: 1, start: 10 }, { pid: 1, start: 11 }), false);
});

test("hostile group names stay inert and missing fields stay unavailable", () => {
  const sample = Model.parseProcessSample({ mode: "expanded", rows: [
    { pid: 10, start: 1, comm: "__proto__", cpu: null, memory: null },
    { pid: 11, start: 1, comm: "<img>\u0000", cpu: -1, memory: 20 },
    { pid: 12, comm: "missing-identity", cpu: 1 }
  ] });
  assert.equal(sample.unreadable, 1);
  const groups = Model.processGroups(sample, "cpu");
  assert.deepEqual(groups.map(r => r.value), [null, null]);
  assert.equal(groups[0].comm, "__proto__");
  assert.equal(groups[1].comm, "<img>");
  assert.equal(Model.parseProcessSample({ mode: "expanded" }), null);
});
