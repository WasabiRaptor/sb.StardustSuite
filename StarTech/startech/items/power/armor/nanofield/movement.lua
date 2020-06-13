--

-- steal tweening from dynitem
require "/lib/stardust/dynitem.lua"
local tween = dynItem.tween
dynItem = nil

movement = { }

movement.prevVelocity = mcontroller.velocity()

local function towards(cur, target, max)
  max = math.abs(max)
  if max == 0 then return cur end
  if target == cur then return target end
  local diff = target - cur
  local sign = diff / math.abs(diff)
  return cur + math.min(math.abs(diff), max) * sign
end
local rotTowards = towards -- just an alias for now

do -- core private
  local cr, st
  local states = { }
  
  function movement.update(p)
    movement.zeroGPrev = movement.zeroG
    movement.zeroG = (world.gravity(mcontroller.position()) == 0) or status.statusProperty("fu_byosnogravity", false)
    
    if not st or not cr or coroutine.status(cr) == "dead" then movement.switchState("ground") end
    local f, err = coroutine.resume(cr)
    if not f then sb.logError(err) end
    
    movement.prevVelocity = mcontroller.velocity()
  end
  
  function movement.state(name)
    if not states[name] then states[name] = { } end
    return states[name]
  end
  
  function movement.switchState(name, ...)
    if not states[name] then return nil end
    local par = {...}
    local ocr, ost = cr, st
    cr, st = nil -- preclear
    
    local nst = setmetatable({ }, { __index = states[name] })
    st = nst -- this is a separate variable for capture purposes
    
    cr = coroutine.create(function()
      -- get state changes out of the way
      if ost and ost.uninit then ost:uninit() end
      if nst.init then nst:init(table.unpack(par)) end
      local r = { }
      while true do
        if r[1] then
          r = { r[1](nst, table.unpack(r, 2)) }
        else
          r = { (nst.main or coroutine.yield)(nst) }
        end
      end
    end)
    
    if coroutine.running() == ocr then
      local f, err = coroutine.resume(cr)
      if not f then sb.logError(err) end
      coroutine.yield()
    end
  end
  
  function movement.call(fn, ...) if st and type(st[fn]) == "function" then return st[fn](st, ...) end end
end

---     ---
--- --- ---
---     ---

do local s = movement.state("ground")
  function s:init()
    tech.setParentState()
    mcontroller.setRotation(0)
    mcontroller.clearControls()
    
    self.airJumps = 0
    
    self.sphereTap = 100
  end
  
  function s:uninit()
    
  end
  
  function s:onHardFall()
    movement.switchState("hardFall")
  end
  
  function s:main()
    --
    tech.setParentState() -- default to no state override
    
    if mcontroller.groundMovement() or mcontroller.liquidMovement() then self.airJumps = stats.stat.airJump end
    
    if input.keyDown.t1 then
      input.keyDown.t1 = false -- consume press
      if stats.elytra then
        movement.switchState("flight", true)
      end
    end
    self.sphereTap = self.sphereTap + 1
    if input.keyDown.down then
      sb.logInfo("sphere tap " .. self.sphereTap)
      if self.sphereTap < 12 then movement.switchState("sphere") end
      self.sphereTap = 0
    end
    if input.key.sprint then -- sprint instead of slow walk!
      local v = input.dir[1]
      if v ~= 0 then
        mcontroller.controlMove(v, true)
        mcontroller.controlModifiers({ speedModifier = stats.stat.sprint or 1 })
      end
      if input.keyDown.jump and mcontroller.onGround() then -- slight bunnyhop effect
        mcontroller.setXVelocity(mcontroller.velocity()[1] * (1 + (((stats.stat.sprint or 1) - 1)*0.5)))
      end
    end
    
    -- air jump, borrowed from Aetheri
    if not mcontroller.canJump()
    and not mcontroller.jumping()
    and not mcontroller.liquidMovement()
    --and mcontroller.yVelocity() < 0
    and input.keyDown.jump and self.airJumps >= 1 then
      if stats.drawEnergy(250, false, 25) then
        self.airJumps = self.airJumps - 1
        mcontroller.controlJump(true)
        mcontroller.setYVelocity(math.max(0, mcontroller.yVelocity()))
        mcontroller.controlParameters({ airForce = 1750.0 }) -- allow easier direction control during jump
        sound.play("/sfx/tech/tech_doublejump.ogg")
        tech.setParentState("Fall") -- animate a bit even when already rising
      else
        sound.play("/sfx/interface/energy_out2.ogg")
      end
    end
    
    if movement.zeroG and not movement.zeroGPrev and stats.elytra then movement.switchState("flight") end
    
    coroutine.yield()
  end
