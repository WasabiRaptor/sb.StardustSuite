require "/scripts/util.lua"
require "/scripts/vec2.lua"

local debug = {
  --showLayoutBoxes = true,
}

-- metaGUI core
metagui = metagui or { }
local mg = metagui
mg.debugFlags = debug

require "/sys/metagui/gfx.lua"

function mg.path(path)
  if path:sub(1, 1) == '/' then return path end
  return (mg.cfg.assetPath or "/") .. path
end

function mg.asset(path)
  if path:sub(1, 1) == '/' then return path end
  return mg.cfg.themePath .. path
end

do -- encapsulate
  local id = 0
  function mg.newUniqueId()
    id = id + 1
    return tostring(id)
  end
end

function mg.mkwidget(parent, param)
  local id = mg.newUniqueId()
  if not parent then
    pane.addWidget(param, id)
    return id
  end
  widget.addChild(parent, param, id)
  return table.concat{ parent, '.', id }
end

local getproto do
  local pt = { }
  getproto = function(parent)
    if not pt[parent] then
      pt[parent] = { __index = parent }
    end
    return pt[parent]
  end
  function mg.proto(parent, table) return setmetatable(table or { }, getproto(parent)) end
end

-- some operating variables
local redrawQueue = { }
local recalcQueue = { }
local lastMouseOver
local mouseMap = setmetatable({ }, { __mode = 'v' })
local scriptUpdate = { }

-- and widget stuff
mg.widgetTypes = { }
mg.widgetBase = {
  expandMode = {0, 0}, -- default: decline to expand in either direction (1 is "can", 2 is "wants to")
}
local widgetTypes, widgetBase = mg.widgetTypes, mg.widgetBase

function widgetBase:minSize() return {0, 0} end
function widgetBase:preferredSize() return {0, 0} end

function widgetBase:init() end

function widgetBase:queueRedraw() redrawQueue[self] = true end
function widgetBase:draw() end

function widgetBase:isMouseInteractable() return false end
function widgetBase:onMouseEnter() end
function widgetBase:onMouseLeave() end
function widgetBase:onMouseButtonEvent(btn, down) end

function widgetBase:applyGeometry()
  self.size = self.size or self:preferredSize() -- fill in default size if absent
  local tp = self.position or {0, 0}
  local s = self
  while s.parent and not s.parent.isBaseWidget do
    tp = vec2.add(tp, s.parent.position or {0, 0})
    s = s.parent
  end
  s = s.parent -- we want the parent of the result
  -- apply calculated total position
  --sb.logInfo("processing " .. (self.backingWidget or "unknown") .. ", type " .. self.typeName)
  local etp
  if self.parent then etp = { tp[1], s.size[2] - (tp[2] + self.size[2]) } else etp = tp end -- if no parent, it must be a backing widget
  if self.backingWidget then
    widget.setSize(self.backingWidget, {math.floor(self.size[1]), math.floor(self.size[2])})
    widget.setPosition(self.backingWidget, {math.floor(etp[1]), math.floor(etp[2])})
  end
  --sb.logInfo("widget " .. (self.backingWidget or "unknown") .. ", type " .. self.typeName .. ", pos (" .. self.position[1] .. ", " .. self.position[2] .. "), size (" .. self.size[1] .. ", " .. self.size[2] .. ")")
  self:queueRedraw()
  if self.children then
    for k,c in pairs(self.children) do
      if c.applyGeometry then c:applyGeometry() end
    end
  end
end

function widgetBase:queueGeometryUpdate() recalcQueue[self] = true end
function widgetBase:updateGeometry()
  
end

function widgetBase:addChild(param) return mg.createWidget(param, self) end
function widgetBase:clearChildren()
  local c = { }
  for _, v in pairs(self.children or { }) do table.insert(c, v) end
  for _, v in pairs(c) do v:delete() end
end
function widgetBase:delete()
  if self.parent then -- remove from parent
    for k, v in pairs(self.parent.children) do
      if v == self then table.remove(self.parent.children, k) break end
    end
    self.parent:queueGeometryUpdate()
  end
  if self.id and _ENV[self.id] == self then _ENV[self.id] = nil end -- remove from global
  
  -- unhook from events and drawing
  redrawQueue[self] = nil
  recalcQueue[self] = nil
  if lastMouseOver == this then lastMouseOver = nil end
  
  -- clear out backing widgets
  local function rw(w)
    local parent, child = w:match('^(.*)%.(.-)$')
    widget.removeChild(parent, child)
  end
  if self.backingWidget then rw(self.backingWidget) end
  if self.subWidgets then for _, sw in pairs(self.subWidgets) do rw(sw) end end
end

require "/sys/metagui/widgets.lua"

-- DEBUG populate type names
for id, t in pairs(widgetTypes) do t.typeName = id end

function mg.createWidget(param, parent)
  if not param or not param.type or not widgetTypes[param.type] then return nil end -- abort if not valid
  local w = mg.proto(widgetTypes[param.type])
  if parent then -- add as child
    w.parent = parent
    w.parent.children = w.parent.children or { }
    table.insert(w.parent.children, w)
  end
  
  -- some basics
  w.id = param.id
  w.position = param.position
  w.explicitSize = param.size
  w.size = param.size
  
  local base
  if parent then -- find base widget
    local f = parent
    while not f.isBaseWidget and f.parent do f = f.parent end
    base = f.backingWidget
  end
  w:init(base, param)
  if w:isMouseInteractable() then -- enroll in mouse events
    if w.backingWidget then mouseMap[w.backingWidget] = w end
    if w.subWidgets then for _, sw in pairs(w.subWidgets) do mouseMap[sw] = w end end
  end
  if w.id and _ENV[w.id] == nil then
    _ENV[w.id] = w
  end
  return w
