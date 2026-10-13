-- Renders the real panel.luau with every section combination against every
-- recorded state, then clicks through it like a user would.

H.surface = "panel"
H.declared = DECLARED
local loads = 0

local function load(cfg, store)
  H.store = H.copy(store)
  H.watchers, H.queue = {}, {}
  H.config = H.copy(DEFAULTS)
  for k, v in cfg do
    H.config[k] = v
  end
  H.rendered = nil
  LOAD()
  update() -- right after load: closed, so nothing renders
  H.drain()
  if H.rendered ~= nil then
    H.issue("rendered while closed")
  end
  onOpen("")
  H.drain()
  loads += 1
  if H.rendered == nil then
    H.issue("nothing rendered on open")
    return
  end
  if H.rendered.props.width ~= 352 or H.rendered.props.height ~= 572 then
    H.issue("panel root size wrong")
  end
  if H.secondTicks ~= true then
    H.issue("second ticks not requested on open")
  end
end

local SECTIONS = { "panel_hero", "panel_graph", "panel_readout", "panel_protection", "panel_events", "panel_actions" }
for _, name in SCENARIO_ORDER do
  for mask = 0, 63 do
    local cfg = {}
    for i, key in SECTIONS do
      cfg[key] = bit32.band(mask, bit32.lshift(1, i - 1)) ~= 0
    end
    load(cfg, SCENARIOS[name])
  end
end

-- ── Clicking through it (pwrstat, everything on) ──────────────────────────
local ALL = {}
for _, key in SECTIONS do
  ALL[key] = true
end
load(ALL, SCENARIOS.pwrstat_idle)

local function button(text)
  local found = H.find(H.rendered, function(n)
    return n.type == "button" and n.props.text == text
  end)
  if #found ~= 1 then
    H.issue(`button '{text}' found {#found} times`)
    return nil
  end
  return found[1]
end
local function click(text)
  local b = button(text)
  if b == nil then
    return
  end
  if b.props.enabled == false then
    H.issue(`clicked disabled button '{text}'`)
  end
  b.props.onClick()
  H.drain()
end
local function hasText(fragment)
  for _, t in H.texts do
    if t:find(fragment, 1, true) then
      return true
    end
  end
  return false
end

for _, span in { "10 min", "1 h", "2 min" } do
  click(span)
end
onGraphMove("0.5000", "0.5000")
H.drain()
if hasText("Now ·") then
  H.issue("hover readout did not leave 'Now'")
end
onGraphLeave()
H.drain()
if not hasText("Now ·") then
  H.issue("leaving the graph should show 'Now' again")
end

click("Self-test")
if not hasText("Run a battery self-test?") then
  H.issue("self-test asks first")
end
click("Cancel")
click("Self-test")
click("Run test")
local req = H.store["cmups.request"]
if req == nil or req.action ~= "test" then
  H.issue("Run test sent no request")
end
if button("Mute") and button("Mute").props.enabled ~= false then
  H.issue("buttons should be disabled while waiting")
end
noctalia.state.set("cmups.reply", { id = req.id, ok = true, message = "Done" })
H.drain()
if not hasText("Done") or button("Mute").props.enabled == false then
  H.issue("reply not shown or buttons still disabled")
end

click("Mute")
H.clock += 16
update()
H.drain()
if not hasText("No answer from the UPS service") then
  H.issue("no-answer timeout not shown")
end

click("Alarm off")
if H.store["cmups.request"].action ~= "alarm_off" then
  H.issue("alarm button sent the wrong action")
end

local settings = H.find(H.rendered, function(n)
  return n.type == "button" and n.props.glyph == "settings"
end)
settings[1].props.onClick()
if H.settingsOpened ~= 1 then
  H.issue("settings button did not open settings")
end

onClose()
H.drain()
if H.secondTicks ~= false then
  H.issue("second ticks not released on close")
end
H.rendered = nil
noctalia.state.set("cmups.link", H.store["cmups.link"])
H.drain()
if H.rendered ~= nil then
  H.issue("rendered while closed")
end
onOpen("")
H.drain()
if hasText("No answer") then
  H.issue("old reply still shown after reopening")
end

-- What it reads like
for _, name in { "pwrstat_idle", "pwrstat_on_battery", "nut_normal", "none_missing" } do
  load(ALL, SCENARIOS[name])
  print(`   {name}: {table.concat(H.texts, " | "):sub(1, 900)}`)
end
print(`panel renders: {loads}`)
H.report("panel")
