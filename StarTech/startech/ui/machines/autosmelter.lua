local function waitFor(p) -- wait for promise
  while not p:finished() do coroutine.yield() end
  return p
end

metagui.startEvent(function() -- sync
  while true do
    local data = waitFor(world.sendEntityMessage(pane.sourceEntity(), "uiSyncRequest")):result()
    if data then
      burnSlot:setItem(data.smelting.item)
      local bsb = burnSlot.subWidgets.slot
      if data.smelting.item.count >= 1 then
        widget.setItemSlotProgress(bsb, ( (data.smelting.remaining or 0) / (data.smelting.smeltTime or 1) ))
      else
        widget.setItemSlotProgress(bsb, 1)
      end
      
      fpLabel:setText(string.format("%i^accent;/^reset;%i^accent;FP^reset;", math.floor(0.5 + (data.batteryStats.energy or 0)), math.floor(0.5 + (data.batteryStats.capacity or 0))))
    end
  end
end)

function takeAll:onClick()
  local id = pane.sourceEntity()
  for i = 3, 11 do
    player.giveItem(world.containerItemAt(id, i))
    world.containerTakeAt(id, i)
  end
end
