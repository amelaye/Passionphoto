-- Mode « dev » (tools/server.sh) : exécute au nom d'un FAUX joueur les lignes de
-- <monde>/passionphoto_test_inbox.txt (« id<TAB>joueur<TAB>message ») et écrit le chat produit dans
-- <monde>/passionphoto_test_outbox.txt (« id<TAB>texte », puis « id<TAB>[fin] »).
-- Commandes /pptest_* (privilège server ; le faux joueur les a tous) : aides de développement.
local T = passionphoto_test

local WORLD = core.get_worldpath()
local INBOX = WORLD .. "/passionphoto_test_inbox.txt"
local OUTBOX = WORLD .. "/passionphoto_test_outbox.txt"

local offset = 0
local queue = {} -- { id, name, msg } en attente
local current = nil -- commande en cours : { id, name, holds }

local function clean(text)
	text = core.strip_colors(core.get_translated_string("fr", tostring(text)))
	return (text:gsub("\27.", ""):gsub("\r?\n", "\\n"))
end

local function out(id, text)
	local f = io.open(OUTBOX, "a")
	if not f then return end
	f:write(id, "\t", clean(text), "\n")
	f:close()
end

T.on_fake_chat = function(name, text)
	if current and current.name == name then out(current.id, text) end
end

local function finish_current()
	if current and current.holds <= 0 then
		out(current.id, "[fin]")
		current = nil
	end
end

--- Pour une commande asynchrone : retient « [fin] » ; appeler la fonction renvoyée quand c'est terminé.
function T.dev_hold()
	local c = current
	if not c then return function() end end
	c.holds = c.holds + 1
	local released = false
	return function()
		if released then return end
		released = true
		c.holds = c.holds - 1
		if current == c then core.after(0.2, finish_current) end
	end
end

local function ensure_player(name)
	if T.fakes[name] then return T.fakes[name] end
	local privs = {}
	for p in pairs(core.registered_privileges) do privs[p] = true end
	return T.new_fake_player(name, { pos = vector.new(0, 30, 0), privs = privs })
end

local function execute(id, name, msg)
	ensure_player(name)
	current = { id = id, name = name, holds = 0 }
	local ok, err = pcall(function()
		if msg:sub(1, 1) == "/" then
			local cmd, param = msg:match("^/(%S+)%s*(.*)$")
			local def = cmd and core.registered_chatcommands[cmd]
			if not def then return out(id, "commande inconnue : " .. msg) end
			if def.privs then
				local okp, missing = core.check_player_privs(name, def.privs)
				if not okp then return out(id, "privilèges manquants : " .. table.concat(missing, ", ")) end
			end
			local success, text = def.func(name, param or "")
			if text and text ~= "" then out(id, (success == false and "ÉCHEC : " or "") .. text) end
		else
			for _, f in ipairs(core.registered_on_chat_messages) do
				if f(name, msg) then break end
			end
		end
	end)
	if not ok then out(id, "ERREUR Lua : " .. tostring(err)) end
	core.after(0.2, finish_current)
end

