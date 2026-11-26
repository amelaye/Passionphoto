-- Faux joueurs : une table qui imite l'ObjectRef d'un joueur connecté, pour les scénarios et le serveur de dev.
-- Méthodes connues : état réaliste (position, regard, inventaire détaché réel, méta, HUD, FOV, contrôles…).
-- Méthode inconnue : l'appel est noté dans fake._state.calls et renvoie nil (le code du mod ne plante pas).
-- Aides de test (absentes de l'API moteur) : préfixe test_ (test_set_controls, test_look_at, test_eye_pos).
-- Limites : pas de physique, pas de client (rien n'est affiché ni joué), pas d'attachement réel.
local T = passionphoto_test

-- Couleurs de ciel par défaut du moteur (approximation, pour get_sky(true) des faux joueurs).
local DEFAULT_SKY = {
	type = "regular", base_color = "#ffffff", clouds = true, fog = { fog_distance = -1, fog_start = -1 },
	sky_color = {
		day_sky = "#61b5f5", day_horizon = "#90d3f6", dawn_sky = "#b4bafa", dawn_horizon = "#bac1f0",
		night_sky = "#006bff", night_horizon = "#4090ff", indoors = "#646464",
		fog_sun_tint = "#f47d1d", fog_moon_tint = "#7f99cc", fog_tint_type = "default",
	},
}

local function new_meta()
	local data = {}
	local m = {}
	function m:get_string(k) return data[k] or "" end
	function m:set_string(k, v)
		if v == nil or v == "" then data[k] = nil else data[k] = tostring(v) end
	end
	function m:get(k) return data[k] end
	function m:get_int(k)
		local n = tonumber(data[k]) or 0
		return n >= 0 and math.floor(n) or math.ceil(n)
	end
	function m:set_int(k, v)
		local n = tonumber(v) or 0
		m:set_string(k, tostring(n >= 0 and math.floor(n) or math.ceil(n)))
	end
	function m:get_float(k) return tonumber(data[k]) or 0 end
	function m:set_float(k, v) m:set_string(k, tostring(tonumber(v) or 0)) end
	function m:contains(k) return data[k] ~= nil end
	function m:get_keys()
		local t = {}
		for k in pairs(data) do t[#t + 1] = k end
		table.sort(t)
		return t
	end
	function m:to_table() return { fields = table.copy(data) } end
	function m:from_table(t)
		data = {}
		for k, v in pairs(t and t.fields or {}) do data[k] = tostring(v) end
		return true
	end
	return m
end

local M = {} -- méthodes ; self._state contient l'état

function M:get_player_name() return self._state.name end
function M:is_player() return true end
function M:is_valid() return T.fakes[self._state.name] == self end
function M:get_pos() return vector.copy(self._state.pos) end
function M:set_pos(p) self._state.pos = vector.copy(p) end
function M:move_to(p) self._state.pos = vector.copy(p) end
function M:get_velocity() return vector.zero() end
function M:add_velocity() end

function M:get_look_dir()
	local yaw, pitch = self._state.yaw, self._state.pitch
	return vector.new(-math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch))
end
function M:get_look_horizontal() return self._state.yaw end
function M:set_look_horizontal(r) self._state.yaw = r % (2 * math.pi) end
function M:get_look_vertical() return self._state.pitch end
function M:set_look_vertical(r) self._state.pitch = math.max(-math.pi / 2, math.min(math.pi / 2, r)) end

function M:get_properties() return table.copy(self._state.props) end
function M:set_properties(t)
	for k, v in pairs(t or {}) do self._state.props[k] = v end
end
function M:get_eye_offset()
	local e = self._state.eye_offset
	return vector.copy(e[1]), vector.copy(e[2]), vector.copy(e[3])
end
function M:set_eye_offset(first, third, third_front)
	self._state.eye_offset = { first and vector.copy(first) or vector.zero(),
		third and vector.copy(third) or vector.zero(), third_front and vector.copy(third_front) or vector.zero() }
end
function M:get_fov()
	local f = self._state.fov
	return f[1], f[2], f[3]
end
function M:set_fov(fov, is_multiplier, transition_time)
	self._state.fov = { fov or 0, is_multiplier or false, transition_time or 0 }
end

function M:hud_add(def)
	local st = self._state
	local id = st.next_hud
	st.next_hud = id + 1
	st.huds[id] = table.copy(def)
	return id
end
function M:hud_remove(id) self._state.huds[id] = nil end
function M:hud_change(id, stat, value)
	local h = self._state.huds[id]
	if h then h[stat] = value end
end
function M:hud_get(id)
	local h = self._state.huds[id]
	return h and table.copy(h) or nil
end
function M:hud_get_all() return table.copy(self._state.huds) end
function M:hud_set_flags(flags)
	for k, v in pairs(flags or {}) do self._state.hud_flags[k] = v end
end
function M:hud_get_flags() return table.copy(self._state.hud_flags) end
function M:hud_get_hotbar_itemcount() return self._state.hotbar_itemcount end
function M:hud_set_hotbar_itemcount(n) self._state.hotbar_itemcount = n end

function M:get_player_control()
	local c = { up = false, down = false, left = false, right = false, jump = false, aux1 = false, sneak = false,
		dig = false, place = false, LMB = false, RMB = false, zoom = false, movement_x = 0, movement_y = 0 }
	for k, v in pairs(self._state.controls) do c[k] = v end
	c.LMB, c.RMB = c.dig, c.place
	return c
end
function M:get_player_control_bits() return 0 end

function M:get_meta() return self._state.meta end
function M:get_inventory() return self._state.inv end
function M:get_wield_list() return "main" end
function M:get_wield_index() return self._state.wield_index end
function M:get_wielded_item() return self._state.inv:get_stack("main", self._state.wield_index) end
function M:set_wielded_item(stack)
	self._state.inv:set_stack("main", self._state.wield_index, ItemStack(stack))
	return true
end

function M:get_hp() return self._state.hp end
function M:set_hp(hp) self._state.hp = hp end
function M:get_breath() return self._state.breath end
function M:set_breath(b) self._state.breath = b end

function M:get_attach()
	local a = self._state.attach
	if a then return a.parent, a.bone, a.position, a.rotation, a.forced_visible end
end
function M:set_attach(parent, bone, position, rotation, forced_visible)
	self._state.attach = { parent = parent, bone = bone, position = position, rotation = rotation,
		forced_visible = forced_visible }
end
function M:set_detach() self._state.attach = nil end
function M:get_children() return {} end

function M:get_sky(as_table)
	local s = self._state.sky
	if as_table then return table.copy(s) end
	return s.base_color, s.type, {}, s.clouds
end
function M:set_sky(p)
	for k, v in pairs(p or {}) do self._state.sky[k] = v end
end
function M:get_day_night_ratio() return self._state.day_night_ratio end
function M:override_day_night_ratio(r) self._state.day_night_ratio = r end
function M:get_lighting() return table.copy(self._state.lighting) end
function M:set_lighting(l)
	for k, v in pairs(l or {}) do self._state.lighting[k] = v end
end
function M:get_physics_override() return table.copy(self._state.physics) end
function M:set_physics_override(p)
	for k, v in pairs(p or {}) do self._state.physics[k] = v end
end
function M:get_luaentity() return nil end
function M:get_armor_groups() return { fleshy = 100 } end
function M:remove() end

-- Aides de test (pas dans l'API moteur)
function M:test_set_controls(t) self._state.controls = table.copy(t or {}) end
function M:test_set_wield_index(i) self._state.wield_index = i end
function M:test_eye_pos()
	local st = self._state
	return vector.add(vector.offset(st.pos, 0, st.props.eye_height or 1.625, 0), vector.divide(st.eye_offset[1], 10))
end
--- Oriente le regard vers une position (yaw, pitch calculés depuis l'œil).
function M:test_look_at(target)
	local d = vector.subtract(target, self:test_eye_pos())
	local len = vector.length(d)
	if len == 0 then return end
	local yaw = math.atan2(-d.x, d.z)
	if yaw < 0 then yaw = yaw + 2 * math.pi end
	self._state.yaw = yaw
	self._state.pitch = -math.asin(d.y / len)
end

--- Crée un faux joueur. opts : pos, yaw, pitch (radians), wield (objet en main), inv_size, privs (table),
-- lang (défaut "fr"), eye_height.
function T.new_fake_player(name, opts)
	opts = opts or {}
	assert(not T.fakes[name], "faux joueur déjà présent : " .. tostring(name))
	local inv_name = "passionphoto_test:" .. name
	local inv = core.create_detached_inventory(inv_name, {})
	inv:set_size("main", opts.inv_size or 32)
	inv:set_size("craft", 9)
	inv:set_width("craft", 3)
	local st = {
		name = name, pos = vector.copy(opts.pos or vector.zero()), yaw = opts.yaw or 0, pitch = opts.pitch or 0,
		wield_index = 1, inv = inv, inv_name = inv_name, meta = new_meta(),
		props = { eye_height = opts.eye_height or 1.625, zoom_fov = 0, visual = "mesh",
			collisionbox = { -0.3, 0, -0.3, 0.3, 1.7, 0.3 } },
		eye_offset = { vector.zero(), vector.zero(), vector.zero() },
		fov = { 0, false, 0 }, huds = {}, next_hud = 1, hotbar_itemcount = 8,
		hud_flags = { hotbar = true, healthbar = true, crosshair = true, wielditem = true, breathbar = true,
			minimap = false, minimap_radar = false, basic_debug = false, chat = true },
		controls = {}, privs = opts.privs or { interact = true, shout = true }, lang = opts.lang or "fr",
		formspecs = {}, chat = {}, calls = {}, hp = 20, breath = 10, sky = table.copy(DEFAULT_SKY),
		lighting = {}, physics = { speed = 1, jump = 1, gravity = 1 },
	}
	if opts.wield then inv:set_stack("main", 1, ItemStack(opts.wield)) end
	local fake = { _state = st, _fake = true }
	setmetatable(fake, { __index = function(_, k)
		local m = M[k]
		if m then return m end
		return function()
			st.calls[#st.calls + 1] = k
		end
	end })
	T.fakes[name] = fake
	return fake
end

function T.remove_fake_player(name)
	local f = T.fakes[name]
	if not f then return end
	core.remove_detached_inventory(f._state.inv_name)
	T.fakes[name] = nil
end
