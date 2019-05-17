--

local railTypes = root.assetJson("/rails.config")
local function railCheck(pos)
  return railTypes[world.material(pos, "foreground")]
end
local function railCast(pos, dist)
  dist = dist or 0 -- allow single tile checks
  -- adjust starting position to center of tile
  local sp = { math.floor(pos[1]) + 0.5, math.floor(pos[2]) + 0.5 }
  for i = 0, math.ceil(dist) do
    local p = vec2.add(sp, {0, -i})
    local rail = railCheck(p)
    if rail then
      local res = { }
      local relX = pos[1] - sp[1]
      local y = math.ceil(p[2]) -- top of region
      local slope = 0
      if railCheck(vec2.add(p, {0, 1})) then -- rail directly above
        -- don't land on the middle of a vertical rail
        if not railCheck(vec2.add(p, {-1, 0})) and not railCheck(vec2.add(p, {1, 0})) then return false end
      elseif relX >= 0 then -- on the right
        if railCheck(vec2.add(p, {1, 1})) and not railCheck(vec2.add(p, {1, 2})) then slope = -1
        elseif railCheck(vec2.add(p, {1, 0})) then slope = 0
        elseif railCheck(vec2.add(p, {1, -1})) then slope = 1
        -- check back if blank edge
        elseif railCheck(vec2.add(p, {-1, 0})) then slope = 0
        elseif railCheck(vec2.add(p, {-1, -1})) then slope = -1
        elseif railCheck(vec2.add(p, {-1, 1})) and not railCheck(vec2.add(p, {-1, 2})) then slope = 1
        end
      else -- on the left
        if railCheck(vec2.add(p, {-1, 1})) and not railCheck(vec2.add(p, {-1, 2})) then slope = 1
        elseif railCheck(vec2.add(p, {-1, 0})) then slope = 0
        elseif railCheck(vec2.add(p, {-1, -1})) then slope = -1
        -- check back if blank edge
        elseif railCheck(vec2.add(p, {1, 0})) then slope = 0
        elseif railCheck(vec2.add(p, {1, -1})) then slope = 1
        elseif railCheck(vec2.add(p, {1, 1})) and not railCheck(vec2.add(p, {1, 2})) then slope = -1
        end
      end
      y = y - relX * slope
      res.slope = slope
      res.point = {pos[1], y}
      res.tilePos = p
      
      return res
      --return materialAt
    end
  end
  return false
end

movement = {
  states = { },
}
local currentState = { } -- internal
local stateData = { } -- stuff

function movement.enterState(id, ...)
  if currentState == movement.states[id] or not movement.states[id] then return nil end
  movement.callState("uninit", id)
  local prevState = currentState
  local prevStateData = stateData
  currentState = movement.states[id]
  stateData = { }
  movement.callState("init", prevState, prevStateData, ...)
end

function movement.callState(f, ...)
  if currentState[f] then return currentState[f](stateData, ...) end
end

function movement.update(p)
  movement.callState("update", p.dt) -- don't need to pass in p since input module exists
end

-- for now, states are just part of the movement module; this may change... eventually

movement.states.ground = { }
function movement.states.ground:init(_, _, giveAirJumps, sprinting)
  self.airJumps = giveAirJumps and stats.stat.airJumps or 0
  self.airJumpTimer = 0
  self.groundTimer = 0
  self.sprinting = sprinting
end

function movement.states.ground:uninit()
  --
end

