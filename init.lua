-- Use the movement gravity for the downwards acceleration.
-- The setting may change in-game but for simplicity we don't support this.
local movement_gravity = tonumber(core.settings:get("movement_gravity")) or 9.81

-- get_flow_target_raw determines position to which the water flows, or returns
-- nothing if no target position was found
local neighbour_offsets = {
	{x=-1, y=0, z=0},
	{x=1, y=0, z=0},
	{x=0, y=0, z=-1},
	{x=0, y=0, z=1}
}
local function get_flow_target_raw(pos)
	local param2 = minetest.get_node(pos).param2
	if param2 > 7 then
		-- The liquid flows downwards
		return
	end
	local neighbours = {}
	for n = 1, 4 do
		local p = vector.add(pos, neighbour_offsets[n])
		neighbours[n] = p
		neighbours[n + 4] = minetest.get_node(p)
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
		-- Flow to a downwards-flowing neighbour if its height is not too small
		local node = neighbours[i + 4]
		if node.name == "default:water_flowing"
		and node.param2 >= 11 then
			return neighbours[i]
		end
	end
	for i = 1, 4 do
		-- Flow to a neighbouring unsolid node
		local node = neighbours[i + 4]
		if node.name ~= "default:water_flowing" then
			local def = minetest.registered_nodes[node.name]
			if def and not def.walkable then
				return neighbours[i]
			end
		end
	end
	-- No neighbour found
end

-- get_flow_target caches the results from get_flow_target_raw for 10 s
local flow_target_cache = {}
setmetatable(flow_target_cache, {__mode = "kv"})
local function get_flow_target(pos)
	local vi = minetest.hash_node_position(pos)
	local t = minetest.get_us_time()
	if flow_target_cache[vi]
	and t - flow_target_cache[vi][1] < 10 * 1000000 then
		return flow_target_cache[vi][2]
	end
	local flow_target = get_flow_target_raw(pos)
	flow_target_cache[vi] = {t, flow_target}
	return flow_target
end

local item_entity = minetest.registered_entities["__builtin:item"]
local old_on_step = item_entity.on_step

item_entity.makes_footstep_sound = true
-- The "bt_" prefix shows that the value comes from builtin_item
item_entity.bt_timer = 0
item_entity.on_step = function(self, dtime, ...)
	-- Remember the velocity before an original on_step can change it
	local vel_desired
	if self.bt_reset_velocity then
		vel_desired = self.object:get_velocity()
	end

	old_on_step(self, dtime, ...)

	-- Ignore the item if it should not interact with physics
	if not self.physical_state then
		return
	end

	-- Reset the velocity if needed
	if vel_desired
	and not vector.equals(self.object:get_velocity(), vel_desired) then
		self.object:set_velocity(vel_desired)
	end

	-- For performance reasons, skip the remaining code in frequent steps
	self.bt_timer = self.bt_timer + dtime
	if self.bt_timer < 0.1 then
		return
	end
	self.bt_timer = 0

	local p = self.object:get_pos()
	local pos = vector.round(p)
	local nodename = minetest.get_node(pos).name

	if self.bt_reset_velocity then
		-- Set the item acceleration to its default (changed again below)
		self.object:set_acceleration({x=0, y=-movement_gravity, z=0})
		self.bt_reset_velocity = nil
	end
	local def = minetest.registered_nodes[nodename]
	if not def or not def.liquidtype or def.liquidtype ~= "flowing" then
		return
	end
	local pos_next = get_flow_target(pos)
	if not pos_next then
		return
	end
	local vel_current = vel_desired or self.object:get_velocity()
	local acc = vector.multiply(vector.subtract(pos_next, pos), 2.0)
	if math.abs(vel_current.x) > 1.0 then
		acc.x = 0
	end
	if math.abs(vel_current.z) > 1.0 then
		acc.z = 0
	end
	acc.y = -movement_gravity
	self.object:set_acceleration(acc)
	self.bt_reset_velocity = true
end

minetest.register_entity(":__builtin:item", item_entity)
