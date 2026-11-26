-- Passion Photo (passionphoto) — photographie argentique pour Amelaye in Minerland.
-- En cours : outillage en place, moteur de rendu des photos (étape 2) ; le reste arrive par étapes (docs/PLAN.md).
-- init.lua ne fait que charger les modules dans l'ordre (CLAUDE.md §4).

local modpath = core.get_modpath(core.get_current_modname())

passionphoto = {
	version = "0.1.0", -- identique à mod.conf (vérifié par le scénario « mod: version »)
	modpath = modpath,
}

-- logique pure (testée sous LuaJIT : tests/unit/)
passionphoto.png = dofile(modpath .. "/src/lib/png.lua")
passionphoto.texstring = dofile(modpath .. "/src/lib/texstring.lua")

-- rendu des photos (skill photo-render)
passionphoto.render = {}
passionphoto.render.textures = dofile(modpath .. "/src/render/textures.lua")
passionphoto.render.nodes = dofile(modpath .. "/src/render/nodes.lua")
passionphoto.render.raymarch = dofile(modpath .. "/src/render/raymarch.lua")

core.log("action", "[passionphoto] " .. passionphoto.version .. " chargé (rendu en développement, voir docs/PLAN.md)")
