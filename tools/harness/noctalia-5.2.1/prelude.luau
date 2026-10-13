
ui = {}
local function ctor(t)
  return function(props, children)
    return { type = t, props = props or {}, children = children or {} }
  end
end
ui.column = ctor("column")
ui.row = ctor("row")
ui.box = ctor("box")
ui.label = ctor("label")
ui.glyph = ctor("glyph")
ui.image = ctor("image")
ui.separator = ctor("separator")
ui.spacer = ctor("spacer")
ui.progress = ctor("progress")
ui.button = ctor("button")
ui.graph = ctor("graph")
ui.input = ctor("input")
ui.markdown = ctor("markdown")
ui.select = ctor("select")
ui.slider = ctor("slider")
ui.toggle = ctor("toggle")
ui.scroll = ctor("scroll")
ui.dragSource = ctor("drag_source")
ui.dropZone = ctor("drop_zone")
