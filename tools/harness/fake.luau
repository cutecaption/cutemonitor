-- Fake Noctalia runtime for running the plugin's entry scripts offline.
-- Mirrors the 5.2.1 behaviors read from source: JSON state (luaToJson rules),
-- watchers delivered after the current callback, async command callbacks,
-- tr() returning the key (and logging) when missing.

H = {
  issues = {},
  clock = 1760300000,
  config = {},
  declared = {},
  store = {},
  watchers = {},
  queue = {}, -- pending async work: { kind = "cmd"|"watch", ... }
  held = {}, -- command results held back until H.release()
  files = {},
  sysfiles = {},
  commands = {},
  run = nil, -- function(argv) -> result | nil (nil = never answers)
  terminal = {},
  logs = {},
  interval = nil,
  secondTicks = nil,
  rendered = nil,
  tooltip = nil,
  visible = nil,
  vertical = false,
  toggled = nil,
  settingsOpened = 0,
  inflight = 0,
  missingTr = {},
  texts = {},
  surface = "?",
}

function H.issue(msg)
  table.insert(H.issues, `[{H.surface}] {msg}`)
end

local realOs = os
os = {
  time = function(t)
    if t ~= nil then
      return realOs.time(t)
    end
    return H.clock
  end,
  date = realOs.date,
  clock = realOs.clock,
  difftime = realOs.difftime,
}

-- ── JSON (luaToJson rules) ───────────────────────────────────────────────
local function finite(n)
  return n == n and n ~= math.huge and n ~= -math.huge
end

local function normalize(v, depth, path)
  if depth > 32 then
    H.issue("json depth > 32 at " .. path)
    return nil
  end
  local t = type(v)
  if t == "nil" or t == "boolean" or t == "string" then
    return v
  elseif t == "number" then
    if not finite(v) then
      H.issue("non-finite number at " .. path)
      return nil
    end
    return v
  elseif t == "table" then
    local n = #v
    local out = {}
    if n > 0 then
      for i = 1, n do
        out[i] = normalize(v[i], depth + 1, `{path}[{i}]`)
      end
      for k in v do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
          H.issue(`array at {path} has extra key {tostring(k)} (dropped by Noctalia)`)
        end
      end
      return out
    end
    for k, val in v do
      if type(k) == "string" then
        out[k] = normalize(val, depth + 1, `{path}.{k}`)
      else
        H.issue(`object at {path} has non-string key {tostring(k)} (dropped by Noctalia)`)
      end
    end
    return out
  end
  H.issue(`unsupported {t} at {path}`)
  return nil
end
H.normalize = normalize

