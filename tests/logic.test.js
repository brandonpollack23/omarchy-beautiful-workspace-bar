// Run with `node tests/logic.test.js`.
const assert = require("node:assert/strict")
const test = require("node:test")
const Logic = require("../Logic.js")

test("entries orders regular workspaces by id and special ones by name", () => {
  const got = Logic.entries([
    { id: 3, name: "Notes" },
    { id: -98, name: "special:scratchpad" },
    { id: 1, name: "Home" },
    { id: -97, name: "special:music" },
    { id: 2, name: "2" },
  ], true)
  assert.deepEqual(got, { normal: [1, 2, 3], special: [-97, -98] })
})

test("entries hides special workspaces when asked", () => {
  const got = Logic.entries([{ id: 1, name: "1" }, { id: -98, name: "special:scratchpad" }], false)
  assert.deepEqual(got, { normal: [1], special: [] })
})

test("entries skips half-created and duplicate workspaces", () => {
  const got = Logic.entries([{ id: 0, name: "x" }, { id: 2 }, { id: 2 }, null, { id: NaN }], true)
  assert.deepEqual(got.normal, [2])
})

test("label shows Hyprland's name, or the number for an unnamed workspace", () => {
  assert.equal(Logic.label(1, "Home", false, false), "Home")
  assert.equal(Logic.label(4, "4", false, false), "4")
  assert.equal(Logic.label(4, "", false, false), "4")
  assert.equal(Logic.label(1, "Home", true, false), "1 Home")
  assert.equal(Logic.label(4, "4", true, false), "4")
  assert.equal(Logic.label(-98, "special:scratchpad", false, false), "scratchpad")
})

test("label fits a vertical bar", () => {
  assert.equal(Logic.label(3, "Notes", false, true), "3")
  assert.equal(Logic.label(-98, "special:scratchpad", false, true), "S")
})

test("title names a workspace in full", () => {
  assert.equal(Logic.title(1, "Home"), "1 · Home")
  assert.equal(Logic.title(5, "5"), "Workspace 5")
  assert.equal(Logic.title(-98, "special:scratchpad"), "scratchpad")
})

test("neighbour steps and wraps", () => {
  assert.equal(Logic.neighbour([1, 2, 5], 2, 1), 5)
  assert.equal(Logic.neighbour([1, 2, 5], 5, 1), 1)
  assert.equal(Logic.neighbour([1, 2, 5], 1, -1), 5)
  assert.equal(Logic.neighbour([1, 2, 5], 9, 1), 1)
  assert.equal(Logic.neighbour([], 1, 1), 0)
})

test("previewMode falls back to capture", () => {
  assert.equal(Logic.previewMode("icons"), "icons")
  assert.equal(Logic.previewMode("off"), "off")
  assert.equal(Logic.previewMode("nonsense"), "capture")
  assert.equal(Logic.previewMode(undefined), "capture")
})

test("logicalMonitor divides by scale and swaps a rotated monitor", () => {
  assert.deepEqual(Logic.logicalMonitor({ x: 0, y: 0, width: 3840, height: 2160, scale: 1.5 }),
    { x: 0, y: 0, width: 2560, height: 1440 })
  assert.deepEqual(Logic.logicalMonitor({ x: 10, y: 0, width: 1920, height: 1080, scale: 1, transform: 1 }),
    { x: 10, y: 0, width: 1080, height: 1920 })
  assert.equal(Logic.logicalMonitor(null), null)
})

test("previewLayout keeps drawable windows, floating last, capped", () => {
  const clients = [
    { address: "0xa", at: [0, 0], size: [100, 100], floating: true, class: "pavucontrol" },
    { address: "0xb", at: [100, 0], size: [200, 100], floating: false, class: "ghostty" },
    { address: "0xc", at: [0, 0], size: [0, 0] },
    { address: "0xd", at: [0, 0], size: [10, 10], hidden: true },
    { address: "0xe", at: [0, 0], size: [10, 10], mapped: false },
    { address: "0xf" },
  ]
  const got = Logic.previewLayout(clients, 12)
  assert.deepEqual(got.map(w => w.address), ["0xb", "0xa"])
  assert.equal(got[0].cls, "ghostty")
  assert.equal(Logic.previewLayout(clients, 1).length, 1)
})

test("pillGeometry insets the pill on the bar's cross axis", () => {
  const buttons = [{ id: 1, x: 0, y: 0, width: 40, height: 30 }, { id: 2, x: 44, y: 0, width: 60, height: 30 }]
  assert.deepEqual(Logic.pillGeometry(buttons, 2, false, 4), { visible: true, x: 44, y: 4, width: 60, height: 22 })
  assert.deepEqual(Logic.pillGeometry(buttons, 1, true, 4), { visible: true, x: 4, y: 0, width: 32, height: 30 })
  assert.equal(Logic.pillGeometry(buttons, 7, false, 4).visible, false)
})

test("address compares Hyprland's and Quickshell's forms", () => {
  assert.equal(Logic.address("0x5DBE17026020"), "5dbe17026020")
  assert.equal(Logic.address("5dbe17026020"), "5dbe17026020")
  assert.equal(Logic.address(undefined), "")
})

test("hyprState reads workspaces, focus, specials and window placement", () => {
  const state = Logic.hyprState(
    [
      { id: 2, name: "Web", windows: 1, monitor: "DP-1" },
      { id: -98, name: "special:scratchpad", windows: 2, monitor: "DP-1" },
      { id: 1, name: "1", windows: 0, monitor: "HDMI-A-1" },
      { id: 0, name: "half-made" },
    ],
    [
      { name: "DP-1", x: 0, y: 0, width: 2560, height: 1440, scale: 1.25, transform: 0, focused: true,
        activeWorkspace: { id: 2, name: "Web" }, specialWorkspace: { id: -98, name: "special:scratchpad" } },
      { name: "HDMI-A-1", x: 2048, y: 0, width: 1920, height: 1080, scale: 1, focused: false,
        activeWorkspace: { id: 1, name: "1" }, specialWorkspace: { id: 0, name: "" } },
      { name: "off", disabled: true, focused: false, activeWorkspace: { id: 9 } },
    ],
    [{ address: "0xAB", workspace: { id: 2, name: "Web" } }, { address: "0xcd" }]
  )
  assert.deepEqual(state.workspaces.map(w => w.id), [2, -98, 1])
  assert.equal(state.workspaces[0].windows, 1)
  assert.equal(state.focusedId, 2)
  assert.equal(state.focusedMonitor, "DP-1")
  assert.deepEqual(state.activeIds, [2, 1])
  assert.deepEqual(state.openSpecials, ["special:scratchpad"])
  assert.deepEqual(Object.keys(state.monitors), ["DP-1", "HDMI-A-1"])
  assert.equal(state.monitors["DP-1"].scale, 1.25)
  assert.deepEqual(state.windowWorkspace, { ab: 2 })
  assert.equal(state.clients.length, 1)
})

test("hyprState survives missing or broken input", () => {
  const state = Logic.hyprState(undefined, null, "nope")
  assert.deepEqual(state.workspaces, [])
  assert.equal(state.focusedId, 0)
})

test("urgentIds marks workspaces with urgent windows, not the focused one", () => {
  const where = { a: 2, b: 3, c: 3, d: 1 }
  assert.deepEqual(Logic.urgentIds({ a: true, b: true, c: true, d: true, gone: true }, where, 1), [2, 3])
  assert.deepEqual(Logic.urgentIds({ a: false }, where, 1), [])
})
