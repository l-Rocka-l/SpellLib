local spellcore

-- Search for and require SpellCore library from all available paths
for _, path in ipairs(listFiles(nil, true)) do
    if path:sub(-9) == "SpellCore" then
        spellcore = require(path)
    end
end
assert(spellcore, "SpellCore not found. You can download it from GitHub")

local spellib = {}
local hiddenSpells = {}
local movings = {}
local scalings = {}
local rotatings = {}


--- Hides the vanilla Minecraft model for arrows and tridents belonging to specified spells.
---@param ... string Spell names whose vanilla models should be hidden
function spellib.hide_vanilla_model(...)
    local spellNames = {...}
    for _, name in ipairs(spellNames) do
        hiddenSpells[name] = true
    end
end

--- Shows the vanilla Minecraft model for arrows and tridents belonging to specified spells.
---@param ... string Spell names whose vanilla models should be shown
function spellib.show_vanilla_model(...)
    local spellNames = {...}
    for _, name in ipairs(spellNames) do
        hiddenSpells[name] = nil
    end
end

--------------- Render Utilities ------------------------------

--- Makes a model follow a projectile's position and rotation. Must be called continuously in render events.
---@param projectile table Projectile object to follow
---@param model model Model to position
---@param delta number Delta time from render event (0 to 1 indicating time between ticks)
---@param follow table Optional table with pos and rot multipliers. Set vector components to 0 to ignore following on that axis.
function spellib.follow(projectile, model, delta, follow)
    local follow = follow or {
        pos = vec(1, 1, 1),
        rot = vec(1, 1)
    }
    local newRot = projectile.__data.entity:getRot(delta)*follow.rot
    model:setVisible(true)
    model:setPos(projectile:getLastPos(delta)*follow.pos*16)
    model:setRot(newRot.x, 180+newRot.y, 0)
end

--- Executes a function at regular intervals along a projectile's path. Must be called continuously in render events.
---@param func function Function to execute (receives projectile, position, delta)
---@param projectile table Projectile object to track
---@param distance number Interval distance between function executions
---@param delta number Delta time from render event (0 to 1 indicating time between ticks)
---@param axis vector Optional axis filter vector to restrict effect to specific axes
function spellib.trailEffect(func, projectile, distance, delta, axis)
	axis = axis or vec(1,1,1)
	local pos = projectile:getPos(delta)
	if not projectile._pos then projectile._pos = pos end
	local _pos = projectile._pos
	local difference = ((pos - _pos)*axis)
	local times = math.floor(difference:length() / distance)
	if times >= 1 then
		local active_pos = nil
		local step = difference:clampLength(distance, distance)
		for i = 1, times do
			active_pos = _pos + i*step
			func(projectile, active_pos, delta)
		end
		projectile._pos = active_pos
	end
end

--- Creates a burst of particles with randomized velocities.
---@param particleID string Particle type ID (default: "dust 1 1 1 1")
---@param pos vector Position vector where particles spawn
---@param count number Number of particles (default: 20)
---@param maxSpeed number Maximum particle speed (default: 0.1)
---@param color vector Optional particle color
---@param lifetime number Particle lifetime in ticks (default: 20)
---@param gravity number Particle gravity (default: 0.3)
function spellib.puff(particleID, pos, count, maxSpeed, color, lifetime, gravity)
	count = count or 20
	maxSpeed = maxSpeed or .1
	for i = 1, count do
		local p = particles[particleID or "dust 1 1 1 1"]:spawn()
			:setPos(pos)
			:setLifetime(lifetime or 20)
			:setGravity(gravity or 0.3)
			:setPhysics(true)
			if color then
				p:setColor(color)
			end

		local vx = (math.random() * 2 - 1) * maxSpeed
		local vy = (math.random() * 2 - 1) * maxSpeed
		local vz = (math.random() * 2 - 1) * maxSpeed

		p:setVelocity(vx, vy, vz)
	end
end

---------------------- Model Controls -----------------------------

--- Creates a copy of a model in the world with specified transformation.
---@param model model Model to copy
---@param pos vector Position vector (default: player position)
---@param rotvector Rotation vector (default: vec(0,0,0))
---@param scale vector Scale vector (default: vec(1,1,1))
---@return model model Copied model object
function spellib.summon(model, pos, rot, scale)
    pos = pos or player:getPos()
    rot = rot or vec(0,0,0)
    scale = scale or vec(1,1,1)
	local copy = model:copy():moveTo(models):setParentType('WORLD'):setPos(pos*16):setRot(rot):setScale(scale):setVisible(true)
	return copy
