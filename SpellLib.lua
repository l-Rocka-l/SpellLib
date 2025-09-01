local spellcore = require('SpellAPI.SpellCore')

local spellib = {}
local hiddenSpells = {}
local movings = {}
local scalings = {}
local rotatings = {}


--- Yor spells have to have names (`spellName`).
--- Works only with arrows and tridents
---@param ... string spell names, which vanilla models have to be hidden
function spellib.hide_vanilla_model(...)
    local spellNames = {...}
    for _, name in ipairs(spellNames) do
        hiddenSpells[name] = true
    end
end

--- Yor spells have to have names (`spellName`).
--- Works only with arrows and tridents
---@param ... string spell names, which vanilla models have to be shown
function spellib.show_vanilla_model(...)
    local spellNames = {...}
    for _, name in ipairs(spellNames) do
        hiddenSpells[name] = nil
    end
end

--------------- Things for render functions ------------------------------

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

---------------------- models controls -----------------------------
function spellib.summon(model, pos, rot, scale)
    pos = pos or player:getPos()
    rot = rot or vec(0,0,0)
    scale = scale or vec(1,1,1)
	local copy = model:copy():moveTo(models):setParentType('WORLD'):setPos(pos*16):setRot(rot):setScale(scale):setVisible(true)
	return copy
end

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
---------------------- Other ---------------------------------------

local projectiles = spellcore.getProjectiles()
local function hide_vanilla_model(arrow)
    local uuid = arrow:getUUID()
    return projectiles[uuid] and hiddenSpells[projectiles[uuid]:getSpellName()]
end

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
---------------------- Events --------------------------------------
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

events.ARROW_RENDER:register(function (_, arrow)
    return hide_vanilla_model(arrow)
end)
events.TRIDENT_RENDER:register(function (_, trident)
    return hide_vanilla_model(trident)
end)

return spellib