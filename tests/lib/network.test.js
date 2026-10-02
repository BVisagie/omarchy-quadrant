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
