-- proxy for playerext


--local synchronous = (player or tech) and true or false
local err = nil

local function resultOf(promise)
  err = nil
  if not promise:finished() then return promise end
  if not promise:succeeded() then
    err = promise:error()
    return nil
  end
  return promise:result()
end

if not playerext then
  playerext = { }
  
  
  local plr
  function playerext.setPlayer(id)
    if id then plr = id
    elseif player then plr = player.id()
    elseif entity then plr = entity.id()
    end
    return playerext -- chainable
  end
  
  local commands = {
    "message",
    "openInterface",
    "openUI",
    
    "getPlayerConfig",
    "setPlayerConfig",
    
    "warp", "positionWarp",
    
    "giveItems",
    "giveItemToCursor",
    "giveAP",
    "getEquip",
    "setEquip",
    "updateEquip",
    
    "readEquipEnergy",
    "fillEquipEnergy",
    "drawEquipEnergy",
    "fillEquipEnergyAsync",
    
    "getTechOverride",
    "overrideTech",
    "restoreTech",
    
    "queueDrawable",
    "queueLight",
    "queueParticle",
    "playAudio",
    "getHUDPosition",
    
    "setGlowColor",
  }
  
  for _, cmd in pairs(commands) do -- generate proxies automatically
    playerext[cmd] = function(...)
      if not plr then playerext.setPlayer() end
      return resultOf(world.sendEntityMessage(plr, "playerext:" .. cmd, ...))
    end
  end
end
