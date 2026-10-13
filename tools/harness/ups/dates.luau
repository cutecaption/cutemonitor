-- Readout dates in every date style. pwrstat prints local wall-clock time, so
-- the "pwrstat" style must reproduce its text exactly (this caught Luau's
-- os.time(table) reading dates as UTC); the expectations hold in any timezone.

H.surface = "dates"
H.declared = DECLARED

local EXPECT = {
  short = { test = "Passed · Oct 5, 08:22", event = "Over voltage · Oct 11, 20:32 · 3 s" },
  pwrstat = { test = "Passed · 2026/10/05 08:22:32", event = "Over voltage · 2026/10/11 20:32:49 · 3 s" },
}

local function rowValue(texts, label)
  for i, t in texts do
    if t == label then
      return texts[i + 1]
    end
  end
  return nil
end

for _, style in OPTIONS.date_style do
  H.store = H.copy(SCENARIOS.pwrstat_idle)
  H.watchers, H.queue = {}, {}
  H.config = H.copy(DEFAULTS)
  H.config.display = "readout"
  H.config.date_style = style
  H.clock = 1791800000 -- after the fixture dates
  LOAD()
  update()
  H.drain()
  local test, event = rowValue(H.texts, "Test Result"), rowValue(H.texts, "Last Power Event")
  print(`   {style}: Test Result = {tostring(test)} | Last Power Event = {tostring(event)}`)
  local want = EXPECT[style]
  if want then
    if test ~= want.test then
      H.issue(`{style} Test Result: expected '{want.test}', got '{tostring(test)}'`)
    end
    if event ~= want.event then
      H.issue(`{style} Last Power Event: expected '{want.event}', got '{tostring(event)}'`)
    end
  elseif test == nil or not test:find(" ago", 1, true) then
    H.issue(`{style} Test Result should be relative, got '{tostring(test)}'`)
  end
end
H.report("dates")
