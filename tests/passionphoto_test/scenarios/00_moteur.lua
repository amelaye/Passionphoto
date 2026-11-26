-- Capacités du moteur sur lesquelles repose le mod (docs/PLAN.md, « Faisabilité ») : à relancer en cas de
-- changement de version de Luanti. Aucun code de passionphoto n'est testé ici.
local T = passionphoto_test

local PNG_SIG = "\137PNG\r\n\26\n"

T.register("moteur: API nécessaires au mod présentes", function(ctx)
	ctx:metric("version", core.get_version().string)
	for _, f in ipairs({ "encode_png", "colorspec_to_bytes", "encode_base64", "decode_base64", "dynamic_add_media",
			"raycast", "get_node_light", "get_natural_light", "get_artificial_light", "time_to_day_night_ratio",
			"safe_file_write", "mkdir", "get_dir_list", "get_mod_storage", "register_lbm", "create_detached_inventory",
			"show_formspec", "get_player_window_information", "formspec_escape", "get_translator" }) do
		ctx:check(type(core[f]) == "function", "core." .. f .. " existe")
	end
	ctx:check(core.features.dynamic_add_media_table, "dynamic_add_media accepte une table d'options (5.5)")
	ctx:check(core.features.dynamic_add_media_filepath, "dynamic_add_media accepte filename/filedata (5.9)")
end)

