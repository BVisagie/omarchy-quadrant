// Quadrant data model — pure functions only, split by area.
//
// QML:  import "lib/index.mjs" as Model
// Node: const Model = require("../lib/index.mjs")
//
// Everything here is side-effect free so the whole data layer is
// testable with `node --test` against captured fixtures.

export { clamp, num, nonNeg, safeJson, safeJsonValue, clipStr, collapseSpaces, hasOwn } from "./core.mjs"
export { normalizeDeviceSetting, BAR_SEGMENTS, DEFAULT_BAR_SEGMENTS, segmentKeyForTab, normalizeSegments, segmentsFromSetting, unquoteSetting, parseIntSetting, parseEnumSetting, SETTING_DEFAULTS, BAR_PALETTES, BAR_LABEL_MODES, RATE_UNITS, readSettings, settingEquals, settingsPatch, toggleSegment, parseBoolSetting, effectiveSegments, visibleBarCells, normalizeIntegratedGpuDevice, normalizeInterfaceSetting, normalizeGpuDeviceSetting, normalizeDiskSetting } from "./settings.mjs"
export { formatUnit, formatBytes, formatRate, formatRateUnit, formatRateCompact, formatKiB, formatPct, formatTemp, formatMhz, formatGpuClock, formatWatts, formatLoad, formatUptime } from "./format.mjs"
export { parseCpuArray, parseStreamMem, parseStreamPsi, parseStreamNet, parseStreamDisk, parseStreamRoutes, parseGpuEngines, parseStreamGpu, parseStreamLine } from "./stream.mjs"
export { cpuDelta, parseCpuCoreArray, parseCpuCoreIds, cpuCoreDeltas, cpuBarTooltip, parseCpuTopoEntry, physicalCoreKey, parseCpuTopo, classifyUnlabeledCpus, classifyCpuTopology, cpuClassCounts, formatCpuClassMix, coreGridLayout, parseSystemCpu, cleanCpuName, formatCache } from "./cpu.mjs"
export { swapRates, memComposition, swapUsage, JUNK_RAM_TYPES, JUNK_RAM_MAKERS, ramTypeRanked, cleanRamMaker, dimmGiB, formatRamKit, formatRamMaker, parseUdevRam, formatRamLabel, parseSystemMem } from "./memory.mjs"
export { isExcludedDiskName, isPartitionName, parentDiskName, isVirtualDiskName, diskSourceBase, resolveBackingDisk, diskNamePresent, parseDiskstats, diskRates, DF_SKIP_TYPES, parseDf, collapseMounts, parseDiskInfoDisks, parseDiskInfoBacking, parseDiskInfo, parseDiskUsage, mergeDiskUsage, pickDisk } from "./disk.mjs"
export { netRates, pickInterface, normalizeAddr, stripSsLocal, ssParseLocal, ssParseUsers, ssScanNumbers, parseSs, sumSocketsByPid, socketsOnIface, computeNetAppRows } from "./network.mjs"
export { parsePs, WRAPPER_COMMS, APP_LABELS, KWORKER_TASK, basenameToken, hintTokens, labelFromHints, kworkerLabel, INTERPRETER_COMMS, displayName, parseProcRows, parseProcessRowList, parseProcessSample, nameAndCollapse, mergeRoster, processMemberKey, processRowKey, sameProcessRow, sameProcessSelection, processGroups, filterProcessGroups, formatProcessGroups, processScope } from "./processes.mjs"
export { parseNvidiaCsv, parseNvidiaApps, rankGpuRows, parseKeyValues, milliToWhole, microToWhole, enginesFromKv, normalizeAmdGpu, normalizeIntelGpu, clipPciClass, normalizeGpuListEntry, normalizeGpuList, pickGpu, isIntelIgpuSlot, amdLooksIntegrated, classifyGpuRole, pickIntegratedGpu, gpuIdentityEqual, gpuStreamVendor, gpuStreamPath, gpuStreamSignature, gpuDevicePinMessage, reconcileGpuTopology, parseAmdgpuIds, parseSystemGpus, gpuVendorLabel, cleanGpuName, gpuDisplayName, nvidiaMiBToBytes, gpuVramPct } from "./gpu.mjs"
export { drmMaxIntervalNs, drmEnginePreferred, parseDrmSnapshot, drmEngineBusyNs, drmBusyFromTotals, drmProcessRows, drmBusyFromEngines, drmBusyFromRc6, drmBusyPercent, drmMemoryKind, mergeGpuLive } from "./drm.mjs"
export { parseIpAddrJson, parseSystemNet, interfaceSummary, parseLspciMm, parseSystemHost, parseSystemInfo, junkDmi, hostLine } from "./identity.mjs"
export { graphGapSeconds, pushTimedWindow, pushBucket, mergeBuckets, HISTORY_FILE_VERSION, HISTORY_SERIES, sanitizeBuckets, loadHistoryFile, historyFilePayload } from "./history.mjs"
export { parseHex, mixHex, heatColor, band } from "./heat.mjs"
export { rgbToHsl, hslToHex, rotateHue, withAlpha, dimColor, seriesPalette, VIVID, BAR_GLYPHS, BAR_LETTERS, barLabelFor } from "./palette.mjs"
export { normalizeGpuDeviceId, normalizeDiskDeviceId } from "./settings.mjs"
export { diskDeviceById, diskHistoryTag } from "./disk.mjs"
export { gpuDeviceById, gpuHistoryTag, gpuRuntimeKey } from "./gpu.mjs"
export { devicePinMigration, devicePolicyResetPatch } from "./devices.mjs"
export { parseBootTime, historySeriesMatches } from "./history.mjs"
export { graphValue, graphWindow, graphStats, graphAxis, graphRuns, graphHoverIndex } from "./graphs.mjs"
