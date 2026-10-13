-- Renders the real bar.luau for every option, orientation and recorded state.

H.surface = "bar"
H.declared = DECLARED
local loads = 0

local function load(cfg, store, vertical)
  H.store = H.copy(store)
  H.watchers, H.queue = {}, {}
  H.config = H.copy(DEFAULTS)
  for k, v in cfg do
    H.config[k] = v
  end
  H.vertical = vertical
  H.rendered, H.tooltip, H.visible, H.interval = nil, nil, nil, nil
  LOAD()
  update()
  H.drain()
  loads += 1
  local lost = store["cmups.link"] and store["cmups.link"].state == "lost"
  local wanted = if lost then 1000 else 60000
  if H.interval ~= wanted then
    H.issue(`update interval {tostring(H.interval)} (expected {wanted}) visible={tostring(H.visible)}`)
  end
  if H.visible == nil then
    H.issue("setVisible never called")
  end
  if H.visible then
    if H.rendered == nil then
      H.issue("visible but nothing rendered")
    end
    local t = H.tooltip
    if type(t) == "table" then
      for i, row in t do
        if type(row.key) ~= "string" or type(row.value) ~= "string" or row.value == "" then
          H.issue(`tooltip row {i} malformed`)
        end
      end
    elseif type(t) ~= "string" or t == "" then
      H.issue("tooltip missing")
    end
  end
end

for _, name in SCENARIO_ORDER do
  local store = SCENARIOS[name]
  for _, mode in OPTIONS.display_mode do
    for _, show in { true, false } do
      for _, content in OPTIONS.label_content do
        for _, only in { false, true } do
          for _, vertical in { false, true } do
            load({ display_mode = mode, show_label = show, label_content = content, only_on_battery = only, battery_color = "#ff8800" }, store, vertical)
          end
        end
      end
    end
  end
end

-- Hidden item ("show only on battery" on utility power) keeps a slow tick.
load({ only_on_battery = true }, SCENARIOS.pwrstat_idle, false)
if H.visible ~= false or H.interval ~= 60000 then
  H.issue("hidden bar item: visible/interval wrong")
end
-- Drawn battery takes Battery Color in the normal state, Warning when on battery.
load({ display_mode = "battery", battery_color = "#ff8800" }, SCENARIOS.pwrstat_idle, false)
local inks = H.find(H.rendered, function(n)
  return n.type == "box" and n.props.fill == "#ff8800"
end)
if #inks == 0 then
  H.issue("battery color not applied")
end
load({ display_mode = "battery", battery_color = "#ff8800" }, SCENARIOS.pwrstat_on_battery, false)
local warn = H.find(H.rendered, function(n)
  return n.type == "box" and n.props.fill == DEFAULTS.warning_color
end)
if #warn == 0 then
  H.issue("on battery the drawn battery should use the Warning color")
end
-- Click handler toggles the panel.
onClick()
if H.toggled ~= "cutecaption/cutemonitor-ups:details" then
  H.issue("onClick did not toggle the panel")
end

for _, name in { "pwrstat_idle", "pwrstat_on_battery", "pwrstat_lost", "none_missing" } do
  load({}, SCENARIOS[name], false)
  local tip = if type(H.tooltip) == "table" then (function()
    local rows = {}
    for _, r in H.tooltip do
      table.insert(rows, r.key .. "=" .. r.value)
    end
    return table.concat(rows, "; ")
  end)() else tostring(H.tooltip)
  print(`   {name}: {table.concat(H.texts, " ")} || tooltip: {tip}`)
end
print(`bar renders: {loads}`)
H.report("bar")
