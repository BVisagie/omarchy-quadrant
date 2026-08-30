"use strict";

// Quadrant Model.js test suite — run with `node --test`.
// Fixtures are captured real tool outputs plus hostile variants.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const Model = require("../Model.js");
const Theme = require("../Theme.js");

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8");
}

// ---------------------------------------------------------- stream parsing

test("parseStreamLine parses a full sample", () => {
  const s = Model.parseStreamLine(fixture("stream-basic.json"));
  assert.ok(s);
  assert.equal(s.ts, 1788067655.087906);
  assert.deepEqual(s.cpu, { user: 7132, nice: 0, system: 4217, idle: 301512, iowait: 295, irq: 0, softirq: 1203, steal: 8 });
  assert.equal(s.mem.tot, 16398384);
  assert.equal(s.psi.cs300, 0.04);
  assert.deepEqual(s.net, [
    { n: "eth0", rx: 2268161762, tx: 7069677 },
    { n: "docker0", rx: 0, tx: 0 }
  ]);
  assert.deepEqual(s.r4, [{ n: "eth0", m: 0 }]);
  assert.equal(s.gpu, null);
  assert.equal(s.tempC, null);
  assert.equal(s.cores, 4);
  assert.equal(s.uptimeS, 784.2);
});

test("parseStreamLine accepts missing PSI and Intel gpu shape", () => {
  const s = Model.parseStreamLine(fixture("stream-no-psi.json"));
  assert.ok(s);
  assert.equal(s.psi, null);
  assert.equal(s.gpu.kind, "intel");
  assert.equal(s.gpu.busy, null);
  assert.equal(s.gpu.freqCurMhz, 400);
  assert.equal(s.gpu.freqMaxMhz, 1300);
  assert.deepEqual(s.r6, [{ n: "wlan0", m: 600 }]);
});

test("parseStreamLine keeps unread PSI half as null, not zero", () => {
  const s = Model.parseStreamLine(fixture("stream-partial-psi.json"));
  assert.ok(s);
  assert.equal(s.psi.cs10, 1.5);
  assert.equal(s.psi.ms10, null);
  assert.equal(s.psi.ms60, null);
  assert.equal(s.gpu.kind, "amd");
  assert.equal(s.gpu.memBusy, 22);
  assert.deepEqual(s.gpu.engines, [
    { id: "comp_1_0_0", busy: 5 },
    { id: "gfx", busy: 40 }
  ]);
});

test("parseStreamLine rejects garbage", () => {
  assert.equal(Model.parseStreamLine(""), null);
  assert.equal(Model.parseStreamLine("not json"), null);
  assert.equal(Model.parseStreamLine('{"v":2,"ts":1}'), null);
  assert.equal(Model.parseStreamLine('{"v":1,"ts":-3,"cpu":[1,2,3,4,5,6,7,8],"mem":{"tot":1,"fre":1,"avl":1,"buf":1,"cac":1,"srec":1,"slab":1,"swtot":1,"swfre":1}}'), null);
  assert.equal(Model.parseStreamLine('{"v":1,"ts":5,"cpu":[1,2,3],"mem":{}}'), null);
  assert.equal(Model.parseStreamLine('{"v":1,"ts":5,"cpu":["x",0,0,0,0,0,0,0],"mem":{"tot":1,"fre":1,"avl":1,"buf":1,"cac":1,"srec":1,"slab":1,"swtot":1,"swfre":1}}'), null);
});

// ---------------------------------------------------------------- cpuDelta

test("cpuDelta computes bucketed percentages", () => {
  const prev = { user: 100, nice: 0, system: 50, idle: 800, iowait: 30, irq: 10, softirq: 10, steal: 0 };
  const curr = { user: 160, nice: 10, system: 70, idle: 1500, iowait: 40, irq: 15, softirq: 15, steal: 10 };
  const d = Model.cpuDelta(prev, curr);
  // deltas: user 70 (incl nice), system 30 (incl irq+softirq), iowait 10, steal 10, idle 700 → total 820
  assert.ok(d);
  assert.equal(Math.round(d.user * 100 / 100), Math.round(100 * 70 / 820));
  assert.equal(Math.round(d.system), Math.round(100 * 30 / 820));
  assert.equal(Math.round(d.iowait), Math.round(100 * 10 / 820));
  assert.equal(Math.round(d.steal), Math.round(100 * 10 / 820));
  assert.equal(Math.round(d.busy), Math.round(100 * 100 / 820));
});

