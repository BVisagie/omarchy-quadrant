import QtQuick
import "lib/index.mjs" as Model

QtObject {
  property var cfg: Model.readSettings({})
  property int barIntervalMs: 1000
  property var sample: ({ net: [{ n: "eth0", rx: 1000, tx: 2000 }, { n: "wlan0", rx: 0, tx: 0 }] })
  property string effectiveInterface: "eth0"
  property string networkInterface: "auto"
  property bool pinnedInterface: false
  property string networkInterfaceError: ""
  property string rateUnit: "bytes"
  property var ifaceRates: ({ rxBps: 1024, txBps: 300 })
  property var sysInfo: ({ net: { byName: {
    eth0: { mac: "Aa:bb:cc:dd:ee:ff", addrs: ["192.0.2.4/24", "2001:db8:1234:5678:90ab:cdef:1234:5678/64", "2001:db8::5/64"], speedMbps: 1000 },
    wlan0: { mac: "00:11:22:33:44:55", addrs: ["198.51.100.5/24"], wireless: true, speedMbps: 866 }
  } } })
  property var netRows: []
  property string netError: ""
  property var netHistory: []
  property var netLong: []
  property string effectiveDisk: "sda"
  property string diskDeviceError: ""
  property string diskInfoError: ""
  property var diskInfo: ({ disks: [{ name: "sda", model: "Fixture SSD", sizeBytes: 500000000000 }, { name: "sdb", model: "Other SSD" }],
    mounts: [{ source: "/dev/sda1", target: "/", size: 1000000000, used: 400000000, pct: 40 },
      { source: "/dev/sda2", target: '/media/space "quote" \\ $(touch NO) % # café  ', size: 1000000000, used: 200000000, pct: 20 }], backing: {} })
  property var diskRates: ({ utilPct: 20, readBps: 1024, writeBps: 512, readIops: 2, writeIops: 1 })
  property var diskHistory: []
  property var diskLong: []
  property var ioRows: []
  property var allIoRows: []
  property string procError: ""
  property var procStats: ({ mode: "expanded", dt: 1, ioReady: 2, ioVisible: 2, ioHidden: 0, cpu: [], mem: [], io: [], procs: 2 })
  property int polls: 0
  property int selects: 0
  function pollNet() { polls++ }
  function pollDiskUsage() { polls++ }
  function pollProcesses() { polls++ }
  function selectInterface(value) { selects++; networkInterface = value; pinnedInterface = value !== "auto"; effectiveInterface = value === "auto" ? "eth0" : value }
  function selectDisk(value) { selects++; effectiveDisk = value }
}
