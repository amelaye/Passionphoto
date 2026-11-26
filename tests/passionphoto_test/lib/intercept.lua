-- Interceptions de fonctions moteur pour les FAUX joueurs (lib/fake_player.lua), et enregistrement des effets
-- observables (formspecs, chat, sons, médias dynamiques). Pour un vrai joueur, la vraie fonction est appelée.
-- Limite : seuls les appels faits via la table `core` AU MOMENT de l'appel sont vus ; le mod ne doit donc pas
-- mettre ces fonctions en cache dans des locales au chargement (CLAUDE.md §5).
local T = passionphoto_test

--- Enregistrements remis à zéro avant chaque scénario (T.reset_records).
function T.reset_records()
	T.rec = {
		formspecs = {}, -- { player, formname, formspec }
		closed = {}, -- { player, formname }
		chat = {}, -- { player, text } (messages privés aux faux joueurs)
		chat_all = {}, -- textes de core.chat_send_all
		sounds = {}, -- { name, params, ephemeral }
		media = {}, -- { filename, filepath, to_player, ephemeral, size, ok }
		media_data = {}, -- nom de fichier -> contenu (dynamic_add_media avec filedata)
		protection_violations = {}, -- { pos, name }
	}
end
T.reset_records()

T.protected = {} -- zones protégées de test : { minp, maxp, owner } (ctx:protect)

local function fake(name)
	return type(name) == "string" and T.fakes[name] or nil
end
function T.is_fake(name)
	return fake(name) ~= nil
end

local real = {}
for _, k in ipairs({ "get_player_by_name", "get_connected_players", "show_formspec", "close_formspec",
		"chat_send_player", "chat_send_all", "sound_play", "sound_stop", "sound_fade", "dynamic_add_media",
		"get_player_information", "check_player_privs", "get_player_privs", "is_protected",
		"record_protection_violation" }) do
	real[k] = core[k]
end
T.real = real

core.get_player_by_name = function(name)
	return fake(name) or real.get_player_by_name(name)
end

core.get_connected_players = function()
	local list = real.get_connected_players()
	local names = {}
	for n in pairs(T.fakes) do names[#names + 1] = n end
	table.sort(names)
	for _, n in ipairs(names) do list[#list + 1] = T.fakes[n] end
	return list
end

core.show_formspec = function(name, formname, formspec)
	local f = fake(name)
	if not f then return real.show_formspec(name, formname, formspec) end
	local r = { player = name, formname = formname, formspec = formspec }
	T.rec.formspecs[#T.rec.formspecs + 1] = r
	f._state.formspecs[#f._state.formspecs + 1] = r
	if T.on_fake_formspec then T.on_fake_formspec(name, formname, formspec) end
end

core.close_formspec = function(name, formname)
	if not fake(name) then return real.close_formspec(name, formname) end
	T.rec.closed[#T.rec.closed + 1] = { player = name, formname = formname }
end

core.chat_send_player = function(name, text)
	local f = fake(name)
	if not f then return real.chat_send_player(name, text) end
	T.rec.chat[#T.rec.chat + 1] = { player = name, text = text }
	f._state.chat[#f._state.chat + 1] = text
	if T.on_fake_chat then T.on_fake_chat(name, text) end
end

core.chat_send_all = function(text)
	T.rec.chat_all[#T.rec.chat_all + 1] = text
	if T.on_fake_chat then
		for n in pairs(T.fakes) do T.on_fake_chat(n, text) end
	end
	return real.chat_send_all(text)
end

-- Sons : toujours enregistrés ; un son destiné à un faux joueur n'est pas joué (poignée négative factice).
core.sound_play = function(spec, params, ephemeral)
	params = params or {}
	local sname = type(spec) == "table" and spec.name or spec
	T.rec.sounds[#T.rec.sounds + 1] = { name = sname, params = params, ephemeral = ephemeral }
	if params.to_player and fake(params.to_player) then
		if ephemeral then return nil end
		return -1
	end
	return real.sound_play(spec, params, ephemeral)
end
core.sound_stop = function(handle)
	if type(handle) == "number" and handle < 0 then return end
	return real.sound_stop(handle)
end
core.sound_fade = function(handle, step, gain)
	if type(handle) == "number" and handle < 0 then return end
	return real.sound_fade(handle, step, gain)
end

-- Médias dynamiques : vers un faux joueur, rien n'est envoyé et le callback est appelé comme si le client
-- avait reçu le fichier ; sinon, vrai appel (le moteur valide le fichier) et callback simulé pour les faux.
core.dynamic_add_media = function(options, callback)
	local r = { filename = options.filename, filepath = options.filepath, to_player = options.to_player,
		ephemeral = options.ephemeral, size = options.filedata and #options.filedata or nil }
	T.rec.media[#T.rec.media + 1] = r
	local fname = options.filename or (options.filepath and options.filepath:match("[^/\\]+$"))
	if options.filedata and fname then T.rec.media_data[fname] = options.filedata end
	if options.to_player and fake(options.to_player) then
		r.ok = true
		if callback then core.after(0.05, callback, options.to_player) end
		return true
	end
	local ok = real.dynamic_add_media(options, callback)
	r.ok = ok
	if ok and callback and not options.to_player then
		for n in pairs(T.fakes) do core.after(0.05, callback, n) end
	end
	return ok
end

core.get_player_information = function(name)
	local f = fake(name)
	if not f then return real.get_player_information(name) end
	return { address = "127.0.0.1", ip_version = 4, connection_uptime = 1, protocol_version = 48,
		formspec_version = 10, lang_code = f._state.lang, version_string = "faux joueur (passionphoto_test)" }
end

local function privs_list(...)
	local first = ...
	local list = {}
	if type(first) == "table" then
		for k, v in pairs(first) do
			if v then list[#list + 1] = k end
		end
	else
		list = { ... }
	end
	return list
end

core.check_player_privs = function(who, ...)
	local name = type(who) == "string" and who or (who and who.get_player_name and who:get_player_name())
	local f = fake(name)
	if not f then return real.check_player_privs(who, ...) end
	local missing = {}
	for _, p in ipairs(privs_list(...)) do
		if not f._state.privs[p] then missing[#missing + 1] = p end
	end
	return #missing == 0, missing
end

core.get_player_privs = function(name)
	local f = fake(name)
	if not f then return real.get_player_privs(name) end
	return table.copy(f._state.privs)
end

core.is_protected = function(pos, name)
	for _, a in ipairs(T.protected) do
		if pos.x >= a.minp.x and pos.x <= a.maxp.x and pos.y >= a.minp.y and pos.y <= a.maxp.y
				and pos.z >= a.minp.z and pos.z <= a.maxp.z and name ~= a.owner then
			return true
		end
	end
	return real.is_protected(pos, name)
end

core.record_protection_violation = function(pos, name)
	T.rec.protection_violations[#T.rec.protection_violations + 1] = { pos = vector.copy(pos), name = name }
	return real.record_protection_violation(pos, name)
end
