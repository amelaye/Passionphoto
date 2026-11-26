-- Contexte d'un scénario : monde, temps, contrôles, faux joueurs, objets, inventaires, formspecs, photos.
-- Toutes les positions prises ou rendues sont ABSOLUES ; ctx:p(x, y, z) convertit une position relative
-- à l'origine du scénario. check* note l'échec et continue, assert* arrête le scénario.
local T = passionphoto_test
local Ctx = {}
Ctx.__index = Ctx
T.Ctx = Ctx

T.AREA_RADIUS = 24 -- rayon (nœuds) de la zone d'un scénario autour de son origine

function T.new_context(name, origin)
	return setmetatable({
		name = name, origin = vector.copy(origin), messages = {}, metrics = {}, failures = {}, photos = {},
		forceloaded = {}, fakes = {}, cleanups = {},
	}, Ctx)
end

--- Exécute fn dans une coroutine ; chaque yield (ctx:wait) rend la main au serveur pendant `s` secondes.
-- on_done(ok, err, co) à la fin. Renvoie une fonction d'annulation.
function T.run_in_coroutine(fn, on_done)
	local co = coroutine.create(fn)
	local finished = false
	local function resume()
		if finished then return end
		local ok, res = coroutine.resume(co)
		if not ok then
			finished = true
			return on_done(false, res, co)
		end
		if coroutine.status(co) == "dead" then
			finished = true
			return on_done(true, nil, co)
		end
		core.after(tonumber(res) or 0, resume)
	end
	resume()
	return function() finished = true end
end

-------------------------------------------------------------------------------------------------------------
-- bases
-------------------------------------------------------------------------------------------------------------

function Ctx:p(x, y, z)
	return vector.add(self.origin, vector.new(x or 0, y or 0, z or 0))
end