end

--- Moves a model smoothly over time.
---@param model model Model to move
---@param offset number Movement offset vector
---@param time number Duration in ticks
---@param delta number Optional delta time
---@return model model The model object
function spellib.move(model, offset, time, delta)
    delta = delta or 0
    table.insert(movings,
        {startTime = world.getTime(delta),
        endTime = world.getTime(delta) + time,
        start = model:getPos(),
        finish = model:getPos() + offset*16,
        model = model
        } )
    return model
end

--- Scales a model smoothly over time.
---@param model model Model to scale
---@param offset vector Scale offset vector
---@param time number Duration in ticks
---@param delta number Optional delta time
---@return model model The model object
function spellib.scale(model, offset, time, delta)
    delta = delta or 0
    table.insert(scalings,
        {startTime = world.getTime(delta),
        endTime = world.getTime(delta) + time,
        start = model:getScale(),
        finish = model:getScale() + offset,
        model = model
        } )
    return model
end

--- Rotates a model smoothly over time.
---@param model model Model to rotate
---@param offset vector Rotation offset vector
---@param time number Duration in ticks
---@param delta number Optional delta time
---@return model model The model object
function spellib.rotate(model, offset, time, delta)
    delta = delta or 0
    table.insert(rotatings,
        {startTime = world.getTime(delta),
        endTime = world.getTime(delta) + time,
        start = model:getOffsetRot(),
        finish = model:getOffsetRot() + offset,
        model = model
        } )
    return model
end

---------------------- Other Utilities ---------------------------------------

local projectiles = spellcore.getProjectiles()

--- Internal function to check if vanilla model should be hidden for an arrow/trident
local function hide_vanilla_model(arrow)
    local uuid = arrow:getUUID()
    return projectiles[uuid] and hiddenSpells[projectiles[uuid]:getSpellName()]
end

--- Returns all effects from a potion entity.
---@param potion_entity EntityAPI The potion entity
---@param unified boolean If true, removes "long_" and "strong_" prefixes from effect names
---@return table effects Table of potion effects
function spellib.getPotionEffects(potion_entity, unified)
    local potion_contents = potion_entity:getNbt().Item.components['minecraft:potion_contents']
	if potion_contents.custom_effects then
		return potion_contents.custom_effects
	else
        if unified then
            return {{id = string.gsub(string.gsub(potion_contents.potion, 'long_', ''), 'strong_', '')}}
        end
        return {{id = potion_contents.potion}}
	end
end

--- Returns the primary effect from a potion entity.
---@param potion_entity EntityAPI The potion entity
---@param unified boolean If true, removes "long_" and "strong_" prefixes from effect names
---@return string effect Potion effect ID string
function spellib.getPotionEffect(potion_entity, unified)
    local potion_contents = potion_entity:getNbt().Item.components['minecraft:potion_contents']
	if potion_contents.custom_effects then
		return potion_contents.custom_effects[1].id
	else
		if unified then
            return string.gsub(string.gsub(potion_contents.potion, 'long_', ''), 'strong_', '')
        end
        return potion_contents.potion
	end
end

---------------------- Event Handlers --------------------------------------

-- Clean up completed transformations every tick
events.TICK:register(function(delta)
    local worldTime = world.getTime()
    for _, transformations in pairs({movings, rotatings, scalings}) do
        for key, value in pairs(transformations) do
            if worldTime >= value.endTime then
                transformations[key] = nil
            end
        end
    end
end)

-- Apply smooth transformations to models every frame
local transform = {'setPos', 'setOffsetRot', 'setScale'}
events.RENDER:register(function(delta)
    local worldTime = world.getTime(delta)
    for i, transformations in pairs({movings, rotatings, scalings}) do
        for _, value in pairs(transformations) do
            local progress = 1
            if worldTime < value.endTime then
                progress = (worldTime - value.startTime) / (value.endTime - value.startTime)
            end
            value.model[transform[i]](value.model, math.lerp(value.start, value.finish, progress))
        end
    end
end)

-- Handle vanilla arrow model visibility
events.ARROW_RENDER:register(function (_, arrow)
    return hide_vanilla_model(arrow)
end)

-- Handle vanilla trident model visibility
events.TRIDENT_RENDER:register(function (_, trident)
    return hide_vanilla_model(trident)
end)

return spellib