test("cpuDelta returns null when counters do not advance", () => {
  const c = { user: 1, nice: 0, system: 1, idle: 1, iowait: 0, irq: 0, softirq: 0, steal: 0 };
  assert.equal(Model.cpuDelta(c, c), null);
  assert.equal(Model.cpuDelta(null, c), null);
});

test("cpuDelta clamps counter resets instead of going negative", () => {
  // user/system reset while idle keeps advancing: reset buckets clamp to 0.
  const prev = { user: 1000, nice: 0, system: 500, idle: 100, iowait: 0, irq: 0, softirq: 0, steal: 0 };
  const curr = { user: 10, nice: 0, system: 5, idle: 150, iowait: 0, irq: 0, softirq: 0, steal: 0 };
  const d = Model.cpuDelta(prev, curr);
  assert.ok(d);
  assert.equal(d.user, 0);
  assert.equal(d.system, 0);
  assert.equal(d.idle, 100);
  // everything reset at once: no usable delta at all
  const gone = Model.cpuDelta(curr, { user: 1, nice: 0, system: 1, idle: 1, iowait: 0, irq: 0, softirq: 0, steal: 0 });
  assert.equal(gone, null);
});

// ---------------------------------------------------------------- netRates

test("netRates computes per-interface byte rates", () => {
  const prev = [{ n: "eth0", rx: 1000, tx: 500 }];
  const curr = [{ n: "eth0", rx: 3000, tx: 900 }, { n: "wlan0", rx: 50, tx: 50 }];
  const rates = Model.netRates(prev, curr, 2);
  assert.equal(rates.length, 2);
  assert.equal(rates[0].name, "eth0");
  assert.equal(rates[0].rxBps, 1000);
  assert.equal(rates[0].txBps, 200);
  // new interface reports 0, not a spike from its lifetime counters
  assert.equal(rates[1].rxBps, 0);
});

test("netRates treats counter resets as zero", () => {
  const rates = Model.netRates([{ n: "eth0", rx: 5000, tx: 10 }], [{ n: "eth0", rx: 100, tx: 20 }], 1);
  assert.equal(rates[0].rxBps, 0);
  assert.equal(rates[0].txBps, 10);
});

// ---------------------------------------------------------------- swapRates

test("swapRates converts pages to KiB/s", () => {
  const r = Model.swapRates({ swpin: 100, swpout: 200 }, { swpin: 150, swpout: 200 }, 2);
  assert.equal(r.inKBs, 100);   // 50 pages * 4 KiB / 2 s
  assert.equal(r.outKBs, 0);
});

// ------------------------------------------------------------------- memory

test("memComposition buckets RAM with buffers in cache", () => {
  const mem = { tot: 1000, fre: 200, avl: 600, buf: 50, cac: 300, srec: 50, slab: 100, swtot: 0, swfre: 0 };
  const c = Model.memComposition(mem);
  assert.equal(c.cacheK, 400);          // buffers + cached + sreclaimable
  assert.equal(c.kernelK, 50);          // slab - sreclaimable
  assert.equal(c.freeK, 200);
  assert.equal(c.appsK, 350);           // 1000 - 200 - 400 - 50
  assert.equal(c.usedPct, 40);          // (tot - avl) / tot
});

test("memComposition never yields a negative applications slice", () => {
  const mem = { tot: 100, fre: 10, avl: 90, buf: 60, cac: 60, srec: 10, slab: 10, swtot: 0, swfre: 0 };
  const c = Model.memComposition(mem);
  assert.equal(c.appsK, 0);
});

test("swapUsage handles swapless machines", () => {
  assert.deepEqual(Model.swapUsage({ swtot: 0, swfre: 0 }), { totalK: 0, usedK: 0, pct: 0 });
  const s = Model.swapUsage({ swtot: 1000, swfre: 250 });
  assert.equal(s.usedK, 750);
  assert.equal(s.pct, 75);
});

// ----------------------------------------------------------- pickInterface

test("pickInterface prefers the lowest metric across v4 and v6", () => {
  const net = [{ n: "eth0" }, { n: "wlan0" }];
  assert.equal(Model.pickInterface([{ n: "eth0", m: 100 }], [{ n: "wlan0", m: 600 }], net), "eth0");
  assert.equal(Model.pickInterface([{ n: "eth0", m: 700 }], [{ n: "wlan0", m: 600 }], net), "wlan0");
  // tie → IPv4 wins
  assert.equal(Model.pickInterface([{ n: "eth0", m: 600 }], [{ n: "wlan0", m: 600 }], net), "eth0");
});

