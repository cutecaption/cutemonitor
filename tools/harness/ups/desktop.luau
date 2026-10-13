-- Renders the real desktop.luau for every layout option against every recorded
-- service state, validating each tree against Noctalia 5.2.1's rules.

H.surface = "desktop"
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
  H.interval = nil
  LOAD()
  update()
  H.drain()
  loads += 1
  local tree = H.rendered
  if tree == nil then
    H.issue("nothing rendered")
    return
  end
  if tree.props.width ~= 252 then
    H.issue(`root width {tostring(tree.props.width)} (expected 252) for display={H.config.display}`)
  end
  local lost = store["cmups.link"] and store["cmups.link"].state == "lost"
  local wanted = if lost then 1000 else 60000
  if H.interval ~= wanted then
    H.issue(`update interval {tostring(H.interval)} (expected {wanted})`)
  end
  -- a later link update re-renders without error
  if store["cmups.link"] then
    noctalia.state.set("cmups.link", store["cmups.link"])
    H.drain()
  end
end

local STATS = OPTIONS.big1
for _, name in SCENARIO_ORDER do
  local store = SCENARIOS[name]
  -- Status
  for _, style in OPTIONS.number_style do
    for _, big1 in STATS do
      for _, big2 in OPTIONS.big2 do
        load({ display = "status", number_style = style, big1 = big1, big2 = big2 }, store)
      end
    end
  end
  for _, d in OPTIONS.detail1 do
    load({ display = "status", detail1 = d, detail2 = d, detail3 = "none" }, store)
  end
  -- Graph
  for _, l1 in OPTIONS.line1 do
    for _, l2 in OPTIONS.line2 do
      for _, span in OPTIONS.time_span do
        load({ display = "graph", line1 = l1, line2 = l2, time_span = span, show_label = true }, store)
      end
    end
  end
  load({ display = "graph", show_label = false }, store)
  -- Gauges
  for _, layout in OPTIONS.gauge_layout do
    for _, b in OPTIONS.bar1 do
      load({ display = "gauges", gauge_layout = layout, bar1 = b }, store)
    end
    load({ display = "gauges", gauge_layout = layout, bar1 = "none", bar2 = "none", bar3 = "none", status_line = false }, store)
    load({ display = "gauges", gauge_layout = layout, status_line = false }, store)
  end
  -- Readout
  local allOn, allOff = { display = "readout" }, { display = "readout" }
  for key in DECLARED do
    if key:match("^row_") or key:match("^extra_") then
      allOn[key] = true
      allOff[key] = false
    end
  end
  load(allOn, store)
  load(allOff, store)
  load({ display = "readout" }, store)
end

-- Show what the defaults read like in a few states.
for _, name in { "starting", "pwrstat_idle", "pwrstat_on_battery", "pwrstat_low_battery", "pwrstat_lost", "nut_normal", "none_missing" } do
  for _, display in { "status", "gauges", "readout" } do
    load({ display = display }, SCENARIOS[name])
    print(`   {name} / {display}: {table.concat(H.texts, " | ")}`)
  end
end

print(`desktop renders: {loads}`)
H.report("desktop")