end

--- --- ---

do local s = movement.state("hardFall")
  function s:init()
    self.time = 0
    self.startingVelocity = movement.prevVelocity[1]
  end

  function s:uninit()
    mcontroller.clearControls()
    tech.setParentState()
  end

  function s:main()
    mcontroller.controlModifiers({ speedModifier = 0, normalGroundFriction = 0, ambulatingGroundFriction = 0 }) -- just a tiny bit of slide
    mcontroller.setXVelocity(movement.prevVelocity[1] * (1.0 - 5.0 * script.updateDt()))
    tech.setParentState("duck")
    for v in tween(0.333) do
      if not mcontroller.onGround() then break end
      if input.keyDown.jump then
        mcontroller.controlJump(5)
        mcontroller.setVelocity({self.startingVelocity * 2.5, -5})
        break
      end
    end
    movement.switchState("ground")
  end
end

--- --- ---

do local s = movement.state("sphere")
  function s:init()
    local ground = mcontroller.onGround()
    self.collisionPoly = { {-0.85, -0.45}, {-0.45, -0.85}, {0.45, -0.85}, {0.85, -0.45}, {0.85, 0.45}, {0.45, 0.85}, {-0.45, 0.85}, {-0.85, 0.45} }
    mcontroller.controlParameters({ collisionPoly = self.collisionPoly })
    
    local y = mcontroller.position()[2]-(26/16)
    mcontroller.setYPosition(y)
    self.yLock, self.yLockTime = y, ground and 10 or -1
    
    tech.setToolUsageSuppressed(true)
    tech.setParentHidden(true)
    self.ball = Prop.new(0)
    self.ball:setImage("/tech/distortionsphere/distortionsphere.png", "/tech/distortionsphere/distortionsphereglow.png")
    self.ball:setFrame(0)
    self.rot = 0.5
    sound.play("/sfx/tech/tech_sphere_transform.ogg")
  end

  function s:uninit()
    self.ball:discard()
    tech.setParentHidden(false)
    tech.setToolUsageSuppressed(false)
    sound.play("/sfx/tech/tech_sphere_transform.ogg")
    mcontroller.setYPosition(mcontroller.position()[2]+(27/16))
    mcontroller.clearControls()
  end
  
  function s:onHardFall()
    mcontroller.setXVelocity(movement.prevVelocity[1] * 2)
  end

  function s:main()
    if self.yLockTime >= 0 then
      mcontroller.setYPosition(self.yLock)
      mcontroller.setYVelocity(0.0)
      self.yLockTime = self.yLockTime - 1
    end
    if input.keyDown.t1 then -- unmorph
      input.keyDown.t1 = false -- consume press
      movement.switchState(movement.zeroG and "flight" or "ground")
    end
    mcontroller.clearControls()
    mcontroller.controlParameters({
      collisionPoly = self.collisionPoly,
      groundForce = 450,
      runSpeed = 25, walkSpeed = 25,
      normalGroundFriction = 0.75,
      ambulatingGroundFriction = 0.2,
      slopeSlidingFactor = 3.0,
    })
    self.rot = self.rot + mcontroller.xVelocity() * script.updateDt() * -2.0
    while self.rot < 0 do self.rot = self.rot + 8 end
    while self.rot >= 8 do self.rot = self.rot - 8 end
    self.ball:setFrame(math.floor(self.rot))
    
    if input.dir[1] == 0 and math.abs(mcontroller.xVelocity()) < 5 then mcontroller.setXVelocity(0) end
    
    coroutine.yield()
  end

end

--- --- ---