test("pickInterface skips loopback and falls back sanely", () => {
  assert.equal(Model.pickInterface([{ n: "lo", m: 0 }], [], [{ n: "lo" }, { n: "eth0" }]), "eth0");
  assert.equal(Model.pickInterface([], [], [{ n: "lo" }, { n: "eth0" }]), "eth0");
  assert.equal(Model.pickInterface([], [], [{ n: "lo" }]), "");
  assert.equal(Model.pickInterface([], [], []), "");
  // route via an interface with no counters is not picked
  assert.equal(Model.pickInterface([{ n: "tun0", m: 0 }], [], [{ n: "eth0" }]), "eth0");
});

// -------------------------------------------------------------------- ps

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

// -------------------------------------------------------------------- ss

test("parseSs parses real captured output", () => {
  const socks = Model.parseSs(fixture("ss-basic.txt"));
  assert.ok(socks.length >= 5);
  const withPid = socks.filter(s => s.pid > 0);
  assert.ok(withPid.length >= 3);
  const node = withPid.find(s => s.pid === 2497);
  assert.ok(node);
  assert.equal(node.comm, "node");
  assert.equal(node.rx, 68697);              // bytes_received
  assert.equal(node.tx, 3415954);            // bytes_sent preferred over bytes_acked
  assert.equal(node.localAddr, "172.30.0.2");
  // IPv4-mapped IPv6 local addresses normalize to the v4 form
  const mapped = socks.find(s => s.pid === 1501 && s.rx === 29961);
  assert.ok(mapped);
  assert.equal(mapped.localAddr, "172.30.0.2");
  // sockets without a users:(...) group stay unattributed (pid 0)
  assert.ok(socks.some(s => s.pid === 0));
});

test("parseSs defuses pid forgery and keeps hostile comm inert", () => {
  const socks = Model.parseSs(fixture("ss-hostile.txt"));
  assert.equal(socks.length, 4);
  assert.equal(socks[0].pid, 4242);
  assert.equal(socks[0].comm, "<img src=x>");
  // a process named "Other traffic" is a normal row with its real pid
  assert.equal(socks[1].pid, 1337);
  assert.equal(socks[1].comm, "Other traffic");
  // forged inner pid is inert: the kernel's trailing pid wins, the forgery
  // stays inside the displayed comm
  assert.equal(socks[2].pid, 666);
  assert.ok(socks[2].comm.indexOf("pid=1") !== -1);
  // no users group → pid 0
  assert.equal(socks[3].pid, 0);
  assert.equal(socks[3].rx, 400);
});

test("parseSs survives truncated output", () => {
  const socks = Model.parseSs(fixture("ss-truncated.txt"));
  assert.equal(socks.length, 1);   // the cut-off second record has no counters
  assert.equal(socks[0].pid, 2497);
  assert.equal(Model.parseSs("").length, 0);
  assert.equal(Model.parseSs("garbage\n\n").length, 0);
});

// ------------------------------------------------------- computeNetAppRows

test("computeNetAppRows attributes rates and computes the Other remainder", () => {
  const prev = [
    { pid: 100, comm: "a", rx: 1000, tx: 500 },
    { pid: 200, comm: "b", rx: 0, tx: 0 }
  ];
  const curr = [
    { pid: 100, comm: "a", rx: 3000, tx: 500 },
    { pid: 200, comm: "b", rx: 400, tx: 100 }
  ];
  const r = Model.computeNetAppRows(prev, curr, { rx: 10000, tx: 1000 }, { rx: 16000, tx: 2000 }, 2);
  // pid 100: (3000-1000)/2 = 1000 B/s rx; pid 200: 200 B/s rx, 50 B/s tx
  assert.equal(r.rows.length, 2);
  assert.equal(r.rows[0].pid, 100);
  assert.equal(r.rows[0].rxBps, 1000);
  assert.equal(r.rows[1].rxBps, 200);
  // interface moved 3000 B/s rx; 1200 attributed → 1800 other
  assert.equal(r.ifRxBps, 3000);
  assert.equal(r.other.rxBps, 1800);
  assert.equal(r.other.txBps, 500 - 50);
});

test("computeNetAppRows first sample reports zero rates", () => {
  const r = Model.computeNetAppRows(null, [{ pid: 1, comm: "x", rx: 500, tx: 0 }], null, { rx: 500, tx: 0 }, 1);
  assert.equal(r.rows.length, 0);
  assert.equal(r.other.rxBps, 0);
});

