-- Chargement de passionphoto. À compléter à chaque étape : tout ce que le mod enregistre doit exister
-- (objets, nœuds, entités, recettes, commandes), voir skill passionphoto-testing.
local T = passionphoto_test

T.register("mod: passionphoto est chargé", function(ctx)
	ctx:assert(core.get_modpath("passionphoto"), "mod passionphoto présent")
	ctx:assert(type(passionphoto) == "table", "globale passionphoto")
	ctx:check(type(passionphoto.version) == "string", "passionphoto.version est une chaîne")
end)

T.register("mod: version identique dans init.lua et mod.conf", function(ctx)
	local f = io.open(core.get_modpath("passionphoto") .. "/mod.conf", "r")
	ctx:assert(f, "mod.conf lisible")
	local conf = f:read("*a")
	f:close()
	local v = conf:match("\nversion%s*=%s*([%w%.%-]+)")
	ctx:metric("version", v)
	ctx:check_eq(passionphoto.version, v, "passionphoto.version = version de mod.conf")
end)