function movement.states.ground:update(dt)
  tech.setParentState() -- clear
  mcontroller.setRotation(0)
  mcontroller.clearControls()
  mcontroller.controlModifiers { speedModifier = stats.stat.moveSpeed }
  
  if input.keyDown.t1 then
    mcontroller.setPosition(tech.aimPosition())
    mcontroller.setVelocity({0, 0})
  end
  
  -- check to initiate rail grind
  if not mcontroller.canJump() and input.key.sprint and input.key.down and mcontroller.yVelocity() <= 0 then
    local rc = railCast(vec2.add(mcontroller.position(), {0, -1.51}), 1)
    --rc = rc or railCast(vec2.add(mcontroller.position(), {mcontroller.xVelocity() * dt, -2.51}), 0)
    if rc then
      mcontroller.setPosition(vec2.add(rc.point, {0, 2.5})) -- snap to rail
      return movement.enterState("rail") -- and start grinding
    end
  end
  
  if mcontroller.canJump() then self.groundTimer = 0.2 end
  if false and self.groundTimer > 0 and input.dir[1] == 0 and input.dir[2] == -1 then
    tech.setParentState(input.key.down and "Duck" or "Stand")
    mcontroller.controlParameters { 
      normalGroundFriction = 0.75,
      ambulatingGroundFriction = 0.2,
      --slopeSlidingFactor = 500.0
    }
    local ck = { "Block", "Platform", "Dynamic" }
    local rcp = mcontroller.position()--vec2.add(mcontroller.position(), vec2.mul(mcontroller.velocity(), {dt, 0}))
    if world.lineCollision(vec2.add(rcp, {0, -1.5}), vec2.add(rcp, {0, -3}), {"Platform"}) then
      -- rail grind??
      self.groundTimer = 0.25
      mcontroller.setYVelocity(0)
    end
    local lp = vec2.add(rcp, {-0.5, -1})
    local rp = vec2.add(rcp, {0.5, -1})
    local lc = world.lineCollision(lp, vec2.add(lp, {0, -5}), ck)
    local rc = world.lineCollision(rp, vec2.add(rp, {0, -5}), ck)
    if lc and rc then
      local sf = (lc[2] - rc[2]) * 1.5
      mcontroller.addMomentum({sf, math.abs(sf) * -0})
      if sf * mcontroller.xVelocity() > -0.2 then -- if going downhill already...
        mcontroller.setYPosition(util.lerp(0.5, lc[2], rc[2]) + 2.5) -- stick to the ground
      end
    end
  end
  
  if mcontroller.onGround() then
    self.sprinting = input.key.sprint and input.dir[1] ~= 0
    self.airJumps = stats.stat.airJumps
    self.airJumpTimer = 0
  end
  if self.sprinting then
    mcontroller.controlMove(input.dir[1], true) -- set running
    -- sprint speed and a bit of a jump boost
    mcontroller.controlModifiers { speedModifier = stats.stat.sprintSpeed, airJumpModifier = 1.35 }
  end
  
  -- air jump!
  if not mcontroller.canJump()
  and not mcontroller.jumping()
  and not mcontroller.liquidMovement()
  --and mcontroller.yVelocity() < 0
  and input.keyDown.jump and self.airJumps >= 1 then
    self.airJumps = self.airJumps - 1
    mcontroller.controlJump(true)
    mcontroller.setYVelocity(math.max(0, mcontroller.yVelocity()))
    mcontroller.controlParameters({ airForce = 1750.0 }) -- allow easier direction control during jump
    self.sprinting = self.sprinting or (input.key.sprint and input.dir[1] ~= 0) -- allow starting a sprint from an air jump
    sound.play("/sfx/tech/tech_doublejump.ogg")
    -- TODO: particle/animation stuff
    tech.setParentState("Fall") -- animate a bit even when already rising
    self.airJumpTimer = 0.05
  end
  
  if self.groundTimer > 0 then self.groundTimer = self.groundTimer - dt end
  
  if self.airJumpTimer > 0 then 
    -- ?
    self.airJumpTimer = self.airJumpTimer - dt
  end
  
end