function Ctx:log(msg)
	msg = tostring(msg)
	self.messages[#self.messages + 1] = msg
	T.log("      " .. self.name .. " : " .. msg)
end

--- Valeur nommée (nombre ou texte) : apparaît dans results.json et le journal.
function Ctx:metric(key, value)
	self.metrics[key] = value
	self:log(("mesure %s = %s"):format(key, tostring(value)))
end

--- Laisse passer `seconds` de temps serveur (le serveur continue de tourner).
function Ctx:wait(seconds)
	coroutine.yield(seconds or 0)
end

--- Interroge fn() toutes les `step` s jusqu'à une valeur vraie ou `timeout` s. Renvoie la valeur, ou nil.
function Ctx:wait_until(fn, timeout, step)
	step = step or 0.1
	local waited = 0
	while waited <= (timeout or 5) do
		local v = fn()
		if v then return v end
		self:wait(step)
		waited = waited + step
	end
	return nil
end

--- Abandonne le scénario sans échec (statut IGNORÉ), ex. « nécessite -g v7 ».
function Ctx:skip(reason)
	error({ __skip = true, msg = reason or "ignoré" }, 0)
end

-------------------------------------------------------------------------------------------------------------
-- contrôles
-------------------------------------------------------------------------------------------------------------

local function fmt(v)
	if type(v) == "table" then
		if v.x and v.y and v.z then return core.pos_to_string(v, 3) end
		return dump(v)
	end
	return tostring(v)
end
T.fmt = fmt

local function where()
	for level = 3, 14 do
		local info = debug.getinfo(level, "Sl")
		if not info then break end
		if info.what ~= "C" and info.short_src and not info.short_src:find("lib[/\\]ctx%.lua$") then
			return (info.short_src or "?") .. ":" .. (info.currentline or "?")
		end
	end
	return "?"
end

function Ctx:_fail(hard, msg)
	msg = msg .. " (" .. where() .. ")"
	self.failures[#self.failures + 1] = msg
	self:log("contrôle en échec : " .. msg)
	if hard then
		error({ __assert = true, msg = table.concat(self.failures, "\n") }, 0)
	end
end

function Ctx:_truthy(hard, cond, msg)
	if not cond then self:_fail(hard, msg or "valeur vraie attendue") end
	return cond
end

function Ctx:_eq(hard, actual, expected, msg)
	local same = actual == expected
	if type(actual) == "table" and type(expected) == "table" and actual.x and expected.x then
		same = vector.equals(actual, expected)
	end
	if not same then
		self:_fail(hard, ("%s : attendu %s, obtenu %s"):format(msg or "égalité", fmt(expected), fmt(actual)))
	end
	return same
end

function Ctx:_near(hard, actual, expected, tol, msg)
	local d
	if type(actual) == "table" then d = vector.distance(actual, expected) else d = math.abs(actual - expected) end
	if d > tol then
		self:_fail(hard, ("%s : attendu %s ±%s, obtenu %s"):format(msg or "proche", fmt(expected), tol, fmt(actual)))
		return false
	end
	return true
end

function Ctx:check(cond, msg) return self:_truthy(false, cond, msg) end
function Ctx:assert(cond, msg) return self:_truthy(true, cond, msg) end
function Ctx:check_eq(a, e, msg) return self:_eq(false, a, e, msg) end
function Ctx:assert_eq(a, e, msg) return self:_eq(true, a, e, msg) end
function Ctx:check_near(a, e, tol, msg) return self:_near(false, a, e, tol, msg) end
function Ctx:assert_near(a, e, tol, msg) return self:_near(true, a, e, tol, msg) end

--- Exécute fn(...) et note un échec s'il lève une erreur. Renvoie ok, résultats…
function Ctx:pcall(fn, msg, ...)
	local res = { pcall(fn, ...) }
	if not res[1] then self:_fail(false, (msg or "erreur inattendue") .. " : " .. tostring(res[2])) end
	return unpack(res, 1, table.maxn(res))
end

-------------------------------------------------------------------------------------------------------------
-- monde
-------------------------------------------------------------------------------------------------------------

--- Génère et charge de force la zone du scénario : minuteries de nœuds et entités tournent sans joueur.
-- Appelé automatiquement par set/fill et les scènes.
function Ctx:prepare(radius)
	if self.prepared then return end
	radius = radius or T.AREA_RADIUS
	local minp = vector.subtract(self.origin, radius)
	local maxp = vector.add(self.origin, radius)
	local done = false
	core.emerge_area(minp, maxp, function(_, _, remaining)
		if remaining == 0 then done = true end
	end)
	self:assert(self:wait_until(function() return done end, 30, 0.05), "emerge_area trop long")
	local bmin = vector.apply(minp, function(c) return math.floor(c / 16) end)
	local bmax = vector.apply(maxp, function(c) return math.floor(c / 16) end)
	for x = bmin.x, bmax.x do
		for y = bmin.y, bmax.y do
			for z = bmin.z, bmax.z do
				local bp = vector.new(x * 16, y * 16, z * 16)
				if core.forceload_block(bp, true) then self.forceloaded[#self.forceloaded + 1] = bp end
			end
		end
	end
	self.prepared = true
end

function Ctx:set(pos, name, param2)
	self:prepare()
	core.set_node(pos, { name = name, param2 = param2 or 0 })
end

function Ctx:get(pos) return core.get_node(pos) end
function Ctx:meta(pos) return core.get_meta(pos) end

--- Remplit un pavé (VoxelManip, rapide ; lumière recalculée). param2 facultatif.
function Ctx:fill(a, b, name, param2)
	self:prepare()
	local minp, maxp = vector.sort(a, b)
	local vm = core.get_voxel_manip()
	local e1, e2 = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new({ MinEdge = e1, MaxEdge = e2 })
	local data = vm:get_data()
	local p2 = param2 and vm:get_param2_data() or nil
	local cid = core.get_content_id(name)
	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				local i = area:index(x, y, z)
				data[i] = cid
				if p2 then p2[i] = param2 end
			end
		end
	end
	vm:set_data(data)
	if p2 then vm:set_param2_data(p2) end
	vm:write_to_map(true)
end

--- Écrit dans le journal chaque nœud non vide du pavé (aide au débogage).
function Ctx:dump_area(a, b)
	local minp, maxp = vector.sort(a, b)
	for x = minp.x, maxp.x do
		for y = minp.y, maxp.y do
			for z = minp.z, maxp.z do
				local pos = vector.new(x, y, z)
				local n = core.get_node(pos)
				if n.name ~= "air" and n.name ~= "ignore" then
					self:log(("%s %s p2=%d"):format(core.pos_to_string(vector.subtract(pos, self.origin)), n.name, n.param2))
				end
			end
		end
	end
end

--- Heure du jour (0 = minuit, 0.5 = midi). Remise à midi au nettoyage.
function Ctx:set_time(tod)
	core.set_timeofday(tod)
end

--- Protège un pavé pour tous sauf `owner` (core.is_protected intercepté, voir lib/intercept.lua).
function Ctx:protect(a, b, owner)
	local minp, maxp = vector.sort(a, b)
	T.protected[#T.protected + 1] = { minp = minp, maxp = maxp, owner = owner }
end

-------------------------------------------------------------------------------------------------------------
-- faux joueurs et objets
-------------------------------------------------------------------------------------------------------------

--- Faux joueur (lib/fake_player.lua), supprimé au nettoyage. opts.pos par défaut : origine du scénario.
function Ctx:fake_player(name, opts)
	opts = opts or {}
	name = name or ("testeur" .. (#self.fakes + 1))
	opts.pos = opts.pos or self.origin
	local f = T.new_fake_player(name, opts)
	self.fakes[#self.fakes + 1] = name
	return f
end

local function wielded(player)
	local stack = player:get_wielded_item()
	return stack, stack:get_definition()
end

local function keep(player, res)
	if res ~= nil then player:set_wielded_item(res) end
	return res
end

--- Clic gauche avec l'objet tenu (on_use). pointed : pointed_thing (défaut : rien de pointé).
function Ctx:use(player, pointed)
	local stack, def = wielded(player)
	if not def.on_use then return nil, "pas de on_use : " .. stack:get_name() end
	return keep(player, def.on_use(stack, player, pointed or { type = "nothing" }))
end

--- Clic droit dans le vide (on_secondary_use).
function Ctx:secondary_use(player, pointed)
	local stack, def = wielded(player)
	if not def.on_secondary_use then return nil, "pas de on_secondary_use : " .. stack:get_name() end
	return keep(player, def.on_secondary_use(stack, player, pointed or { type = "nothing" }))
end

--- Clic droit sur la face `above` du nœud `under` : on_place de l'objet (core.item_place par défaut, qui
-- appelle on_rightclick du nœud si le joueur ne s'accroupit pas), comme le moteur.
function Ctx:place(player, under, above)
	local stack, def = wielded(player)
	local pointed = { type = "node", under = under, above = above or vector.offset(under, 0, 1, 0) }
	return keep(player, (def.on_place or core.item_place)(stack, player, pointed))
end

--- on_rightclick du nœud, directement.
function Ctx:rightclick_node(player, pos)
	local node = core.get_node(pos)
	local def = core.registered_nodes[node.name]
	if not (def and def.on_rightclick) then return nil, "pas de on_rightclick : " .. node.name end
	local pointed = { type = "node", under = pos, above = vector.offset(pos, 0, 1, 0) }
	return keep(player, def.on_rightclick(pos, node, player, player:get_wielded_item(), pointed))
end

function Ctx:punch_node(player, pos)
	local node = core.get_node(pos)
	local def = core.registered_nodes[node.name] or {}
	local pointed = { type = "node", under = pos, above = vector.offset(pos, 0, 1, 0) }
	return (def.on_punch or core.node_punch)(pos, node, player, pointed)
end

--- Creuse comme un joueur (protection, can_dig, objets récupérés dans l'inventaire du faux joueur).
function Ctx:dig_node(player, pos)
	local node = core.get_node(pos)
	local def = core.registered_nodes[node.name] or {}
	return (def.on_dig or core.node_dig)(pos, node, player)
end

--- Commande de chat au nom d'un joueur (privilèges vérifiés). Renvoie ok, message.
function Ctx:command(player, cmd, param)
	local name = type(player) == "string" and player or player:get_player_name()
	local def = core.registered_chatcommands[cmd]
	if not def then return false, "commande inconnue : /" .. cmd end
	if def.privs then
		local ok, missing = core.check_player_privs(name, def.privs)
		if not ok then return false, "privilèges manquants : " .. table.concat(missing, ", ") end
	end
	return def.func(name, param or "")
end

-------------------------------------------------------------------------------------------------------------
-- inventaires de nœuds et détachés (comme le moteur : allow_* puis on_*)
-------------------------------------------------------------------------------------------------------------

function Ctx:inv(pos) return core.get_meta(pos):get_inventory() end

local function node_def(pos)
	return core.registered_nodes[core.get_node(pos).name] or {}
end

--- Le joueur dépose `stack` dans la case listname[index] du nœud. Renvoie le nombre accepté.
function Ctx:inv_put(player, pos, listname, index, stack)
	stack = ItemStack(stack)
	local def, inv = node_def(pos), self:inv(pos)
	local n = stack:get_count()
	if def.allow_metadata_inventory_put then n = def.allow_metadata_inventory_put(pos, listname, index, stack, player) end
	if n == -1 then n = stack:get_count() end
	if n <= 0 then return 0 end
	local put = ItemStack(stack)
	put:set_count(n)
	local cur = inv:get_stack(listname, index)
	if cur:is_empty() then
		inv:set_stack(listname, index, put)
	elseif cur:get_name() == put:get_name() and cur:get_meta():equals(put:get_meta()) then
		local left = cur:add_item(put)
		inv:set_stack(listname, index, cur)
		n = n - left:get_count()
	else
		return 0
	end
	if def.on_metadata_inventory_put then def.on_metadata_inventory_put(pos, listname, index, put, player) end
	return n
end

--- Le joueur prend `count` objets (défaut : tous) de la case ; ils vont dans son inventaire. Renvoie la pile prise.
function Ctx:inv_take(player, pos, listname, index, count)
	local def, inv = node_def(pos), self:inv(pos)
	local cur = inv:get_stack(listname, index)
	if cur:is_empty() then return ItemStack("") end
	local want = ItemStack(cur)
	want:set_count(math.min(count or cur:get_count(), cur:get_count()))
	local n = want:get_count()
	if def.allow_metadata_inventory_take then n = def.allow_metadata_inventory_take(pos, listname, index, want, player) end
	if n == -1 then n = want:get_count() end
	if n <= 0 then return ItemStack("") end
	local taken = cur:take_item(n)
	inv:set_stack(listname, index, cur)
	player:get_inventory():add_item("main", taken)
	if def.on_metadata_inventory_take then def.on_metadata_inventory_take(pos, listname, index, taken, player) end
	return taken
end

--- Déplacement interne au nœud. Renvoie le nombre déplacé.
function Ctx:inv_move(player, pos, from_list, from_index, to_list, to_index, count)
	local def, inv = node_def(pos), self:inv(pos)
	local src = inv:get_stack(from_list, from_index)
	count = math.min(count or src:get_count(), src:get_count())
	if count <= 0 then return 0 end
	if def.allow_metadata_inventory_move then
		count = def.allow_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	end
	if count <= 0 then return 0 end
	local moved = src:take_item(count)
	local dst = inv:get_stack(to_list, to_index)
	if not dst:is_empty() and dst:get_name() ~= moved:get_name() then return 0 end
	local left = dst:add_item(moved)
	inv:set_stack(from_list, from_index, src)
	inv:set_stack(to_list, to_index, dst)
	if not left:is_empty() then inv:add_item(from_list, left) end
	if def.on_metadata_inventory_move then
		def.on_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	end
	return count
end

--- Dépôt dans un inventaire détaché (callbacks allow_put / on_put de core.create_detached_inventory).
function Ctx:detached_put(player, inv_name, listname, index, stack)
	stack = ItemStack(stack)
	local cb = (core.detached_inventories or {})[inv_name] or {}
	local inv = core.get_inventory({ type = "detached", name = inv_name })
	if not inv then return 0 end
	local n = stack:get_count()
	if cb.allow_put then n = cb.allow_put(inv, listname, index, stack, player) end
	if n == -1 then n = stack:get_count() end
	if n <= 0 then return 0 end
	local put = ItemStack(stack)
	put:set_count(n)
	if not inv:get_stack(listname, index):is_empty() then return 0 end
	inv:set_stack(listname, index, put)
	if cb.on_put then cb.on_put(inv, listname, index, put, player) end
	return n
end

--- Retrait depuis un inventaire détaché (allow_take / on_take). Renvoie la pile prise.
function Ctx:detached_take(player, inv_name, listname, index, count)
	local cb = (core.detached_inventories or {})[inv_name] or {}
	local inv = core.get_inventory({ type = "detached", name = inv_name })
	if not inv then return ItemStack("") end
	local cur = inv:get_stack(listname, index)
	if cur:is_empty() then return ItemStack("") end
	local want = ItemStack(cur)
	want:set_count(math.min(count or cur:get_count(), cur:get_count()))
	local n = want:get_count()
	if cb.allow_take then n = cb.allow_take(inv, listname, index, want, player) end
	if n == -1 then n = want:get_count() end
	if n <= 0 then return ItemStack("") end
	local taken = cur:take_item(n)
	inv:set_stack(listname, index, cur)
	player:get_inventory():add_item("main", taken)
	if cb.on_take then cb.on_take(inv, listname, index, taken, player) end
	return taken
end

-------------------------------------------------------------------------------------------------------------
-- formspecs (montrées aux faux joueurs, voir lib/intercept.lua)
-------------------------------------------------------------------------------------------------------------

--- Dernier formspec montré au faux joueur : formspec, formname.
function Ctx:last_formspec(player)
	local list = player._state.formspecs
	local r = list[#list]
	if r then return r.formspec, r.formname end
end

--- Envoie des champs comme le client : callbacks register_on_player_receive_fields jusqu'au premier qui
-- renvoie true (comportement du moteur). Renvoie true si un callback a traité le formulaire.
function Ctx:submit(player, formname, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do
		if f(player, formname, fields) then return true end
	end
	return false
end

--- Formulaire d'un nœud (méta « formspec ») : on_receive_fields du nœud.
function Ctx:submit_node(player, pos, fields, formname)
	local def = node_def(pos)
	if not def.on_receive_fields then return nil, "pas de on_receive_fields" end
	return def.on_receive_fields(pos, formname or "", fields, player)
end

--- Éléments d'un formspec : liste de { type = "image", args = { "0,0", "4,4", "tex.png" } } (échappements
-- respectés, arguments non déséchappés). typ facultatif filtre par type.
function T.formspec_elements(fs, typ)
	local out, buf, esc = {}, {}, false
	for i = 1, #fs do
		local c = fs:sub(i, i)
		if esc then
			buf[#buf + 1] = c
			esc = false
		elseif c == "\\" then
			buf[#buf + 1] = c
			esc = true
		elseif c == "]" then
			local elem = table.concat(buf)
			buf = {}
			local t, rest = elem:match("^%s*([%w_]+)%[(.*)$")
			if t and (not typ or t == typ) then
				local args, a, e2 = {}, {}, false
				for j = 1, #rest do
					local ch = rest:sub(j, j)
					if e2 then a[#a + 1] = ch; e2 = false
					elseif ch == "\\" then a[#a + 1] = ch; e2 = true
					elseif ch == ";" then args[#args + 1] = table.concat(a); a = {}
					else a[#a + 1] = ch end
				end
				args[#args + 1] = table.concat(a)
				out[#out + 1] = { type = t, args = args }
			end
		else
			buf[#buf + 1] = c
		end
	end
	return out
end

--- Vrai si un élément de type `typ` contient `text` (recherche simple) dans ses arguments.
function T.formspec_has(fs, typ, text)
	for _, e in ipairs(T.formspec_elements(fs, typ)) do
		if not text or table.concat(e.args, ";"):find(text, 1, true) then return true end
	end
	return false
end

-------------------------------------------------------------------------------------------------------------
-- entités, effets enregistrés, photos
-------------------------------------------------------------------------------------------------------------

--- Entités Lua nommées `name` (toutes si nil) à moins de `radius` de pos.
function Ctx:find_entities(pos, radius, name)
	local out = {}
	for _, obj in ipairs(core.get_objects_inside_radius(pos, radius or 2)) do
		local ent = obj:get_luaentity()
		if ent and (not name or ent.name == name) then out[#out + 1] = obj end
	end
	return out
end

function Ctx:sounds() return T.rec.sounds end
function Ctx:media() return T.rec.media end
function Ctx:chat(player) return player._state.chat end

--- Enregistre une image (voir lib/png.lua) ; le chemin est listé dans results.json et le compte rendu.
function Ctx:save_png(name, w, h, pixels, opts)
	local path = T.save_png(T.slug(self.name) .. "__" .. name, w, h, pixels, opts)
	self.photos[#self.photos + 1] = path
	self:log("image " .. path)
	return path
end

--- Enregistre une texture « [png:… » ou un média dynamique envoyé par le mod.
function Ctx:save_texture(name, texture)
	local path, err = T.save_texture(T.slug(self.name) .. "__" .. name, texture)
	if path then
		self.photos[#self.photos + 1] = path
		self:log("image " .. path)
	end
	return path, err
end

-------------------------------------------------------------------------------------------------------------
-- nettoyage
-------------------------------------------------------------------------------------------------------------

function Ctx:on_cleanup(fn)
	self.cleanups[#self.cleanups + 1] = fn
end

function Ctx:cleanup()
	for i = #self.cleanups, 1, -1 do pcall(self.cleanups[i]) end
	for _, obj in ipairs(core.get_objects_inside_radius(self.origin, T.AREA_RADIUS * 2)) do
		if not obj:is_player() then obj:remove() end
	end
	for _, bp in ipairs(self.forceloaded) do core.forceload_free_block(bp, true) end
	for _, name in ipairs(self.fakes) do T.remove_fake_player(name) end
	T.protected = {}
	core.set_timeofday(0.5)
end