end

function mg.createImplicitLayout(list, parent, defaults)
  local p = { type = "layout", children = list }
  if parent then -- inherit some defaults off parent
    if parent.mode == "horizontal" then p.mode = "vertical"
    elseif parent.mode == "vertical" then p.mode = "horizontal" end
    p.spacing = parent.spacing
  end
  
  if defaults then util.mergeTable(p, defaults) end
  if type(list[1]) == "table" and not list[1][1] and not list[1].type then util.mergeTable(p, list[1]) end
  return mg.createWidget(p, parent)
end

local redrawFrame = { draw = function() theme.drawFrame() end }
function mg.setTitle(s)
  mg.cfg.title = s
  redrawQueue[redrawFrame] = true
end

-- -- --

function init()
  mg.cfg = config.getParameter("___") -- window config
  
  mg.theme = root.assetJson(mg.cfg.themePath .. "theme.json")
  mg.theme.id = mg.cfg.theme
  mg.theme.path = mg.cfg.themePath
  _ENV.theme = mg.theme -- alias
  require(mg.theme.path .. "theme.lua") -- load in theme
  
  -- TODO set up some parameter stuff?? idk, maybe the theme does most of that
  
  -- set up basic pane stuff
  local borderMargins = mg.theme.metrics.borderMargins[mg.cfg.style]
  frame = mg.createWidget({ type = "layout", size = mg.cfg.totalSize, position = {0, 0}, zlevel = -9999 })
  paneBase = mg.createImplicitLayout(mg.cfg.children, nil, { size = mg.cfg.size, position = {borderMargins[1], borderMargins[4]}, mode = mg.cfg.layoutMode or "vertical" })
  
  mg.theme.decorate()
  mg.theme.drawFrame()
  
  frame:updateGeometry()
  paneBase:updateGeometry()
  
  local sysUpdate = update
  for _, s in pairs(mg.cfg.scripts or { }) do
    init, update = nil
    require(mg.path(s))
    if update then table.add(scriptUpdate, update) end
    if init then init() end -- call script init
  end
end

local eventQueue = { }
local function runEventQueue()
  local next = { }
  for _, v in pairs(eventQueue) do
    local f, err = coroutine.resume(v)
    if coroutine.status(v) ~= "dead" then table.insert(next, v) -- execute; insert in next-frame queue if still running
    elseif not f then sb.logError(err) end
  end
  eventQueue = next
  for _, f in pairs(scriptUpdate) do f() end
end
function mg.startEvent(func, ...)
  local c = coroutine.create(func)
  coroutine.resume(c, ...)
  if coroutine.status(c) ~= "dead" then table.insert(eventQueue, c) end
end

local function findWindowPosition()
  if not mg.windowPosition then mg.windowPosition = {0, 0} end -- at the very least, make sure this exists
  local fp
  local sz = mg.cfg.totalSize
  local max = {1920, 1080} -- technically probably 4k
  
  local ws = "_tracker" -- widget to search for
  
  -- initial find
  for y=0,max[2],sz[2] do
    for x=0,max[1],sz[1] do
      if widget.inMember(ws, {x, y}) then
        fp = {x, y} break
      end
    end
    if fp then break end
  end
  
  if not fp then return nil end -- ???
  
  local isearch = 32
  -- narrow x
  local search = isearch
  while search >= 1 do
    while widget.inMember(ws, {fp[1] - search, fp[2]}) do fp[1] = fp[1] - search end
    search = search / 2
  end
  
  -- narrow y
  local search = isearch
  while search >= 1 do
    while widget.inMember(ws, {fp[1], fp[2] - search}) do fp[2] = fp[2] - search end
    search = search / 2
  end
  
  mg.windowPosition = fp
end

local lastMouseOver
function update()
  local ws = "_tracker"
  if not mg.windowPosition then
    findWindowPosition()
  else
    if not widget.inMember(ws, mg.windowPosition) or not widget.inMember(ws, vec2.add(mg.windowPosition, mg.cfg.totalSize)) then findWindowPosition() end
  end
  
  local c = widget.bindCanvas(ws)
  mg.mousePosition = c:mousePosition()
  
  runEventQueue() -- not entirely sure where this should go in the update cycle
  
  local mwc = widget.getChildAt(vec2.add(mg.windowPosition, mg.mousePosition))
  local mw = mwc and mouseMap[mwc:sub(2)]
  if mw ~= lastMouseOver then
    if mw then mw:onMouseEnter() end
    if lastMouseOver then lastMouseOver:onMouseLeave() end
  end
  lastMouseOver = mw
  if mw then
    widget.setPosition("_intercept", {0, 0})
  else
    widget.setPosition("_intercept", {-99999, -99999})
  end
  
  for w in pairs(recalcQueue) do w:updateGeometry() end
  for w in pairs(redrawQueue) do w:draw() end
  redrawQueue = { } recalcQueue = { }
end

function _mouseEvent(_, btn, down)
  if lastMouseOver then lastMouseOver:onMouseButtonEvent(btn, down) end
end