test("computeNetAppRows scopes sockets to the watched interface", () => {
  const prev = [
    { pid: 1, comm: "a", rx: 100, tx: 0, localAddr: "10.0.0.2" },
    { pid: 2, comm: "b", rx: 100, tx: 0, localAddr: "172.16.0.2" }
  ];
  const curr = [
    { pid: 1, comm: "a", rx: 1100, tx: 0, localAddr: "10.0.0.2" },
    { pid: 2, comm: "b", rx: 5100, tx: 0, localAddr: "172.16.0.2" }
  ];
  const r = Model.computeNetAppRows(prev, curr, { rx: 0, tx: 0 }, { rx: 2000, tx: 0 }, 1, ["10.0.0.2"]);
  assert.equal(r.rows.length, 1);
  assert.equal(r.rows[0].pid, 1);
  assert.equal(r.rows[0].rxBps, 1000);
  // iface moved 2000; 1000 attributed to pid 1; docker pid 2 is Other
  assert.equal(r.other.rxBps, 1000);
});

test("computeNetAppRows matches IPv4-mapped ss addresses to iface IPv4", () => {
  const prev = [{ pid: 9, comm: "n", rx: 0, tx: 0, localAddr: "10.0.0.2" }];
  const curr = [{ pid: 9, comm: "n", rx: 500, tx: 0, localAddr: "10.0.0.2" }];
  const r = Model.computeNetAppRows(prev, curr, { rx: 0, tx: 0 }, { rx: 500, tx: 0 }, 1, ["::ffff:10.0.0.2"]);
  assert.equal(r.rows.length, 1);
  assert.equal(r.rows[0].rxBps, 500);
  assert.equal(r.other.rxBps, 0);
});

// -------------------------------------------------------------- mergeRoster

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

// ------------------------------------------------------------------ nvidia

test("parseNvidiaCsv parses multiple GPUs", () => {
  const rows = Model.parseNvidiaCsv(fixture("nvidia.csv"));
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], {
    index: 0, name: "NVIDIA GeForce RTX 4070", utilPct: 12,
    memUsedM: 1024, memTotalM: 12282, tempC: 52, powerW: 35.5, clockMhz: 1800
  });
  assert.equal(rows[1].utilPct, 0);
});

test("parseNvidiaCsv maps N/A and [Not Supported] to null", () => {
  const rows = Model.parseNvidiaCsv(fixture("nvidia-na.csv"));
  assert.equal(rows.length, 1);
  assert.equal(rows[0].utilPct, null);
  assert.equal(rows[0].powerW, null);
  assert.equal(rows[0].clockMhz, null);
  assert.equal(rows[0].memUsedM, 1024);
  assert.equal(Model.parseNvidiaCsv("").length, 0);
  assert.equal(Model.parseNvidiaCsv("garbage line").length, 0);
});

test("parseNvidiaCsv rejoins comma-containing GPU names", () => {
  const rows = Model.parseNvidiaCsv(fixture("nvidia-comma.csv"));
  assert.equal(rows.length, 2);
  assert.equal(rows[0].name, "NVIDIA RTX 4070, Laptop GPU");
  assert.equal(rows[0].utilPct, 12);
  assert.equal(rows[0].clockMhz, 1800);
  assert.equal(rows[1].name, "NVIDIA GeForce GT 1030");
  assert.equal(rows[1].utilPct, 0);
});

// -------------------------------------------------------------- amd / intel

test("parseKeyValues reads key=value payloads", () => {
  const kv = Model.parseKeyValues("a=1\nb=two words\nBAD-KEY=3\n=4\n");
  assert.equal(kv.a, "1");
  assert.equal(kv.b, "two words");
  assert.equal(kv["BAD-KEY"], undefined);
});

test("normalizeAmdGpu converts sysfs units", () => {
  const g = Model.normalizeAmdGpu(Model.parseKeyValues(fixture("amd-sysfs.txt")));
  assert.equal(g.busy, 34);
  assert.equal(g.vramUsed, 4294967296);
  assert.equal(g.vramTotal, 12884901888);
  assert.equal(g.tempC, 52);
  assert.equal(g.tempJunctionC, 61);
  assert.equal(g.powerW, 85);
  assert.equal(g.clockMhz, 1800);
  assert.equal(g.memBusy, 22);
  assert.deepEqual(g.engines, [
    { id: "comp_1_0_0", busy: 5 },
    { id: "gfx", busy: 40 }
  ]);
});

