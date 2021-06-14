-- input module for techs

require "/scripts/vec2.lua"

input = {
  key = { },
  keyLast = { },
  keyDown = { },
  keyUp = { },
  dir = {0, 0},
  dirN = {0, 0},
}

local _i = true
function input.update(p)
  if _i then _i = false
    --
    message.setHandler("stardustlib:getTechInput", function()
      return {
        key = input.key, keyDown = input.keyDown, keyUp = input.keyUp,
        dir = input.dir, dirN = input.dirN,
      }
    end)
  end
  local m = p.moves -- alias
  input.keyLast = input.key -- push back
  input.key = { -- assemble keys
    up = m.up, down = m.down, left = m.left, right = m.right,
    jump = m.jump, sprint = not m.run,
    t1 = m.special1, t2 = m.special2, t3 = m.special3,
    m1 = m.primaryFire, m2 = m.altFire,
  }
  for k in pairs(input.key) do
    input.keyDown[k] = input.key[k] and not input.keyLast[k]
    input.keyUp[k] = input.keyLast[k] and not input.key[k]
  end
  input.dir = { -- and provide both raw and normalized directional input vectors
    (input.key.right and 1 or 0) - (input.key.left and 1 or 0),
    (input.key.up and 1 or 0) - (input.key.down and 1 or 0)
  } input.dirN = vec2.norm(input.dir)
end
