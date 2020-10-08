-- Use the movement gravity for the downwards direction. Get the setting rarely
local cached_gravity
local function get_gravity()
	if cached_gravity then
		return cached_gravity
	end
	cached_gravity = tonumber(core.settings:get("movement_gravity")) or 9.81
	core.after(50, function()
		cached_gravity = nil
	end)
	return cached_gravity
end

local neighbour_offsets = {
	{x=-1, y=0, z=0},
	{x=1, y=0, z=0},
	{x=0, y=0, z=-1},
	{x=0, y=0, z=1}
}
local neighbours_cache = {}
setmetatable(neighbours_cache, {__mode = "kv"})
local function get_neighbour_nodes(pos)
	-- Use previously found neighbours if they are not too old
	local vi = minetest.hash_node_position(pos)
	local t = minetest.get_us_time()
	if neighbours_cache[vi]
	and t - neighbours_cache[vi][1] < 10 * 1000000 then
		return neighbours_cache[vi][2]
	end
	local neighbours = {}
	for n = 1, 4 do
		local p = vector.add(pos, neighbour_offsets[n])
		neighbours[n] = p
		neighbours[n + 4] = minetest.get_node(p)
	end
	neighbours_cache[vi] = {t, neighbours}
	return neighbours
end

-- This function determines position to which the water flows
local function get_flow_target(pos)
	local neighbours = get_neighbour_nodes(pos)
	local param2 = minetest.get_node(pos).param2
	if param2 > 7 then
		return
	end
	for i = 1, 4 do
		-- If a neighbour has a lower height, flow to it
		local node = neighbours[i + 4]
		if node.name == "default:water_flowing"
		and node.param2 < param2 then
			return neighbours[i]
		end
	end
	for i = 1, 4 do
		-- TODO
		local node = neighbours[i + 4]
		if node.name == "default:water_flowing"
		and node.param2 >= 11 then
			return neighbours[i]
		end
	end
	for i = 1, 4 do
		-- TODO
		local node = neighbours[i + 4]
		if node.name ~= "default:water_flowing" then
			local def = minetest.registered_nodes[node.name]
			if def and not def.walkable then
				return neighbours[i]
			end
		end
	end
end

local item_entity = minetest.registered_entities["__builtin:item"]
local old_on_step = item_entity.on_step or function()end

item_entity.makes_footstep_sound = true
item_entity.bt_timer = 0
item_entity.on_step = function(self, dtime, ...)
	old_on_step(self, dtime, ...)

	--~ if not self.physical_state then
		--~ return
	--~ end

	-- Force-adjust an acceleration and/or velocity if needed
	if self.bt_acc
	and not vector.equals(self.object:get_acceleration(), self.bt_acc) then
		self.object:set_acceleration(self.bt_acc)
	end
	if self.bt_vel
	and not vector.equals(self.object:get_velocity(), self.bt_vel) then
		self.object:set_velocity(self.bt_vel)
	end

	-- TODO: was ist pyhsical state?
	if self.bt_phys ~= nil
	and self.physical_state ~= self.bt_phys then
		self.physical_state = self.bt_phys
		self.object:set_properties({
			physical = self.bt_phys
		})
	end

	-- For performance reasons, skip the remaining code except every second
	self.bt_timer = self.bt_timer + dtime
	if self.bt_timer < 1 then
		return
	end
	self.bt_timer = 0

	local p = self.object:get_pos()
	local pos = vector.round(p)

	local name = minetest.get_node(pos).name
	if name == "default:lava_flowing"
	or name == "default:lava_source" then
		-- TODO: more generic burn cases
		minetest.sound_play("builtin_item_lava", {pos=p})
		minetest.add_particlespawner({
			amount = 3,
			time = 0.1,
			minpos = {x=p.x, y=p.y, z=p.z},
			maxpos = {x=p.x, y=p.y+0.2, z=p.z},
			minacc = {x=-0.5,y=5,z=-0.5},
			maxacc = {x=0.5,y=5,z=0.5},
			minexptime = 0.1,
			minsize = 2,
			maxsize = 4,
			texture = "smoke_puff.png"
		})
		minetest.add_particlespawner ({
			amount = 1, time = 0.4,
			minpos = {x = p.x, y= p.y + 0.25, z= p.z},
			maxpos = {x = p.x, y= p.y + 0.5, z= p.z},
			minexptime = 0.2, maxexptime = 0.4,
			minsize = 4, maxsize = 6,
			collisiondetection = false,
			vertical = false,
			texture = "fire_basic_flame.png",
		})
		self.object:remove()
		return
	end

	local def = minetest.registered_nodes[name]
	if not def then
		return
	end
	-- Adjust the acceleration in liquid nodes
	self.bt_acc = nil
	self.bt_vel = nil
	if def.liquidtype then
		-- Set the strongest acceleration when we are in the middle of the node
		local acc_strength = 1.0 - ((p.y - 0.5) % 1.0) * 0.9
		local acc = {x = 0, y = -acc_strength * get_gravity(), z = 0}
		self.object:set_acceleration(acc)
		self.bt_acc = acc
	end
	if def.liquidtype ~= "flowing" then
		return
	end
	local vec = get_flow_target(pos)
	if not vec then
		return
	end
	local v = vector.add(
		self.object:get_velocity(),
		vector.multiply(vector.subtract(vec, pos),.5)
	)
	self.bt_vel = v
	self.object:set_velocity(v)
	self.physical_state = true
	self.bt_phys = true
	self.object:set_properties({
		physical = true
	})
end

minetest.register_entity(":__builtin:item", item_entity)