do local s = movement.state("flight")
  
  local wingDefaults = {
    flightSpeed = 25,
    boostSpeed = 55,
    idlePowerCost = 0,--25,
    flightPowerCost = 250,
    boostPowerCost = 1000,
    
    force = 1.0,
    boostForce = 1.0,
    
    forceMultAir = 1.0,
    forceMultSpace = 1.0,
    forceMultWater = 1.0,
    
    speedMultAir = 1.0,
    speedMultSpace = 1.0,
    speedMultWater = 1.0,
    
    heatAirIdle = 0.0000000001, -- prevent cooldown
    heatAirThrust = 1.0,
    heatAirBoost = 1.1,
    
    heatSpaceIdle = 0,
    heatSpaceThrust = 0,
    heatSpaceBoost = 0.0000000001, -- prevent cooldown
    
    heatWaterIdle = 0,
    heatWaterThrust = -0.05,
    heatWaterBoost = 0.2,
    
    energyColor = "ff0354",
    baseRotation = 0.0,
    imgFront = "elytra.png",
    imgBack = "elytra.png",
    
    soundActivate = "/sfx/objects/ancientlightplatform_on.ogg",
    soundDeactivate = "/sfx/objects/ancientlightplatform_off.ogg",
    soundThrust = "/sfx/npc/boss/kluexboss_vortex_windy.ogg",--"/sfx/objects/steel_elevator_loop.ogg",--"/sfx/tech/tech_sonicsphere_charge1.ogg",
    soundThrustVolume = 1.0,
    soundThrustPitch = 1.0,
    soundThrustBoostPitch = 1.22,
  }
  
  local vanityProp = {
    imgFront = "",
    imgBack = "",
    baseRotation = true,
    energyColor = true,
    
    soundActivate = "",
    soundDeactivate = "",
    soundThrust = "",
    soundThrustVolume = true,
    soundThrustPitch = true,
    soundThrustBoostPitch = true,
  }
  
  --[[ testing: Poptra
  wingDefaults.baseRotation = 0.3
  wingDefaults.soundThrust = "nyan.ogg"
  wingDefaults.soundThrustVolume = 0.45
  wingDefaults.soundThrustPitch = 0.9
  wingDefaults.soundThrustBoostPitch = 1.0
  --]]
  
  function s:init(summoned)
    self.hEff = 0
    self.vEff = 0
    
    self.stats = { } --wingDefaults
    util.mergeTable(self.stats, wingDefaults)
    local istats = itemutil.property(stats.elytra, "startech:elytraStats") or { }
    local vstats = stats.elytraVanity and itemutil.property(stats.elytraVanity, "startech:elytraStats") or istats
    local vitm = stats.elytraVanity or stats.elytra
    util.mergeTable(self.stats, istats)
    
    for k,v in pairs(vanityProp) do
      if type(v) == "string" then -- path
        if vstats[k] then
          self.stats[k] = itemutil.relativePath(vitm, vstats[k])
        else
          self.stats[k] = wingDefaults[k]
        end
      else
        self.stats[k] = vstats[k] or wingDefaults[k]
      end
    end
    
    if stats.buildHeat(0) then
      sound.play("/sfx/interface/energy_out2.ogg")
      return movement.switchState("ground")
    end
    
    if summoned then
      if not stats.drawEnergy(self.stats.boostPowerCost, true, 60) then -- out of power already
        sound.play("/sfx/interface/energy_out2.ogg")
        movement.switchState("ground")
      end
      self.summoned = true
      if mcontroller.groundMovement() then -- lift off ground a bit
        mcontroller.setYVelocity(12)
      end
    else -- if automatic, restore last frame's momentum (bypass FU's momentum kill)
      mcontroller.setVelocity(movement.prevVelocity)
    end
    
    local maxFuel = world.getProperty("ship.maxFuel")
    self.onShip = type(maxFuel) == "number" and maxFuel > 0
    --sb.logInfo("on ship: " .. (self.onShip and "true" or "false"))
    
    appearance.setWings(self.stats)
    appearance.setWingsVisible(true)
    sound.play(self.stats.soundActivate)
    self.thrustLoop = sound.newLoop(self.stats.soundThrust)
    
    -- temporarily kill problematic FR effects
    status.removeEphemeralEffect("swimboost2")
  end
  
  function s:uninit()
    tech.setParentState()
    mcontroller.setRotation(0)
    mcontroller.clearControls()
    
    appearance.setWingsVisible(false)
    self.thrustLoop:discard()
    sound.play(self.stats.soundDeactivate)
    appearance.setEnergyColor()
    
    -- restore FR effects
    world.sendEntityMessage(entity.id(), "playerext:reinstateFRStatus")
  end
  
  function s:updateEffectiveStats(sg)
    util.appendLists(sg, {
      -- glide effortlessly through most FU gases
      { stat = "gasImmunity", amount = 1.0 },
      { stat = "helium3Immunity", amount = 1.0 },
    })
  end
  
  -- couple functions from Aetheri
  local setPose = coroutine.wrap(function()
    local threshold = 1/6
    local t = 0.0
    local f = false
    while true do
      local a = ((vec2.mag(input.dirN) ~= 0 and vec2.dot(input.dirN, vec2.norm(mcontroller.velocity())) > 0) and 1.0 or -1.0) * script.updateDt()
      t = util.clamp(t + a/threshold, 0.0, 1.0)
      if t == 1.0 then f = true elseif t == 0.0 then f = false end
      if f then tech.setParentState("fly") else tech.setParentState() end
      coroutine.yield()
    end
  end)
  
  local function forceFacing(f)
    mcontroller.controlModifiers{movementSuppressed = false}
    mcontroller.controlFace(f)
    mcontroller.controlModifiers{movementSuppressed = true}
  end
  
  function s:main()
    mcontroller.clearControls()
    mcontroller.controlParameters{
      gravityEnabled = false,
      frictionEnabled = false,
      liquidImpedance = -100, -- full speed in water
      liquidBuoyancy = -1000, -- same as above
      groundForce = 0, airForce = 0, liquidForce = 0, -- disable default movement entirely
      maximumPlatformCorrection = 0.0,
      maximumPlatformCorrectionVelocityFactor = 0.0,
    }
    mcontroller.controlModifiers{ movementSuppressed = true } -- disable harder, and also don't paddle at the air
    if input.keyDown.t1 then
      input.keyDown.t1 = false -- consume press
      movement.switchState("ground")
    end
    
    local dt = script.updateDt()
    
    local statEnv = "Air"
    if movement.zeroG then
      statEnv = "Space"
    elseif mcontroller.liquidPercentage() > 0.25 then
      statEnv = "Water"
    end
    local speedMult = self.stats[string.format("speedMult%s", statEnv)]
    local forceMult = self.stats[string.format("forceMult%s", statEnv)]
    
    local boosting = input.key.sprint
    local thrustSpeed = (boosting and self.stats.boostSpeed or self.stats.flightSpeed) * speedMult
    if input.dir[1] ~= 0 or input.dir[2] ~= 0 then
      local cm = 1.0
      if movement.zeroG or self.onShip then cm = 0.1 elseif mcontroller.liquidMovement() then cm = 0.25 end
      if not stats.drawEnergy((boosting and self.stats.boostPowerCost or self.stats.flightPowerCost) * dt * cm) then movement.switchState("ground") end
    elseif not movement.zeroG and not mcontroller.liquidMovement() then
      if not stats.drawEnergy(self.stats.idlePowerCost * dt) then movement.switchState("ground") end
    end
    
    if input.dir[1] ~= 0 then forceFacing(input.dir[1]) end
    
    -- for now this is just taken straight from the Aetheri
    local sMult = self.stats.force * forceMult
    if boosting then sMult = sMult * self.stats.boostForce end
    local forceMult = util.lerp((1.0 - vec2.dot(input.dirN, vec2.norm(mcontroller.velocity()))) * 0.5, 0.5, 1.0)
    if vec2.mag(input.dirN) < 0.25 then forceMult = 0.25 end
    mcontroller.controlApproachVelocity(vec2.mul(input.dirN, thrustSpeed), 12500 * forceMult * sMult * dt)
    
    setPose()
    self.hEff = towards(self.hEff, util.clamp(mcontroller.velocity()[1] / 55, -1.0, 1.0), dt * 8)
    self.vEff = towards(self.vEff, util.clamp(mcontroller.velocity()[2] / 55, -1.0, 1.0), dt * 8)
    --local rot = util.clamp(mcontroller.velocity()[1] / -55, -1.0, 1.0)
    local rot = math.sin(self.hEff * -1 * math.pi * .45) / (.45*2)
    local targetRot = rot * math.pi * .09
    mcontroller.setRotation(rotTowards(mcontroller.rotation(), targetRot, math.pi * .09 * 8 * dt))
    
    local rot2 = self.hEff * -1 * mcontroller.facingDirection()
    if rot2 < 0 then -- less extra rotation when moving forwards
      rot2 = rot2 * 0.32
    else -- and a wing flare
      rot2 = rot2 * 1.7
    end
    rot2 = rot2 + self.vEff * 0.75
    
    -- sound
    self.thrustLoop:setVolume(self.stats.soundThrustVolume * util.clamp(vec2.mag(mcontroller.velocity()) / 20, 0.0, 1.0))
    local pitch = vec2.mag(mcontroller.velocity())
    if pitch <= 25 then
      pitch = util.lerp(util.clamp(pitch / 20, 0.0, self.stats.soundThrustPitch), 0.25, 1.0)
    else
      pitch = util.lerp(util.clamp((pitch - 25) / (45-25), 0.0, 1.0), self.stats.soundThrustPitch, self.stats.soundThrustBoostPitch)
    end
    self.thrustLoop:setPitch(pitch)
    
    appearance.positionWings(rot2)
    
    -- heat build
    local heatType = "Idle"
    if vec2.mag(input.dir) > 0 then
      heatType = boosting and "Boost" or "Thrust"
    end
    if stats.buildHeat(self.stats[string.format("heat%s%s", statEnv, heatType)] * dt) then
      movement.switchState("ground")
    end
    
    if not summoned and not movement.zeroG and movement.zeroGPrev then movement.switchState("ground") end
    
    coroutine.yield()
  end
end
