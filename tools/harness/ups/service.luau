-- Drives the real service.luau through a full life: start, outage, self-test,
-- blip, lost/recovered link, simulations, actions, NUT, the settings race,
-- no UPS, and a restart from saved files. Prints SCENARIO lines for the UI runs.

local FX = __require("fixtures")
local NFX = __require("nut_fixtures")
H.surface = "service"
H.declared = DECLARED
H.config = H.copy(DEFAULTS)
H.commands = { pwrstat = true, upsc = true, upscmd = true }

local function check(cond, what)
  if not cond then
    H.issue("CHECK FAILED: " .. what)
  end
end

local function withRow(text, label, value)
  local out, n = text:gsub("(\t\t" .. label .. "%.+ )[^\n]*", "%1" .. value:gsub("%%", "%%%%"))
  assert(n == 1, label)
  return out
end

-- Every reading carries the UPS's latest test result, as real pwrstat does.
local TEST = "Passed at 2026/10/05 08:22:32"
local function current(base)
  return withRow(base, "Test Result", TEST)
end
local IDLE_BASE = FX.real_status_idle
local BATTERY_BASE = FX.synth_on_battery

local PW = { status = current(IDLE_BASE), held = false }
local NUT = { list = NFX.synth_list, status = NFX.real_ddl_01, held = false }
local ACTIONS = {}
local function ok(stdout)
  return { exitCode = 0, stdout = stdout, stderr = "", timedOut = false }
end
H.run = function(argv)
  local cmd = table.concat(argv, " ")
  if argv[1] == "pwrstat" then
    if argv[2] == "-status" then
      local r = ok(PW.status)
      r.held = PW.held
      return r
    elseif argv[2] == "-config" then
      return ok(FX.real_config)
    end
    table.insert(ACTIONS, cmd)
    return ok("")
  elseif argv[1] == "upsc" then
    if argv[2] == "-l" then
      return ok(NUT.list)
    end
    local r = if argv[2]:find("@") then { exitCode = 1, stdout = "", stderr = NFX.real_error_refused, timedOut = false } else ok(NUT.status)
    r.held = NUT.held
    return r
  end
  H.issue("unexpected command " .. cmd)
  return { exitCode = 127, stdout = "", stderr = "", timedOut = false }
end

local function tick(n)
  for _ = 1, n or 1 do
    H.clock += 1
    update()
    H.drain()
  end
end

local function link()
  return H.store["cmups.link"] or {}
end
local function events()
  return H.store["cmups.events"] or {}
end
local function eventKeys()
  local keys = {}
  for i = #events(), 1, -1 do
    table.insert(keys, events()[i].key)
  end
  return table.concat(keys, ",")
end
local function scenario(name)
  print("SCENARIO " .. name .. " " .. H.encode(H.store))
end

-- ── Start (pwrstat, defaults) ────────────────────────────────────────────
scenario("starting") -- nothing published yet
LOAD()
check(link().state == "starting", "link starts as starting")
check(H.interval == 1000, "poll interval 1 s")
update() -- Noctalia calls update() right after load
H.drain()
check(link().state == "ok" and link().source == "pwrstat", "resolved to pwrstat")
tick(2)
local snap = H.store["cmups.snapshot"]
check(snap ~= nil and snap.model == "CP1500PFCLCDa", "snapshot published")
check(snap.runtimeFullSec == 190 * 60, "full-charge runtime reference")
check(H.store["cmups.policy"] and H.store["cmups.policy"].config.alarm == true, "policy from pwrstat -config")
check(H.store["cmups.series.2m"] and H.store["cmups.series.2m"].load_w ~= nil, "2m series published")
check(H.store["cmups.series.1h"] ~= nil, "1h series published")
scenario("pwrstat_idle")
PW.status = current(FX.real_status_loaded)
tick(3)
scenario("pwrstat_loaded")

