-- Rendu des photos par le mod (src/render/) sur des scènes de référence : images exportées, mesures de temps,
-- de taille de PNG et de contenu. Comparer d'un passage à l'autre ; regarder les images (liens du compte rendu).
local T = passionphoto_test

local function shoot(ctx, label, view, opts)
	local res = passionphoto.render.raymarch.render(view, opts)
	local png = core.encode_png(res.w, res.h, res.raw, 9)
	local st = T.image_stats(res.w, res.h, res.raw)
	ctx:metric(label .. "_ms", math.floor(res.us / 1000))
	ctx:metric(label .. "_us_par_rayon", math.floor(res.us / res.rays * 10) / 10)
	ctx:metric(label .. "_png_ko", math.floor(#png / 102.4) / 10)
	ctx:metric(label .. "_couleurs", st.distinct)
	ctx:metric(label .. "_luminance", math.floor(st.mean_luma))
	ctx:save_png(label, res.w, res.h, res.raw)
	return res, st
end

T.register("rendu: studio texturé 128 px", function(ctx)
	local view = T.scenes.studio(ctx)
	ctx:wait(0.5)
	local _, st = shoot(ctx, "studio_128", view, { w = 128 })
	local tx = passionphoto.render.textures.stats()
	ctx:metric("textures_indexees", tx.indexed)
	ctx:metric("textures_decodees", tx.decoded)
	ctx:metric("textures_decodage_ms", tx.ms)
	ctx:check(tx.failed == 0, "aucune texture illisible")
	ctx:check(st.distinct >= 200, "image texturée (au moins 200 couleurs distinctes)")
end, { timeout = 120 })

T.register("rendu: studio texturé 256 px anticrénelé 2×2", function(ctx)
	local view = T.scenes.studio(ctx)
	ctx:wait(0.5)
	local _, st = shoot(ctx, "studio_256_aa", view, { w = 256, ssaa = 2 })
	ctx:check(st.distinct >= 500, "image détaillée (au moins 500 couleurs distinctes)")
end, { timeout = 180 })

T.register("rendu: studio de nuit éclairé par une torche, 256 px", function(ctx)
	local view = T.scenes.studio(ctx)
	ctx:set_time(0)
	ctx:wait(0.5)
	local _, night = shoot(ctx, "studio_nuit_256", view, { w = 256 })
	ctx:set_time(0.5)
	local day = T.image_stats(256, 256, passionphoto.render.raymarch.render(view, { w = 256 }).raw)
	ctx:check(night.mean_luma < day.mean_luma * 0.5, "la nuit est nettement plus sombre que le jour")
end, { timeout = 180 })

-- Point de vue repéré avec le serveur de dev (même graine 20261126) : bord de lac en forêt de feuillus, troncs
-- couchés, trembles, herbes hautes.
local SPOT = { x = 320, z = 360, yaw = 0, pitch = 8 }

T.register("rendu: paysage v7 256 px anticrénelé (-g v7)", function(ctx)
	if core.get_mapgen_setting("mg_name") == "singlenode" then
		ctx:skip("monde singlenode : relancer avec tools/headless/run.sh -g v7 -f paysage")
	end
	ctx:set_time(0.32) -- matin : lumière reproductible
	local view = T.scenes.paysage(ctx, SPOT)
	if not view then ctx:skip("pas de sol au point de vue (graine différente ?)") end
	ctx:metric("oeil", core.pos_to_string(view.eye, 1))
	local _, st = shoot(ctx, "paysage_256_aa", view, { w = 256, ssaa = 2, distance = 140 })
	ctx:check(st.distinct >= 300, "image détaillée")
end, { timeout = 240 })
