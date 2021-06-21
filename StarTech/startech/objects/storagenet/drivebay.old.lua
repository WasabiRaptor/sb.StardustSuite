--
require "/lib/stardust/network.lua"
require "/lib/stardust/itemutil.lua"
require "/lib/stardust/playerext.lua"

spTemplate = {} -- template for functional storageProviders
spMeta = { __index = spTemplate }

spDeadTemplate = {} -- and a swap one
spDeadMeta = { __index = spDeadTemplate }

-- each discrete type of item takes up 24 bytes of capacity; each count of item takes one bit
local typeBits = 24 * 8

--------------------------
-- Storage Provider API --
--------------------------

-- Variable notes --
-- sp.slot - 1-8; item slot of the drive it's attached to
-- sp.item - full itemdescriptor of the drive
--+sp.item.parameters.syncId - generated unique ID, refreshed every commit
--+sp.item.parameters.contents - exactly what it sounds like
--+sp.item.parameters.filter / priority
--+sp.item.parameters.bitsUsed

-- sp.driveParameters.capacity - bits used

-- "kills" the provider (in case of drive removed, etc.)
function spTemplate:kill()
  shared.storageProvider[self.slot] = nil
  setmetatable(self, spDeadMeta)
  self.item = nil -- free this up immediately
end

function spTemplate:refreshInfo() -- refresh bits used etc.
  local bits = 0
  for k,item in ipairs(self.item.parameters.contents) do
    bits = bits + typeBits + item.count
  end
  self.item.parameters.bitsUsed = bits
  local fDesc, pDesc = "", ""
  if self.item.parameters.filter and self.item.parameters.filter ~= "" then
    fDesc = table.concat({ "\n^green;Filter: ^blue;", self.item.parameters.filter })
  end
  if (self.item.parameters.priority or 0) ~= 0 then
    pDesc = table.concat({ "\n^green;Priority: ^blue;", self.item.parameters.priority  })
  end
  self.item.parameters.description = table.concat({
    self.driveParameters.description, "\n^green;Bytes used: ^blue;",
    math.ceil(bits / 8), " / ", math.ceil(self.driveParameters.capacity / 8), fDesc, pDesc
  })
end

function spTemplate:commit()
  self:refreshInfo()
  self.item.parameters.syncId = genSyncId() -- generate a new sync UID
  -- the rest is already handled by being in the storage table
end

local priorityModifier = 1000000
function spTemplate:getPriority(item)
  local priorityMod = 0
  
  if self.item.parameters.filter then priorityMod = priorityModifier * 2 end -- any filter sets "go here first!"
  if item then
    if true then -- remove this later
      local itemAnon = {
        name = item.name,
        count = 1,
        parameters = item.parameters
      }
      
      for k, itm in pairs(self.item.parameters.contents) do
        if itemutil.canStack(itemAnon, itm) and itm.count > 0 then
          priorityMod = priorityMod + priorityModifier
          break 
        end
      end
    end
  end
  
  return (self.item.parameters.priority or 0) + priorityMod - ((self.slot - 1) * 0.1) -- might as well weight toward the first slot <.<
end

function spTemplate:getItemList()
  --return self.item.parameters.contents or { } -- the most simple thing ever :D
  if not self.item.parameters.contents then return { } end -- if no contents table, return empty and not nil
  local i = { }
  local ii = 1;
  for k, item in pairs(self.item.parameters.contents) do
    i[ii] = {
      name = item.name,
      count = item.count,
      parameters = item.parameters
    }
    ii = ii + 1
  end
  return i
end

function spTemplate:tryTakeItem(itemReq)
  local itemReqAnon = {
    name = itemReq.name,
    count = 1,
    parameters = itemReq.parameters
  }
  local numTaken = 0
  local rem = false
  
  for k,item in pairs(self.item.parameters.contents) do
    if itemutil.canStack(item, itemReq) then
      local take = math.min(item.count, itemReq.count)
      numTaken = take --numTaken + take
      itemReq.count = itemReq.count - take
      item.count = item.count - take
      if item.count <= 0 then
        self.item.parameters.contents[k] = false
        rem = true
      end
      break -- early-out on take; the drive bay's own operation will never result in two stacks of the same item identity
      -- thus any such occurrence means malformed data
    end
  end
  
  if numTaken > 0 then
    if rem then -- snap out any blanked entries
      self.item.parameters.contents = compactTable(self.item.parameters.contents)
    end
    self:commit()
    itemReqAnon.count = numTaken
    return itemReqAnon
  end
  return nil--{}
end