do
  local function offsetForRot(rot)
    return (math.cos(rot) - 1) * -4, (math.sin(rot)) * -1.5
  end
  
  local function towards(cur, target, max)
    max = math.abs(max)
    if max == 0 then return cur end
    if target == cur then return target end
    local diff = target - cur
    local sign = diff / math.abs(diff)
    return cur + math.min(math.abs(diff), max) * sign
  end
  
  local function rotateTowards(self, rot, dt)
    local curRot = mcontroller.rotation()
    local limit = util.clamp(math.pi * 2 * dt, 0.025, math.abs(curRot - rot) / 2)
    local curYOffset = self.yOffset
    local curXOffset = self.xOffset
    local newRot = towards(curRot, rot, limit)
    self.yOffset, self.xOffset = offsetForRot(newRot)
    mcontroller.setRotation(newRot)
    mcontroller.setYPosition(mcontroller.yPosition() + self.yOffset - curYOffset)
    mcontroller.setXPosition(mcontroller.xPosition() + self.xOffset - curXOffset)
    --
  end
  
  movement.states.rail = { }
  function movement.states.rail:init()
    self.xOffset = 0
    self.yOffset = 0
    self.lastSlope = 0
    sound.play("/aetheri/sfx/railGrindHit.ogg", 0.64, 1.1)
    self.sfx = sound.newLoop("/aetheri/sfx/railGrindLoop.ogg")
    
    -- stuff
    local rc = railCast(vec2.add(mcontroller.position(), {0, -2.51 - self.yOffset}), 2)
    if rc then
      mcontroller.setVelocity(vec2.rotate(mcontroller.velocity(), math.pi * rc.slope * 0.25))
      rotateTowards(self, math.pi * rc.slope * -0.25, 10000)
    end
  end
  
  function movement.states.rail:uninit()
    self.sfx:discard()
    --mcontroller.setYVelocity(mcontroller.yVelocity() + mcontroller.xVelocity() * self.lastSlope * -1)
    local vel = mcontroller.velocity()
    vel[2] = math.max(0, vel[2])
    vel = vec2.mul(vec2.rotate(vel, math.pi * self.lastSlope * -0.25), {1, 1})
    mcontroller.setVelocity(vel)
    --if vel[2] > 0 and not self.forceJump then mcontroller.controlJump(true) end
  end
  
  function movement.states.rail:update(dt)
    mcontroller.clearControls()
    mcontroller.controlDown() -- always slip through crossing platforms
    mcontroller.controlParameters {
      bounceFactor = 0.75, -- bounce off le walls
    }
    
    if input.keyDown.jump then -- jump off
      mcontroller.addMomentum({0, 75})
      self.forceJump = true
      return movement.enterState("ground", true, true)
    end
    -- drop off rail if you release sprint unless standing stationary on a flat rail
    if mcontroller.xVelocity() == 0 and not input.key.down then --nop--
    elseif not input.key.sprint then return movement.enterState("ground", true, true) end
    
    -- TODO: avoid snapping to rails 2 blocks above when a horizontal rail ends(!?)
    -- maybe use an iterative follow system (start with last rail stopped on, follow each tile space in its
    -- direction until you arrive at current x position)
    local lift = math.abs(mcontroller.xVelocity()) * dt --math.abs(mcontroller.xVelocity()) > 10 and 0.2 or 0
    lift = input.key.down and 0 or lift + math.abs(self.lastSlope)--util.clamp(math.abs(mcontroller.xVelocity() * self.lastSlope) * 10000, 0, 1)
    local castLen = 1 + math.abs(lift) + math.abs(self.lastSlope)
    local rc = railCast(vec2.add(mcontroller.position(), {-self.xOffset, lift - 2.51 - self.yOffset}), castLen)
    if not rc then rc = railCast(vec2.add(mcontroller.position(), {-self.xOffset, lift - 0.51 - self.yOffset}), castLen) end
    if rc then
      tech.setParentState("Duck")
      mcontroller.setYVelocity(0)
      mcontroller.setYPosition(rc.point[2] + 2.4 + (1/16)*self.yOffset)
      mcontroller.addMomentum({rc.slope * dt * (input.key.down and 100 or 80), 0})
      mcontroller.addMomentum({input.dir[1] * dt * (rc.slope == 0 and 30 or 15), 0})
      if rc.slope == 0 and input.dir[1] == 0 and math.abs(mcontroller.xVelocity()) <= 2.5 then
        mcontroller.setXVelocity(0) -- help stop on flat rails
        if not input.key.down then tech.setParentState("Stand") end -- and allow standing up if stationary
      end
      rotateTowards(self, math.pi * rc.slope * -0.25, dt)
      self.lastSlope = rc.slope
    else -- no rail!
      return movement.enterState("ground", true, true)
    end
    
    local speed = math.abs(mcontroller.xVelocity())
    speed = math.min(1, speed / 25)
    self.sfx:setVolume(speed * 0.5)
    self.sfx:setPitch(1)
  end
end


















-- EOF --
