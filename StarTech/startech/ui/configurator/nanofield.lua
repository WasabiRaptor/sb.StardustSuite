--
require "/sys/stardust/skilltree/skilltree.lua"

local function loadItem()
  local nf = player.equippedItem("chest")
  if (nf or { }).name ~= "startech:nanofield" then return pane.dismiss() end
  return nf
end

local function saveItem(itm)
  local c = player.equippedItem("chest")
  itm.parameters.batteryStats = c.parameters.batteryStats or { } -- retain energy levels
  player.setEquippedItem("chest", itm)
end

function init()
  skilltree.initFromItem(treeCanvas, loadItem, saveItem)
end

function apply:onClick() skilltree.applyChanges() end
function reset:onClick() skilltree.resetChanges() end

if debugAP then
  function debugAP:onEnter()
    status.setStatusProperty("stardustlib:ap", tonumber(debugAP.text))
    skilltree.recalculateStats()
  end
end

function update()
  -- canary
  local function nope() skilltree.playSound "reset" pane.dismiss() end
  local itm = player.equippedItem("chest")
  if not itm or itm.name ~= "startech:nanofield" then return nope() end
  local sd = itm.parameters["stardustlib:skillData"]
  if not sd then return nope() end
  if sd.uuid ~= skilltree.uuid then return nope() end
end