function spTemplate:tryPutItem(item)
  -- don't bother if filter excludes
  if self.item.parameters.filter and not itemutil.matchFilter(self.item.parameters.filter, item) then return nil end
  local numPut = 0
  
  local bitsFree = math.max(0, self.driveParameters.capacity - self.item.parameters.bitsUsed)
  if bitsFree == 0 then return nil end -- already full
  
  -- ... this part is going to be a pain
  local contents = self.item.parameters.contents or {}
  for k,sItem in ipairs(contents) do
    if itemutil.canStack(item, sItem) then 
      numPut = math.min(item.count, bitsFree)
      item.count = item.count - numPut
      sItem.count = sItem.count + numPut
      
      break -- only one stack per identity
    end
  end
  
  if numPut == 0 and bitsFree > typeBits then -- try new stack (> because no stacks of zero pls
    bitsFree = bitsFree - typeBits
    numPut = math.min(item.count, bitsFree)
    table.insert(contents, {
      name = item.name,
      count = numPut,
      parameters = item.parameters
    })
    item.count = item.count - numPut
  end
  
  if numPut > 0 then
    self:commit()
  end
end

-- Dummy functions for the dead variety
function spDeadTemplate:getPriority(item) return 0 end
function spDeadTemplate:getItemList() return {} end
function spDeadTemplate:tryTakeItem(itemReq) end
function spDeadTemplate:tryPutItem(itemReq) end

---------------
-- something --
---------------

function genSyncId()
  return math.random(0, 9007199254740992) -- limit of integer precision on IEEE double
end

function importDrive(slot, itemJson)
  itemJson = itemJson or storage.drives -- default param
  if not itemJson[slot] then return nil end -- what are you doing. go home.
  if not shared.storageProvider[slot] then shared.storageProvider[slot] = setmetatable({slot = slot}, spMeta) end
  local sp = shared.storageProvider[slot]
  
  sp.item = itemJson[slot]
  sp.driveParameters = itemutil.getCachedConfig(sp.item).config.driveParameters
  if not sp.item.parameters.syncId then
    -- init
    sp.item.parameters.contents = {}
    sp:commit()
  end
end

function eject(slot, item)
  storage.drives[slot] = nil
  world.spawnItem(item, entity.position())
end

function compactTable(tbl)
  local i, nt = 1, {}
  for k, v in ipairs(tbl) do
    if v then
      nt[i] = v
      i = i + 1
    end
  end
  return nt
end

function updateLights()
  local cc = storage.drives
  if not cc then return nil end -- !?
  local lights = {}
  for i,v in pairs(cc) do
    lights[i] = 1
  end
  object.setAnimationParameter("lights", lights)
end

-------------------------
-- Container functions --
-------------------------

local svc = { }

function init()
  shared.storageProvider = setmetatable({}, { __index = { _array = true } })
  
  -- import drives
  storage.drives = storage.drives or { }
  for slot in pairs(storage.drives) do importDrive(slot) end
  
  -- might as well refresh tooltip and the like
  for slot,sp in pairs(shared.storageProvider) do sp:commit() end
  
  -- set up messages
  for k,f in pairs(svc) do message.setHandler("drivebay:"..k, function(_, _, ...) return f(...) end) end
  
  updateLights()
end

function uninit()
  for k,sp in pairs(shared.storageProvider) do
    sp:commit() sp:kill() -- nuke all existing providers
  end
end

function die()
  for k,sp in pairs(shared.storageProvider) do
    sp:commit() sp:kill() -- save changes and nuke
  end
  for slot, item in pairs(storage.drives) do
    world.spawnItem(item, world.entityPosition(entity.id()))
  end
end

function svc.getDisplayItems() -- get drives for display; no sending hueg contents table
  local i = { false, false, false, false, false, false, false, false }
  for slot, itm in pairs(storage.drives) do
    i[slot] = { name = itm.name, count = 1, parameters = { } }
    for k, v in pairs(itm.parameters) do
      if k ~= "contents" then i[slot].parameters[k] = v end
    end
  end
  return i
end

function svc.swapDrive(pid, slot, item)
  -- verify that this is actually a drive
  if item and not itemutil.getCachedConfig(item).config.driveParameters then
    playerext.setPlayer(pid).giveItemToCursor(item)
    return nil
  end
  
  local sp = shared.storageProvider[slot]
  if sp then sp:commit() sp:kill() end -- update info and kill drive
  local old = storage.drives[slot] -- store old item
  storage.drives[slot] = item
  importDrive(slot)
  updateLights()
  playerext.setPlayer(pid).giveItemToCursor(old)
end

--[[
function containerCallback()
  if containerLock then return nil end
  containerLock = true
  
  local itemJson = world.containerItems(entity.id())
  for i = 1, 8 do
    local sp, item = shared.storageProvider[i], itemJson[i]
    if sp and not item then sp:kill() -- nuke removed
    elseif item and not itemutil.getCachedConfig(item).config.driveParameters then eject(i, item) -- not a drive
    elseif not sp or sp.item.parameters.syncId ~= item.parameters.syncId then importDrive(i, itemJson) -- import anything we don't have
    end
  end
  
  containerLock = false
  updateLights()
end--]]


function svc.getInfo(slot)
  local sp = shared.storageProvider[slot]
  if not sp then return nil end
  return { slot = slot, filter = sp.item.parameters.filter or "", priority = sp.item.parameters.priority or 0 }
end

function svc.setInfo(slot, filter, priority)
  local sp = shared.storageProvider[slot]
  if not sp then return nil end
  sp.item.parameters.priority = priority
  if filter == "" then filter = nil end
  sp.item.parameters.filter = filter
  sp:commit()
end

function onStorageNetUpdate()
  -- save memory by sharing a single cache among all things that have touched since last unload
  itemutil.mergeConfigCache(shared.controller.id)
end
