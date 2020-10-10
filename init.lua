-- Use the movement gravity for the downwards acceleration.
-- The setting may change in-game but for simplicity we don't support this.
local movement_gravity = tonumber(core.settings:get("movement_gravity")) or 9.81

local function is_flowing_liquid(nodename)
	local def = minetest.registered_nodes[nodename]
	return def and def.liquidtype == "flowing"
end

-- get_flow_raw determines the fluid flow vector, or returns nothing if
-- the flow is zero
local neighbour_offsets = {
	{x=-1, y=0, z=0},
	{x=1, y=0, z=0},
	{x=0, y=0, z=-1},
	{x=0, y=0, z=1}
}
local function get_flow_raw(pos)
	-- FIXME: Do we need to treat nodes with special liquid_range differently?
	local param2 = minetest.get_node(pos).param2
	if param2 == 15 then
		-- The liquid has full height and flows downwards
		return
	end
	local neighbours = {}
	for n = 1, 4 do
		local p = vector.add(pos, neighbour_offsets[n])
		neighbours[n] = minetest.get_node(p)
	end
	if param2 < 8 then
		-- The liquid does not flow downwards
		for i = 1, 4 do
			-- Flow to a neighbouring free space if possible
			local node = neighbours[i]
			local def = minetest.registered_nodes[node.name]
			if def and not def.walkable and def.liquidtype == "none" then
				return neighbour_offsets[i]
			end
		end
		-- Find a liquid neighbour with lowest height
		local min_height_neig = param2
		local min_neighbour
		for i = 1, 4 do
			local node = neighbours[i]
			local height_neigh = node.param2 % 8
			if height_neigh < min_height_neig
			and is_flowing_liquid(node.name) then
				min_height_neig = height_neigh
				min_neighbour = neighbour_offsets[i]
			end
		end
		if min_neighbour then
			return min_neighbour
		end
		-- No free neighbour and no flowing liquid neighbour
	end
	-- The flowing liquid ends here in the XZ plane, so determine the
	-- flow from higher neighbour nodes
	local flow = {x = 0, y = 0, z = 0}
	for i = 1, 4 do
		local node = neighbours[i]
		local height_neigh = node.param2 % 8
		if is_flowing_liquid(node.name) then
			-- A higher liquid is coming from there
			flow = vector.subtract(flow, neighbour_offsets[i])
		end
	end
	return not vector.equals(flow, {x = 0, y = 0, z = 0}) and flow or nil
end

-- get_flow caches the results from get_flow_raw for 10 s
local flow_cache = {}
setmetatable(flow_cache, {__mode = "kv"})
local function get_flow(pos)
	local vi = minetest.hash_node_position(pos)
	local t = minetest.get_us_time()
	if flow_cache[vi]
	and t - flow_cache[vi][1] < 10 * 1000000 then
		return flow_cache[vi][2]
	end
	local flow = get_flow_raw(pos)
	flow_cache[vi] = {t, flow}
	return flow
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
	local flow = get_flow(pos)
	if not flow then
		return
	end
	local vel_current = vel_desired or self.object:get_velocity()
	local acc
	if vector.dot(vel_current, flow) < 1.0 then
		acc = vector.multiply(flow, 2.0)
	else
		-- The item is already accelerated by the fluids
		acc = {x = 0, y = 0, z = 0}
	end
	acc.y = -movement_gravity
	self.object:set_acceleration(acc)
	self.bt_reset_velocity = true
end

minetest.register_entity(":__builtin:item", item_entity)