T.register("moteur: encode_png et texture [png:", function(ctx)
	local raw = string.rep(core.colorspec_to_bytes("#ff8000"), 16)
	local png = core.encode_png(4, 4, raw, 9)
	ctx:check_eq(png:sub(1, 8), PNG_SIG, "signature PNG")
	ctx:check_eq(core.decode_base64(core.encode_base64(png)), png, "aller-retour base64")
	ctx:metric("png_4x4_octets", #png)
	-- taille d'une photo 64×64 bruitée (pire cas pour la compression) en [png:
	local parts = {}
	local rng = PcgRandom(42)
	for i = 1, 64 * 64 do
		parts[i] = string.char(rng:next(0, 255), rng:next(0, 255), rng:next(0, 255), 255)
	end
	local noisy = core.encode_png(64, 64, table.concat(parts), 9)
	ctx:metric("png_64x64_bruit_octets", #noisy)
	ctx:metric("texture_png_64x64_bruit_caracteres", #("[png:" .. core.encode_base64(noisy)))
end)

T.register("moteur: lecture des textures d'un autre mod (sécurité des mods activée)", function(ctx)
	ctx:check(core.settings:get_bool("secure.enable_security", true), "sécurité des mods activée")
	local mp = core.get_modpath("default")
	ctx:assert(mp, "mod default présent")
	local files = core.get_dir_list(mp .. "/textures", false) or {}
	ctx:metric("textures_default", #files)
	ctx:check(#files > 50, "get_dir_list liste les textures de default")
	local f = io.open(mp .. "/textures/default_stone.png", "rb")
	ctx:assert(f, "io.open en lecture d'une texture de default")
	local data = f:read("*a")
	f:close()
	ctx:check_eq(data:sub(1, 8), PNG_SIG, "contenu PNG lu")
	ctx:metric("default_stone_octets", #data)
	-- écriture hors du monde : doit être refusée
	local forbidden = mp .. "/textures/passionphoto_test_interdit.png"
	local okw, fw = pcall(io.open, forbidden, "wb")
	ctx:check(not (okw and fw), "écriture dans le dossier d'un autre mod refusée")
	if okw and fw then
		fw:close()
		os.remove(forbidden)
	end
	local wp = core.get_worldpath() .. "/passionphoto_test_ecriture.tmp"
	ctx:check(core.safe_file_write(wp, "ok"), "écriture dans le dossier du monde autorisée")
	os.remove(wp)
end)

T.register("moteur: raycast — normale de la face et liquides", function(ctx)
	local c = ctx:p(0, 5, 0)
	ctx:set(c, "default:stone")
	local function first(from, to, liquids)
		for pt in core.raycast(from, to, false, liquids) do
			if pt.type == "node" then return pt end
		end
	end
	local top = first(vector.offset(c, 0, 5, 0), c)
	ctx:assert(top, "le rayon vertical touche la pierre")
	ctx:check_eq(top.intersection_normal, vector.new(0, 1, 0), "normale de la face du dessus")
	ctx:check_near(top.intersection_point.y, c.y + 0.5, 0.01, "point d'impact sur la face du dessus")
	local side = first(vector.offset(c, 5, 0, 0), c)
	ctx:check_eq(side and side.intersection_normal, vector.new(1, 0, 0), "normale de la face est")
	ctx:set(vector.offset(c, 0, 1, 0), "default:water_source")
	local dry = first(vector.offset(c, 0, 5, 0), c, false)
	ctx:check_eq(dry and core.get_node(dry.under).name, "default:stone", "sans liquids, le rayon traverse l'eau")
	local wet = first(vector.offset(c, 0, 5, 0), c, true)
	ctx:check_eq(wet and core.get_node(wet.under).name, "default:water_source", "avec liquids, il touche l'eau")
end)

T.register("moteur: lumière naturelle et artificielle", function(ctx)
	local c = ctx:p(0, 5, 0)
	ctx:set(vector.offset(c, 0, -1, 0), "default:stone")
	ctx:wait(0.2)
	ctx:metric("naturelle_midi", core.get_natural_light(c, 0.5))
	ctx:metric("naturelle_minuit", core.get_natural_light(c, 0))
	ctx:check((core.get_natural_light(c, 0.5) or 0) >= 14, "plein jour à l'air libre : lumière naturelle ≥ 14")
	local box = ctx:p(6, 5, 0)
	ctx:fill(vector.offset(box, -2, -2, -2), vector.offset(box, 2, 2, 2), "default:stone")
	ctx:fill(vector.offset(box, -1, -1, -1), vector.offset(box, 1, 1, 1), "air")
	ctx:set(vector.offset(box, 0, -1, 0), "default:torch", 1)
	ctx:wait(0.5)
	local light = core.get_node_light(box) or 0
	ctx:metric("boite_fermee_torche", light)
	ctx:check(light >= 10, "la torche éclaire la boîte fermée")
	ctx:check_eq(core.get_natural_light(box, 0.5), 0, "aucune lumière du jour dans la boîte fermée")
	ctx:metric("boite_param1_artificielle", core.get_artificial_light(core.get_node(box).param1))
end)

T.register("moteur: dynamic_add_media accepte un PNG en mémoire", function(ctx)
	local png = core.encode_png(2, 2, string.rep(core.colorspec_to_bytes("#00ff00"), 4))
	local name = ("passionphoto_test_media_%d.png"):format(core.get_us_time())
	local ok = core.dynamic_add_media({ filename = name, filedata = png, ephemeral = false }, function() end)
	ctx:check(ok == true, "dynamic_add_media({filename, filedata}) renvoie true")
end)

T.register("moteur: sonde de rendu, un rayon par pixel (scène studio)", function(ctx)
	local view = T.scenes.studio(ctx)
	ctx:wait(0.5)
	local day = T.probe_render(view.eye, view.yaw, view.pitch, { w = 64, h = 64, fov = 72 })
	ctx:metric("64_rayons", day.rays)
	ctx:metric("64_ms", math.floor(day.us / 1000))
	ctx:metric("64_us_par_rayon", math.floor(day.us / day.rays))
	ctx:metric("64_couleurs", day.distinct)
	ctx:check(day.distinct >= 8, "l'image n'est pas uniforme")
	ctx:check(day.hits > day.rays / 4, "la scène occupe au moins un quart de l'image")
	ctx:save_png("jour_64", 64, 64, day.raw, { scale = 4 })
	local big = T.probe_render(view.eye, view.yaw, view.pitch, { w = 128, h = 128, fov = 72 })
	ctx:metric("128_ms", math.floor(big.us / 1000))
	ctx:metric("128_us_par_rayon", math.floor(big.us / big.rays))
	ctx:save_png("jour_128", 128, 128, big.raw, { scale = 2 })
	ctx:set_time(0)
	ctx:wait(0.2)
	local night = T.probe_render(view.eye, view.yaw, view.pitch, { w = 64, h = 64, fov = 72 })
	ctx:save_png("nuit_64", 64, 64, night.raw, { scale = 4 })
	ctx:metric("luminance_jour", math.floor(day.mean_luma))
	ctx:metric("luminance_nuit", math.floor(night.mean_luma))
	ctx:check(night.mean_luma < day.mean_luma, "la nuit est plus sombre que le jour")
end, { timeout = 90 })

T.register("moteur: sonde de rendu sur un vrai paysage (-g v7)", function(ctx)
	if core.get_mapgen_setting("mg_name") == "singlenode" then
		ctx:skip("monde singlenode : relancer avec tools/headless/run.sh -g v7 -f paysage")
	end
	local view = T.scenes.paysage(ctx)
	if not view then ctx:skip("pas de sol au centre de la zone (changer PP_SEED)") end
	ctx:metric("oeil", core.pos_to_string(view.eye, 1))
	local res = T.probe_render(view.eye, view.yaw, view.pitch, { w = 96, h = 96, fov = 72, distance = 128 })
	ctx:metric("96_ms", math.floor(res.us / 1000))
	ctx:metric("96_us_par_rayon", math.floor(res.us / res.rays))
	ctx:save_png("paysage_96", 96, 96, res.raw, { scale = 3 })
	ctx:check(res.distinct >= 8, "l'image n'est pas uniforme")
end, { timeout = 120 })