test("normalizeAmdGpu tolerates missing files", () => {
  const g = Model.normalizeAmdGpu(Model.parseKeyValues("gpu_busy_percent=7\n"));
  assert.equal(g.busy, 7);
  assert.equal(g.vramUsed, null);
  assert.equal(g.tempC, null);
  assert.equal(g.memBusy, null);
  assert.deepEqual(g.engines, []);
});

test("normalizeIntelGpu reports a labeled frequency estimate, never busy", () => {
  const g = Model.normalizeIntelGpu(Model.parseKeyValues(fixture("intel-sysfs.txt")));
  assert.equal(g.busy, null);
  assert.equal(g.freqEstimate, 50);
  assert.equal(g.tempC, 48);
  assert.equal(Model.normalizeIntelGpu(Model.parseKeyValues("")).freqEstimate, null);
});

// ----------------------------------------------------------------- gpu list

test("normalizeGpuList validates entries", () => {
  const list = Model.normalizeGpuList({
    gpus: [
      { card: "card0", vendor: "amd", path: "/sys/class/drm/card0/device", boot: true },
      { card: "card1", vendor: "nvidia", path: "/sys/class/drm/card1/device", boot: false },
      { card: "evil", vendor: "amd", path: "/sys/x", boot: false },
      { card: "card2", vendor: "mali", path: "/sys/class/drm/card2/device", boot: false }
    ]
  });
  assert.equal(list.length, 2);
});

test("pickGpu auto prefers the boot card, then card0", () => {
  const gpus = [
    { card: "card1", vendor: "nvidia", path: "/sys/1", boot: false },
    { card: "card0", vendor: "amd", path: "/sys/0", boot: true }
  ];
  assert.equal(Model.pickGpu(gpus, "auto").card, "card0");
  assert.equal(Model.pickGpu(gpus, "card1").card, "card1");
  assert.equal(Model.pickGpu(gpus, "card9"), null);
  assert.equal(Model.pickGpu([], "auto"), null);
  const noBoot = [
    { card: "card1", vendor: "amd", path: "/sys/1", boot: false },
    { card: "card0", vendor: "intel", path: "/sys/0", boot: false }
  ];
  assert.equal(Model.pickGpu(noBoot, "auto").card, "card0");
});

// --------------------------------------------------------------- formatters

test("formatRate and formatBytes", () => {
  assert.equal(Model.formatRate(512), "512 B/s");
  assert.equal(Model.formatRate(1126), "1.1 KB/s");
  assert.equal(Model.formatRate(3686), "3.6 KB/s");
  assert.equal(Model.formatRate(5 * 1024 * 1024), "5 MB/s");
  assert.equal(Model.formatRate(null), "--");
  assert.equal(Model.formatBytes(2048), "2 KiB");
  assert.equal(Model.formatKiB(1024), "1 MiB");
  assert.equal(Model.formatKiB(1536), "1.5 MiB");
});

test("formatPct, formatTemp, formatUptime", () => {
  assert.equal(Model.formatPct(37.4), "37%");
  assert.equal(Model.formatPct(12.34, 1), "12.3%");
  assert.equal(Model.formatPct(null), "--");
  assert.equal(Model.formatTemp(52.4), "52°C");
  assert.equal(Model.formatTemp(null), "--");
  assert.equal(Model.formatUptime(90061), "1d 1h");
  assert.equal(Model.formatUptime(3660), "1h 1m");
  assert.equal(Model.formatUptime(300), "5m");
});

test("formatMhz, formatWatts, formatLoad", () => {
  assert.equal(Model.formatMhz(1800), "1800 MHz");
  assert.equal(Model.formatMhz(null), "--");
  assert.equal(Model.formatWatts(85), "85 W");
  assert.equal(Model.formatWatts(8.24), "8.2 W");
  assert.equal(Model.formatLoad(0.5), "0.50");
});

test("pushCapped bounds history", () => {
  var h = [];
  for (var i = 0; i < 70; i++) h = Model.pushCapped(h, i, 60);
  assert.equal(h.length, 60);
  assert.equal(h[0], 10);
  assert.equal(h[59], 69);
});

// -------------------------------------------------------------------- theme

test("Theme.alphaHex derives muted variants", () => {
  assert.equal(Theme.alphaHex("#cacccc", 0.5), "#cacccc80");
  assert.equal(Theme.alphaHex("#cacccc", 0), "#cacccc00");
  assert.equal(Theme.alphaHex("#cacccc", 1), "#caccccff");
  assert.equal(Theme.alphaHex("red", 0.5), null);
  assert.equal(Theme.gridFor("#101315"), "#10131524");   // 0.14 * 255 ≈ 36 = 0x24
});