local function poll()
	core.after(0.25, poll)
	local f = io.open(INBOX, "rb")
	if f then
		f:seek("set", offset)
		local data = f:read("*a") or ""
		f:close()
		local consumed = 0
		for line, pos in data:gmatch("([^\n]*)\n()") do
			consumed = pos - 1
			local id, name, msg = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
			if id then queue[#queue + 1] = { id = id, name = name, msg = msg } end
		end
		offset = offset + consumed
	end
	if not current and #queue > 0 then
		local l = table.remove(queue, 1)
		execute(l.id, l.name, l.msg)
	end
end

do -- ignorer d'éventuelles lignes d'une session précédente
	local f = io.open(INBOX, "rb")
	if f then
		offset = f:seek("end") or 0
		f:close()
	end
end
core.after(1, poll)

-------------------------------------------------------------------------------------------------------------
-- commandes de développement
-------------------------------------------------------------------------------------------------------------

local function fake_of(name)
	local f = T.fakes[name]
	if not f then return nil, "réservé au faux joueur de tools/server.sh cmd" end
	return f
end

local function deg(r) return math.floor(math.deg(r) * 10 + 0.5) / 10 end

local function describe(name, f)
	return ("%s : pieds %s, œil %s, lacet %s°, tangage %s°"):format(name, core.pos_to_string(f:get_pos(), 2),
		core.pos_to_string(f:test_eye_pos(), 2), deg(f:get_look_horizontal()), deg(f:get_look_vertical()))
end

local function reg(cmd, params, description, func)
	core.register_chatcommand(cmd, { params = params, description = "(dev) " .. description,
		privs = { server = true }, func = func })
end

reg("pptest_tp", "<x> <y> <z> [lacet° tangage°]", "place le faux joueur (pieds) et oriente son regard",
	function(name, param)
		local f, err = fake_of(name)
		if not f then return false, err end
		local x, y, z, yaw, pitch = param:match("^(%S+)%s+(%S+)%s+(%S+)%s*(%S*)%s*(%S*)$")
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		if not (x and y and z) then return false, "usage : /pptest_tp x y z [lacet° tangage°]" end
		f:set_pos(vector.new(x, y, z))
		if tonumber(yaw) then f:set_look_horizontal(math.rad(tonumber(yaw))) end
		if tonumber(pitch) then f:set_look_vertical(math.rad(tonumber(pitch))) end
		return true, describe(name, f)
	end)

reg("pptest_look", "<lacet°> <tangage°>", "oriente le regard (lacet 0 = +Z, 90 = -X ; tangage > 0 = vers le bas)",
	function(name, param)
		local f, err = fake_of(name)
		if not f then return false, err end
		local yaw, pitch = param:match("^(%S+)%s+(%S+)$")
		if not (tonumber(yaw) and tonumber(pitch)) then return false, "usage : /pptest_look lacet° tangage°" end
		f:set_look_horizontal(math.rad(tonumber(yaw)))
		f:set_look_vertical(math.rad(tonumber(pitch)))
		return true, describe(name, f)
	end)

reg("pptest_lookat", "<x> <y> <z>", "oriente le regard vers une position", function(name, param)
	local f, err = fake_of(name)
	if not f then return false, err end
	local p = core.string_to_pos("(" .. param:gsub("%s+", ",") .. ")")
	if not p then return false, "usage : /pptest_lookat x y z" end
	f:test_look_at(p)
	return true, describe(name, f)
end)

reg("pptest_where", "", "position, regard, nœud sous les pieds, lumière, heure", function(name)
	local f, err = fake_of(name)
	if not f then return false, err end
	local below = core.get_node(vector.round(vector.offset(f:get_pos(), 0, -0.5, 0)))
	return true, ("%s ; sous les pieds : %s ; lumière à l'œil : %s ; heure : %.3f"):format(describe(name, f),
		below.name, tostring(core.get_node_light(vector.round(f:test_eye_pos()))), core.get_timeofday())
end)

reg("pptest_ground", "<x> <z> [lacet° tangage°]", "génère la zone et pose le faux joueur sur le sol",
	function(name, param)
		local f, err = fake_of(name)
		if not f then return false, err end
		local x, z, yaw, pitch = param:match("^(%S+)%s+(%S+)%s*(%S*)%s*(%S*)$")
		x, z = tonumber(x), tonumber(z)
		if not (x and z) then return false, "usage : /pptest_ground x z [lacet° tangage°]" end
		x, z = math.floor(x + 0.5), math.floor(z + 0.5)
		local release = T.dev_hold()
		core.emerge_area(vector.new(x - 16, -48, z - 16), vector.new(x + 16, 112, z + 16), function(_, _, remaining)
			if remaining > 0 then return end
			local y = T.surface_y(x, z, 112, -48)
			if not y then
				core.chat_send_player(name, "pas de sol trouvé entre y=112 et y=-48")
			else
				f:set_pos(vector.new(x, y + 0.5, z))
				if tonumber(yaw) then f:set_look_horizontal(math.rad(tonumber(yaw))) end
				if tonumber(pitch) then f:set_look_vertical(math.rad(tonumber(pitch))) end
				core.chat_send_player(name, describe(name, f))
			end
			release()
		end)
		return true, "génération de la zone…"
	end)

reg("pptest_load", "[rayon]", "génère et charge la zone autour du faux joueur (défaut 96 nœuds) avant une photo",
	function(name, param)
		local f, err = fake_of(name)
		if not f then return false, err end
		local r = math.max(16, math.min(160, tonumber(param) or 96))
		local p = vector.round(f:get_pos())
		local release = T.dev_hold()
		local t0 = core.get_us_time()
		core.emerge_area(vector.offset(p, -r, -48, -r), vector.offset(p, r, 64, r), function(_, _, remaining)
			if remaining > 0 then return end
			core.chat_send_player(name, ("zone ±%d chargée en %.1f s"):format(r, (core.get_us_time() - t0) / 1e6))
			release()
		end)
		return true, "chargement…"
	end)

reg("pptest_scene", "<studio> [x y z]", "construit une scène de référence et place le faux joueur au point de vue",
	function(name, param)
		local f, err = fake_of(name)
		if not f then return false, err end
		local sname, rest = param:match("^(%S+)%s*(.*)$")
		local builder = sname and T.scenes[sname]
		if not builder or sname == "paysage" then return false, "scènes : studio" end
		local origin = vector.round(f:get_pos())
		if rest ~= "" then
			origin = core.string_to_pos("(" .. rest:gsub("%s+", ",") .. ")")
			if not origin then return false, "usage : /pptest_scene studio [x y z]" end
		end
		local release = T.dev_hold()
		local ctx = T.new_context("dev " .. sname, origin)
		T.run_in_coroutine(function()
			local view = builder(ctx)
			f:set_pos(vector.offset(view.eye, 0, -1.625, 0))
			f:set_look_horizontal(view.yaw)
			f:set_look_vertical(view.pitch)
		end, function(ok, e)
			if ok then
				core.chat_send_player(name, ("scène « %s » construite autour de %s ; %s"):format(sname,
					core.pos_to_string(origin), describe(name, f)))
			else
				core.chat_send_player(name, "ERREUR : " .. tostring(type(e) == "table" and e.msg or e))
			end
			release()
		end)
		return true, "construction…"
	end)

reg("pptest_probe", "[largeur] [hauteur] [fov°]", "SONDE de rendu depuis l'œil du faux joueur, exportée en PNG",
	function(name, param)
		local f, err = fake_of(name)
		if not f then return false, err end
		local w, h, fov = param:match("^(%d*)%s*(%d*)%s*(%d*)$")
		w = math.max(8, math.min(256, tonumber(w) or 64))
		h = math.max(8, math.min(256, tonumber(h) or w))
		fov = tonumber(fov) or 72
		local release = T.dev_hold()
		T.probe_render_async(f:test_eye_pos(), f:get_look_horizontal(), f:get_look_vertical(),
			{ w = w, h = h, fov = fov }, function(res)
				local base = ("sonde_%s_%dx%d"):format(os.date("%H%M%S"), w, h)
				local path = T.save_png(base, w, h, res.raw, { scale = math.max(1, math.floor(256 / w)) })
				core.chat_send_player(name, ("sonde %dx%d : %d rayons, %d ms de calcul (%d µs/rayon) → %s"):format(
					w, h, res.rays, math.floor(res.us / 1000), math.floor(res.us / res.rays), path))
				release()
			end)
		return true, "rendu en cours…"
	end)

reg("pptest_photo", "[taille] [ssaa 1|2] [fov°]", "rendu du MOD (textures) depuis l'œil du faux joueur → PNG",
	function(name, param)
		local f, err = fake_of(name)
		if not f then return false, err end
		local size, ss, fov = param:match("^(%d*)%s*(%d*)%s*(%d*)$")
		size = math.max(16, math.min(512, tonumber(size) or 256))
		ss = math.max(1, math.min(2, tonumber(ss) or 1))
		local job = passionphoto.render.raymarch.new_job(
			{ eye = f:test_eye_pos(), yaw = f:get_look_horizontal(), pitch = f:get_look_vertical() },
			{ w = size, ssaa = ss, fov = tonumber(fov) or 72 })
		local release = T.dev_hold()
		local steps = 0
		local function step()
			steps = steps + 1
			if not job.step(40000) then return core.after(0, step) end
			local res = job.result()
			local path = T.save_png(("photo_%s_%d%s"):format(os.date("%H%M%S"), size, ss > 1 and "_aa" or ""),
				res.w, res.h, res.raw)
			local st = passionphoto.render.textures.stats()
			core.chat_send_player(name, ("photo %d px (anticrénelage %d×%d) : %d ms de calcul sur %d pas serveur, "
				.. "%.1f µs/rayon ; textures décodées %d (%d ms) → %s"):format(size, ss, ss, math.floor(res.us / 1000),
				steps, res.us / res.rays, st.decoded, st.ms, path))
			release()
		end
		step()
		return true, "rendu en cours…"
	end)

reg("pptest_give", "<objet> [nombre]", "met un objet dans la main du faux joueur", function(name, param)
	local f, err = fake_of(name)
	if not f then return false, err end
	local item, n = param:match("^(%S+)%s*(%d*)$")
	if not item or not core.registered_items[item] then return false, "objet inconnu : " .. tostring(item) end
	f:set_wielded_item(ItemStack(item .. " " .. (tonumber(n) or 1)))
	return true, "en main : " .. f:get_wielded_item():to_string()
end)

local function dev_ctx(f)
	return T.new_context("dev", vector.round(f:get_pos()))
end

reg("pptest_use", "", "clic gauche avec l'objet tenu (on_use), rien de pointé", function(name)
	local f, err = fake_of(name)
	if not f then return false, err end
	local _, e = dev_ctx(f):use(f)
	return true, e or ("en main : " .. f:get_wielded_item():to_string())
end)

reg("pptest_secondary", "", "clic droit dans le vide (on_secondary_use)", function(name)
	local f, err = fake_of(name)
	if not f then return false, err end
	local _, e = dev_ctx(f):secondary_use(f)
	return true, e or ("en main : " .. f:get_wielded_item():to_string())
end)

reg("pptest_place", "<x> <y> <z>", "clic droit sur le dessus du nœud (on_place / on_rightclick)", function(name, param)
	local f, err = fake_of(name)
	if not f then return false, err end
	local p = core.string_to_pos("(" .. param:gsub("%s+", ",") .. ")")
	if not p then return false, "usage : /pptest_place x y z" end
	dev_ctx(f):place(f, p)
	return true, "en main : " .. f:get_wielded_item():to_string()
end)

reg("pptest_inv", "", "contenu de l'inventaire du faux joueur (clés de méta)", function(name)
	local f, err = fake_of(name)
	if not f then return false, err end
	local lines = {}
	for i, st in ipairs(f:get_inventory():get_list("main")) do
		if not st:is_empty() then
			local keys = {}
			for k in pairs(st:get_meta():to_table().fields) do keys[#keys + 1] = k end
			table.sort(keys)
			lines[#lines + 1] = ("%d : %s%s"):format(i, st:get_name() .. " " .. st:get_count(),
				#keys > 0 and (" [méta : " .. table.concat(keys, ", ") .. "]") or "")
		end
	end
	return true, #lines > 0 and table.concat(lines, "\n") or "inventaire vide"
end)

reg("pptest_formspec", "", "dernier formspec montré au faux joueur", function(name)
	local f, err = fake_of(name)
	if not f then return false, err end
	local list = f._state.formspecs
	local r = list[#list]
	if not r then return true, "aucun formspec montré" end
	return true, ("formname=%s\n%s"):format(r.formname, r.formspec)
end)

reg("pptest_fields", "<formname> [clé=valeur …]", "envoie des champs de formulaire comme le client",
	function(name, param)
		local f, err = fake_of(name)
		if not f then return false, err end
		local formname, rest = param:match("^(%S+)%s*(.*)$")
		if not formname then return false, "usage : /pptest_fields formname clé=valeur …" end
		local fields = {}
		for k, v in rest:gmatch("([^%s=]+)=(%S*)") do fields[k] = v end
		local handled = dev_ctx(f):submit(f, formname, fields)
		return true, handled and "formulaire traité" or "aucun callback n'a traité ce formulaire"
	end)

reg("pptest_lua", "<code>", "exécute du Lua dans le serveur (me = faux joueur, T = kit de test)",
	function(name, param)
		local fn, err = loadstring("return " .. param)
		if not fn then fn, err = loadstring(param) end
		if not fn then return false, "syntaxe : " .. tostring(err) end
		if setfenv then
			setfenv(fn, setmetatable({ T = T, me = T.fakes[name], name = name }, { __index = _G }))
		end
		local res = { pcall(fn) }
		if not res[1] then return false, tostring(res[2]) end
		local parts = {}
		for i = 2, table.maxn(res) do
			parts[#parts + 1] = type(res[i]) == "string" and res[i] or dump(res[i])
		end
		return true, #parts > 0 and table.concat(parts, "\t") or "(rien)"
	end)

T.log("mode dev : boîte de réception " .. INBOX)
