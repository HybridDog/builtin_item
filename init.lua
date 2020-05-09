local time = minetest.get_us_time()+10*1000000
local lastpos = {x=0, y=0, z=0}
local last_tab, always_test

if not core.get_gravity then
	local gravity,grav_updating = 10
	function core.get_gravity()
		if not grav_updating then
			gravity = tonumber(core.settings:get("movement_gravity")) or gravity
			grav_updating = true
			core.after(50, function()
				grav_updating = false
			end)
		end
		return gravity
	end
end

local function get_nodes(pos)
	if not always_test then
		local t = minetest.get_us_time()
		if vector.equals(pos, lastpos)
		and t-time < 10*1000000 then
			return last_tab
		end
		time = t
		lastpos = pos
		local near_objects = minetest.get_objects_inside_radius(pos, 1)
		if #near_objects >= 2 then
			always_test = true
			minetest.after(10, function() always_test = false end)
		end
	end
	local tab,n = {},1
	for i = -1,1,2 do
		for _,p in pairs({
			{x=pos.x+i, y=pos.y, z=pos.z},
			{x=pos.x, y=pos.y, z=pos.z+i}
		}) do
			tab[n] = {p, minetest.get_node(p)}
			n = n+1
		end
	end
	if not always_test then
		last_tab = tab
	end
	return tab
end

local function get_flowing_dir(pos)
	local data = get_nodes(pos)
	local param2 = minetest.get_node(pos).param2
	if param2 > 7 then
		return
	end
	for _,i in pairs(data) do
		local nd = i[2]
		local name = nd.name
		local par2 = nd.param2
		if name == "default:water_flowing"
		and par2 < param2 then
			return i[1]
		end
	end
	for _,i in pairs(data) do
		local nd = i[2]
		local name = nd.name
		local par2 = nd.param2
		if name == "default:water_flowing"
		and par2 >= 11 then
			return i[1]
		end
	end
	for _,i in pairs(data) do
		local nd = i[2]
		local name = nd.name
		local par2 = nd.param2
		local tmp = minetest.registered_nodes[name]
		if tmp
		and not tmp.walkable
		and name ~= "default:water_flowing" then
			return i[1]
		end
	end
end

local item_entity = minetest.registered_entities["__builtin:item"]
local old_on_step = item_entity.on_step or function()end

item_entity.makes_footstep_sound = true
item_entity.bt_timer = 0
item_entity.on_step = function(self, dtime, ...)
	old_on_step(self, dtime, ...)

	if self.bt_acc
	and not vector.equals(self.object:getacceleration(), self.bt_acc) then
		self.object:set_acceleration(self.bt_acc)
	end
	if self.bt_vel
	and not vector.equals(self.object:getvelocity(), self.bt_vel) then
		self.object:set_velocity(self.bt_vel)
	end
	if self.bt_phys ~= nil
	and self.physical_state ~= self.bt_phys then
		self.physical_state = self.bt_phys
		self.object:set_properties({
			physical = self.bt_phys
		})
	end

	self.bt_timer = self.bt_timer+dtime
	if self.bt_timer < 1 then
		return
	end
	self.bt_timer = 0

	local p = self.object:getpos()
	local pos = vector.round(p)

	local name = minetest.get_node(pos).name
	if name == "default:lava_flowing"
	or name == "default:lava_source" then -- update to newest default please
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

	local tmp = minetest.registered_nodes[name]
	if not tmp then
		return
	end
	local acc
	if tmp.liquidtype then
		acc = {x=0, y=core.get_gravity()*(((p.y-.5)%1)*.9-1), z=0}
		self.object:set_acceleration(acc)
		self.bt_acc = acc
	else
		self.bt_acc = nil
	end
	if tmp.liquidtype == "flowing" then
		local vec = get_flowing_dir(pos)
		if vec then
			local v = vector.add(
				self.object:getvelocity(),
				vector.multiply(vector.subtract(vec, pos),.5)
			)
			self.bt_vel = v
			self.object:set_velocity(v)
			self.physical_state = true
			self.bt_phys = true
			self.object:set_properties({
				physical = true
			})
			return
		end
	end
	self.bt_vel = nil
end

minetest.register_entity(":__builtin:item", item_entity)

if minetest.settings:get("log_mods") then
	minetest.log("action", "builtin_item loaded")
end
