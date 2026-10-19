"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../../lib/index.mjs");

test("network actions show and copy each literal host address and MAC once", () => {
  const iface = { mac: "Aa:bb:cc:dd:ee:ff", addrs: ["192.0.2.4/24", "2001:db8::4/64", "192.0.2.4/16", "fe80::4/64"] };
  const rows = Model.addressActions(iface);
  assert.deepEqual(rows.map(row => row.value), [iface.mac, "192.0.2.4", "2001:db8::4", "fe80::4"]);
  assert.deepEqual(rows.map(row => row.label), ["MAC", "IPv4", "IPv6", "IPv6"]);
  assert.ok(rows.every(row => row.kind === "copy"));
  assert.deepEqual(Model.addressActions(null), []);
  assert.deepEqual(Model.addressActions({ mac: "", addrs: [] }), []);
  assert.equal(Model.interfaceSummary({ wireless: true, addrs: iface.addrs }, false), "Wi-Fi");
  assert.ok(Model.interfaceSummary({ wireless: true, addrs: iface.addrs }).includes("192.0.2.4"));
  assert.deepEqual(iface.addrs, ["192.0.2.4/24", "2001:db8::4/64", "192.0.2.4/16", "fe80::4/64"]);
});

test("mount actions retain complete literal paths and reject clipped launch targets", () => {
  const path = '/media/space "quote" \\ $(touch SHOULD_NOT_EXIST) % # café  ';
  const long = "/mnt/" + "a".repeat(200);
  const parsed = Model.parseDf(`/dev/sda1 ext4 1000 100 900 10% ${path}\n/dev/sda2 ext4 2000 200 1800 10% ${long}\n`);
  const actions = Model.mountActions(parsed);
  assert.equal(actions.length, 2);
  assert.equal(actions[0].value, path, "spaces, quotes, backslashes and trailing spaces are unmodified");
  assert.equal(actions[1].value, long, "a path past the old 128-character label limit stays complete");
  assert.ok(actions.every(row => row.available));
  assert.equal(Model.parseDf("/dev/sda1 ext4 1000 100 900 10% / leading-space  \n")[0].target, "/ leading-space  ");
  const oversized = Model.parseDf(`/dev/sda1 ext4 1000 100 900 10% /${"x".repeat(4096)}\n`);
  assert.equal(Model.mountActions(oversized)[0].available, false);
  assert.deepEqual(Model.mountActions(null), []);
});