local function encode(v)
  local t = type(v)
  if v == nil then
    return "null"
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "number" then
    if v % 1 == 0 and math.abs(v) < 9.007199254740992e15 then
      return string.format("%d", v)
    end
    return string.format("%.17g", v)
  elseif t == "string" then
    local s = v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t" end
      return string.format("\\u%04x", string.byte(c))
    end)
    return '"' .. s .. '"'
  end
  if #v > 0 then
    local parts = {}
    for i = 1, #v do
      parts[i] = encode(v[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in v do
    table.insert(keys, k)
  end
  table.sort(keys)
  local parts = {}
  for _, k in keys do
    table.insert(parts, encode(k) .. ":" .. encode(v[k]))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function decode(s)
  local i = 1
  local function ws()
    i = s:find("[^ \t\r\n]", i) or #s + 1
  end
  local value
  local function str()
    i += 1
    local out = {}
    while true do
      local c = s:sub(i, i)
      if c == '"' then
        i += 1
        return table.concat(out)
      elseif c == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e == "u" then
          table.insert(out, utf8.char(tonumber(s:sub(i + 2, i + 5), 16)))
          i += 6
        else
          table.insert(out, ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[e] or e)
          i += 2
        end
      else
        table.insert(out, c)
        i += 1
      end
    end
  end
  function value()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      i += 1
      local out = {}
      ws()
      if s:sub(i, i) == "}" then
        i += 1
        return out
      end
      while true do
        ws()
        local k = str()
        ws()
        i += 1 -- :
        out[k] = value()
        ws()
        local d = s:sub(i, i)
        i += 1
        if d == "}" then
          return out
        end
      end
    elseif c == "[" then
      i += 1
      local out = {}
      ws()
      if s:sub(i, i) == "]" then
        i += 1
        return out
      end
      while true do
        table.insert(out, value())
        ws()
        local d = s:sub(i, i)
        i += 1
        if d == "]" then
          return out
        end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(i, i + 3) == "true" then
      i += 4
      return true
    elseif s:sub(i, i + 4) == "false" then
      i += 5
      return false
    elseif s:sub(i, i + 3) == "null" then
      i += 4
      return nil
    end
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    i += #num
    return tonumber(num)
  end
  local ok, result = pcall(value)
  if not ok then
    return nil, tostring(result)
  end
  return result
end
H.encode, H.decode = encode, decode

local function copy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, val in v do
    out[k] = copy(val)
  end
  return out
end
H.copy = copy

-- ── Async queue ──────────────────────────────────────────────────────────
function H.drain(limit)
  limit = limit or 1000
  local n = 0
  while #H.queue > 0 do
    n += 1
    if n > limit then
      H.issue("queue did not settle")
      return
    end
    local job = table.remove(H.queue, 1)
    if job.kind == "cmd" then
      H.inflight -= 1
      job.cb(job.result)
    else
      job.fn(copy(job.value))
    end
  end
end

function H.release()
  for _, job in H.held do
    table.insert(H.queue, job)
  end
  H.held = {}
  H.drain()
end

-- ── Translations ─────────────────────────────────────────────────────────
local function subst(text, s)
  if s == nil then
    return text
  end
  return (text:gsub("{(%w+)}", function(name)
    local v = s[name]
    if v == nil then
      return "{" .. name .. "}"
    end
    if type(v) == "number" and v % 1 == 0 then
      return string.format("%d", v)
    end
    return tostring(v)
  end))
end

-- ── noctalia.* ───────────────────────────────────────────────────────────
noctalia = {
  getConfig = function(key)
    if not H.declared[key] then
      H.issue(`getConfig("{key}") is not declared for this entry`)
    end
    return copy(H.config[key])
  end,
  tr = function(key, s)
    local text = TR[key]
    if text == nil then
      H.missingTr[key] = true
      H.issue(`tr missing key {key}`)
      return key
    end
    return subst(text, s)
  end,
  trp = function(key, count, s)
    local merged = copy(s or {})
    merged.count = count
    local variant = key .. (if count == 1 then ".one" else ".other")
    local text = TR[variant] or TR[key]
    if text == nil then
      H.issue(`trp missing key {key}`)
      return key
    end
    return subst(text, merged)
  end,
  formatTime = function(pattern, at)
    at = at or H.clock
    local p = pattern:gsub("{:(.-)}", "%1")
    p = p:gsub("%%e", function()
      return string.format("%2d", tonumber(os.date("%d", at)))
    end)
    return os.date(p, at)
  end,
  timeFormat = function()
    return "{:%H:%M}"
  end,
  nowMs = function()
    return H.clock * 1000
  end,
  setUpdateInterval = function(ms)
    H.interval = ms
  end,
  log = function(msg)
    table.insert(H.logs, msg)
  end,
  openSettings = function()
    H.settingsOpened += 1
  end,
  togglePanel = function(id)
    H.toggled = id
  end,
  commandExists = function(name)
    return H.commands[name] == true
  end,
  fileExists = function(path)
    return H.files[path] ~= nil or H.sysfiles[path] == true
  end,
  readFile = function(path)
    return H.files[path]
  end,
  writeFile = function(path, text)
    if type(text) ~= "string" then
      H.issue("writeFile with non-string")
    end
    H.files[path] = text
    return true
  end,
  renameFile = function(from, to)
    H.files[to] = H.files[from]
    H.files[from] = nil
    return true
  end,
  pluginDataDir = function()
    return "/data"
  end,
  runAsync = function(argv, cb, timeoutMs)
    if type(argv) ~= "table" then
      H.issue("runAsync with a shell string")
    end
    if timeoutMs ~= nil and (timeoutMs < 50 or timeoutMs > 60000) then
      H.issue("runAsync timeout outside 50..60000")
    end
    if H.inflight >= 8 then
      return false
    end
    local result = H.run(argv)
    H.inflight += 1
    if result.held then
      table.insert(H.held, { kind = "cmd", cb = cb, result = result }) -- answers on H.release()
    else
      table.insert(H.queue, { kind = "cmd", cb = cb, result = result })
    end
    return true
  end,
  runInTerminal = function(cmd)
    table.insert(H.terminal, cmd)
    return true
  end,
  json = {
    encode = function(v, pretty)
      normalize(v, 0, "json.encode")
      return encode(v)
    end,
    decode = function(s)
      return decode(s)
    end,
  },
  string = {
    trim = function(s)
      return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end,
  },
  state = {
    get = function(key)
      return copy(H.store[key])
    end,
    set = function(key, v)
      local value = normalize(v, 0, "state." .. key)
      H.store[key] = value
      for _, fn in H.watchers[key] or {} do
        table.insert(H.queue, { kind = "watch", fn = fn, value = value })
      end
    end,
    watch = function(key, fn)
      H.watchers[key] = H.watchers[key] or {}
      table.insert(H.watchers[key], fn)
    end,
  },
}

-- ── Tree validation (rules from ui_tree_reconciler.cpp) ───────────────────
local COLOR_PROPS = { color = true, color2 = true, fill = true, track = true, border = true }
local CALLBACKS = { onClick = true, onRightClick = true, onHover = true, onPointerMove = true, onPointerLeave = true, onChange = true, onSubmit = true, onScroll = true, onDrop = true, onDragEnd = true }
local UNIT = { opacity = true, fillOpacity = true, progress = true }
local NUMERIC = { width = true, height = true, size = true, fontSize = true, gap = true, padding = true, radius = true, borderWidth = true, thickness = true, flexGrow = true, maxLines = true, lineWidth = true, glyphSize = true, minWidth = true, minHeight = true }

local function validColor(token)
  if type(token) ~= "string" then
    return false
  end
  if token:match("^#%x%x%x%x%x%x$") or token:match("^#%x%x%x%x%x%x%x%x$") then
    return true
  end
  local base, alpha = token:match("^([%w_]+)/([%d.]+)$")
  if base then
    local a = tonumber(alpha)
    return RULES.roles[base] == true and a ~= nil and a >= 0 and a <= 1
  end
  return RULES.roles[token] == true
end

function H.validate(node, depth, path)
  depth = depth or 1
  path = path or "root"
  if depth > 32 then
    H.issue("tree deeper than 32 at " .. path)
    return
  end
  if type(node) ~= "table" or type(node.type) ~= "string" then
    H.issue("not a ui node at " .. path)
    return
  end
  local known = RULES.props[node.type]
  if known == nil then
    H.issue("unknown node type " .. node.type)
    return
  end
  if H.surface == "bar" and (node.type == "input" or node.type == "select" or node.type == "scroll") then
    H.issue(node.type .. " is not supported in the bar")
  end
  local where = `{path}>{node.type}`
  for k, v in node.props do
    if k == "key" then
      continue
    end
    if not known[k] then
      H.issue(`{where} has no prop '{k}'`)
    end
    if COLOR_PROPS[k] and not validColor(v) then
      H.issue(`{where} bad color {k}={tostring(v)}`)
    end
    if RULES.enums[k] and not RULES.enums[k][v] then
      H.issue(`{where} bad {k}={tostring(v)}`)
    end
    if CALLBACKS[k] and type(v) ~= "function" and not (type(v) == "string" and type(getfenv(1)[v]) == "function") then
      H.issue(`{where} callback {k} does not resolve ({tostring(v)})`)
    end
    if (NUMERIC[k] or UNIT[k]) and (type(v) ~= "number" or not finite(v) or v < 0) then
      H.issue(`{where} bad number {k}={tostring(v)}`)
    end
    if UNIT[k] and type(v) == "number" and v > 1 then
      H.issue(`{where} {k}={v} > 1`)
    end
    if k == "maxLines" and type(v) == "number" and (v < 1 or v % 1 ~= 0) then
      H.issue(`{where} maxLines={v}`)
    end
  end
  if node.type == "label" then
    if type(node.props.text) ~= "string" then
      H.issue(`{where} text is {type(node.props.text)}`)
    else
      table.insert(H.texts, node.props.text)
      if node.props.text:match("^[a-z_]+%.[a-z_.%d]+$") then
        H.issue(`{where} shows a raw key '{node.props.text}'`)
      end
    end
  end
  if node.type == "button" and node.props.text ~= nil then
    table.insert(H.texts, "[" .. node.props.text .. "]")
  end
  if node.type == "box" and node.props.fill == nil then
    -- Box copies its rect's default style and only resolves "clear" once a fill is set,
    -- so an unfilled box draws solid black (box.cpp). Empty space is ui.spacer's job.
    H.issue(`{where} has no fill and will draw black; use ui.spacer for empty space`)
  end
  if node.type == "glyph" and not RULES.glyphs[node.props.name] then
    H.issue(`{where} unknown glyph {tostring(node.props.name)}`)
  end
  if node.type == "button" and node.props.glyph ~= nil and not RULES.glyphs[node.props.glyph] then
    H.issue(`{where} unknown button glyph {tostring(node.props.glyph)}`)
  end
  if node.type == "graph" then
    for _, field in { "values", "values2" } do
      local values = node.props[field]
      if values ~= nil then
        for i, x in values do
          if type(x) ~= "number" or not finite(x) or x < 0 or x > 1 then
            H.issue(`{where} {field}[{i}]={tostring(x)}`)
            break
          end
        end
      end
    end
  end
  if #node.children > 256 then
    H.issue(`{where} has {#node.children} children (> 256)`)
  end
  for i, child in node.children do
    H.validate(child, depth + 1, `{where}[{i}]`)
  end
end

-- Finds nodes (depth-first) whose props match `pred`.
function H.find(node, pred, out)
  out = out or {}
  if node == nil then
    return out
  end
  if pred(node) then
    table.insert(out, node)
  end
  for _, child in node.children or {} do
    H.find(child, pred, out)
  end
  return out
end

function H.render(tree)
  H.rendered = tree
  H.texts = {}
  H.validate(tree)
end

desktopWidget = { render = H.render }
barWidget = {
  render = H.render,
  setTooltip = function(t)
    H.tooltip = t
  end,
  setVisible = function(v)
    H.visible = v
  end,
  isVertical = function()
    return H.vertical
  end,
}
panel = {
  render = H.render,
  setWantsSecondTicks = function(v)
    H.secondTicks = v
  end,
}

function H.report(title)
  print(`== {title}: {#H.issues} issue(s)`)
  local seen = {}
  for _, msg in H.issues do
    if not seen[msg] then
      seen[msg] = true
      print("   ISSUE " .. msg)
    end
  end
end
