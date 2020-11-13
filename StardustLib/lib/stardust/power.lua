-- StardustLib.Power //
-- Fluxpulse Power System

require "/lib/stardust/interop.lua"

local power = { }
_ENV.power = power

-- one fluxpacket translates to this many Joules in Frackin' Universe's power system
-- multiple balance points are possible...
--power.translationFactorFU = (1/60) * 1 -- naive rate
power.translationFactorFU = 4/600 -- blast furnace = 4W = 4J/s; autosmelter = 10FP/t = 600FP/s

function power.sendEnergyTo(target, targetSocket, amount, testOnly)
  local sh = interop.getShared(target)
  if not sh.energyReceptor then return 0 end
  return sh.energyReceptor:receive(targetSocket, amount, testOnly)
end

function power.sendEnergy(socket, amount, testOnly)
  if not object.isOutputNodeConnected(socket) then return 0 end -- well of course
  if amount <= 0 then return 0 end -- why are you trying to send 0 anyway?
  if amount ~= amount then return 0 end -- let's not NaN, please
  -- try to distribute power as evenly as possible
  local conn = {}
  
  local i = 1
  
  -- build list
  for id, ts in pairs(object.getOutputNodeIds(socket)) do
    local sh = interop.getShared(id)
    if sh.energyReceptor then
      conn[i] = { receptor = sh.energyReceptor, socket = ts }
      i = i + 1
    end
  end
  
  -- probe each connection for max acceptance
  local total = 0
  for i, c in ipairs(conn) do
    c.maxTake = c.receptor:receive(c.socket, amount, true)
    total = total + c.maxTake
  end
  
  if total <= 0 or total ~= total then return 0 end -- don't NaN, thanks
  
  -- and send
  local tsend = math.min(total, amount)
  if testOnly then return tsend end -- or not, if this is set
  for i, c in ipairs(conn) do
    c.receptor:receive(c.socket, tsend * (c.maxTake / total))
  end
  return tsend
end

function power.autoSendEnergy(amount, testOnly)
  -- I suppose each socket should have its own I/O and not a shared rate limit across all of them
  for i = 0, object.outputNodeCount() - 1 do
    -- for now, just do it this way... clunky and strictly sequential, but much faster than doing two layers of what sendEnergy does
    shared.energyProvider:extract(i, power.sendEnergy(i, shared.energyProvider:extract(i, amount, true), testOnly), testOnly)
  end
end

-- object-side api - objects within shared table

-- float energyProvider:extract(int socket, float amount, bool testOnly) - returns amount successfully extracted

-- float energyReceptor:receive(int socket, float amount, bool testOnly) - returns amount successfully input