-- ── Outage: battery, low battery, restore ─────────────────────────────────
local before = #events()
PW.status = current(BATTERY_BASE)
local outageStart = H.clock + 1
tick(1)
check(#events() == before, "first battery reading logs nothing yet")
tick(4)
scenario("pwrstat_on_battery")
check(events()[1].key == "power_failure" and events()[1].at == outageStart, "power failure dated to first reading")
PW.status = FX.synth_low_battery
tick(3)
scenario("pwrstat_low_battery")
PW.status = current(IDLE_BASE)
tick(2)
print("events after outage: " .. eventKeys())
check(events()[1].key == "power_restored" and events()[1].durationSec == 8, "restored with 8 s duration")

-- ── Self-test: on battery while "In progress" ─────────────────────────────
before = #events()
PW.status = withRow(withRow(BATTERY_BASE, "State", "Normal"), "Test Result", "In progress")
tick(6)
TEST = "Passed at 2026/10/12 18:00:05"
PW.status = current(IDLE_BASE)
tick(2)
check(#events() == before, "self-test not logged as an outage (self-test logging off)")
check(H.store["cmups.test"].at ~= nil, "tracked test result")

-- with self-test logging on, the test itself is logged
H.config.log_self_test = true
onConfigChanged()
PW.status = withRow(withRow(BATTERY_BASE, "State", "Normal"), "Test Result", "In progress")
tick(3)
TEST = "Passed at 2026/10/12 18:10:00"
PW.status = current(IDLE_BASE)
tick(2)
print("events after logged self-test: " .. eventKeys())
check(events()[1].key == "test_passed", "test_passed logged")

-- ── One-reading blip (no test change) ────────────────────────────────────
before = #events()
PW.status = current(BATTERY_BASE)
tick(1)
PW.status = current(IDLE_BASE)
tick(1)
check(#events() == before + 2 and events()[2].key == "power_failure", "one-reading blip logged at restore")

-- ── Lost: daemon errors (3 in a row), then lost_comm (immediate) ──────────
H.config.log_communication = true
onConfigChanged()
PW.status = FX.error_daemon
tick(2)
check(link().state == "ok", "two failures are not lost yet")
tick(1)
check(link().state == "lost", "third failure is lost")
scenario("pwrstat_lost")
PW.status = current(IDLE_BASE)
tick(1)
check(link().state == "ok", "recovered")
PW.status = FX.synth_lost_comm
tick(1)
check(link().state == "lost", "lost_comm is immediately lost")
PW.status = current(IDLE_BASE)
tick(1)
print("events after lost/recovered: " .. eventKeys())
check(events()[1].key == "comm_restored", "comm_restored logged")

-- ── Simulations ──────────────────────────────────────────────────────────
for _, name in { "on_battery", "low_battery", "overload", "lost", "no_ups" } do
  onIpc("simulate", name)
  H.drain()
  scenario("sim_" .. name)
  tick(1) -- a poll keeps the simulation on top
  check(link().state == (if name == "lost" then "lost" elseif name == "no_ups" then "unavailable" else "ok"), "simulation " .. name .. " survives a poll")
end
onIpc("simulate", "off")
tick(1)
check(link().state == "ok" and H.store["cmups.snapshot"].onBattery == false, "simulation off")
onIpc("simulate", "bogus")
check(H.logs[#H.logs]:find("unknown simulation", 1, true) ~= nil, "unknown simulation logged")
onIpc("dump")
check(H.logs[#H.logs]:find("cutemonitor-ups state:", 1, true) ~= nil, "dump logged")
onIpc("refresh")
H.drain()

-- ── Panel actions (pwrstat) ──────────────────────────────────────────────
local function request(id, action)
  noctalia.state.set("cmups.request", { id = id, action = action })
  H.drain()
  return H.store["cmups.reply"]
end
local r = request("a1", "mute")
check(r.id == "a1" and r.ok == true and r.message == "Done", "mute replied Done")
r = request("a2", "alarm_off")
check(ACTIONS[#ACTIONS] == "pwrstat -alarm off", "alarm off argv")
r = request("a3", "test")
check(ACTIONS[#ACTIONS] == "pwrstat -test", "test argv")
local count = #ACTIONS
request("a3", "test")
check(#ACTIONS == count, "repeated request id ignored")
r = request("a4", "format_disk")
check(r.id == "a4" and r.ok == false, "unknown action refused")

-- ── Switch to NUT (first local UPS) ───────────────────────────────────────
H.config.data_source = "nut"
onConfigChanged()
check(link().state == "starting", "source change restarts")
check(link().lastOkAt == nil, "last-reading time cleared on source change")
tick(1)
check(link().state == "ok" and link().source == "nut" and link().ups == "cyberpower", "resolved NUT first UPS")
tick(1)
check(H.store["cmups.policy"].source == "nut", "NUT policy")
scenario("nut_normal")
r = request("n1", "test")
check(r.ok and H.terminal[#H.terminal]:find("upscmd 'cyberpower' test.battery.start.quick", 1, true) ~= nil, "NUT test opens upscmd in a terminal")
NUT.status = NFX.synth_on_battery
tick(3)
scenario("nut_on_battery")
NUT.status = NFX.real_ddl_02
tick(2)
scenario("nut_ddl_02")
NUT.status = NFX.synth_error_stale
tick(1)
check(link().state == "lost", "NUT data stale is immediately lost")
NUT.status = NFX.real_ddl_01
tick(1)

-- ── Race: settings change while a search is still running ────────────────
H.config.nut_ups = "far@unreachable"
NUT.held = true
onConfigChanged()
tick(1) -- search for far@unreachable starts and hangs
NUT.held = false
H.config.nut_ups = ""
onConfigChanged()
tick(1) -- new search: first local UPS
check(link().state == "ok" and link().ups == "cyberpower", "new setting used right away")
H.release() -- the old search answers late
check(link().state == "ok" and link().ups == "cyberpower", "late answer from the old search is ignored")
tick(1)
check(link().state == "ok" and link().ups == "cyberpower", "still on the new setting after a poll")

-- ── No UPS at all ────────────────────────────────────────────────────────
H.commands = {}
H.config.data_source = "auto"
onConfigChanged()
tick(1)
check(link().state == "unavailable", "unavailable without pwrstat/upsc")
check(link().lastOkAt == nil, "no last-reading time carried over without a source")
print("no-UPS reason: " .. tostring(link().message))
scenario("none_missing")
H.sysfiles["/usr/bin/pwrstat"] = true
H.clock += 31
tick(1)
print("permission reason: " .. tostring(link().message))
check(tostring(link().message):find("power group", 1, true) ~= nil, "permission reason")
scenario("none_permission")
H.sysfiles = {}
H.commands = { pwrstat = true, upsc = true, upscmd = true }
H.clock += 31
tick(1)
check(link().state == "ok", "found again after retry")

-- ── Poll interval change ─────────────────────────────────────────────────
H.config.poll_interval = "5"
onConfigChanged()
check(H.interval == 5000, "poll interval 5 s applied")

-- ── Restart: reload saved files ──────────────────────────────────────────
local savedEvents = H.encode(H.store["cmups.events"])
local savedTest = H.encode(H.store["cmups.test"])
check(H.files["/data/events.json"] ~= nil and H.files["/data/state.json"] ~= nil, "files written")
check(H.files["/data/events.json.tmp"] == nil, "no temp file left")
H.store, H.watchers, H.queue = {}, {}, {}
H.config = H.copy(DEFAULTS)
LOAD()
check(H.encode(H.store["cmups.events"]) == savedEvents, "events reloaded after restart")
check(H.encode(H.store["cmups.test"]) == savedTest, "test reloaded after restart")
update()
H.drain()
check(link().state == "ok", "restart resolves again")

H.report("service")
for _, line in H.logs do
  print("   log: " .. line:sub(1, 160))
end
