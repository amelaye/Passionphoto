-- Configuration luacheck (https://github.com/lunarmodules/luacheck)
std = "luajit"
max_line_length = 120
max_string_line_length = false
unused_args = false
allow_defined_top = false

-- seule globale du mod (CLAUDE.md §4)
globals = { "passionphoto" }

read_globals = {
	"core", "minetest", "vector", "dump", "dump2", "ItemStack", "VoxelArea", "VoxelManip",
	"PcgRandom", "PseudoRandom", "PerlinNoise", "Settings", "AreaStore",
	string = { fields = { "split", "trim" } },
	table = { fields = { "copy", "indexof", "insert_all", "key_value_swap", "shuffle" } },
	math = { fields = { "hypot", "sign", "round" } },
	-- mods facultatifs (lecture seule) : à compléter quand une intégration est ajoutée
	"default", "dye", "unified_inventory", "unifieddyes",
}

-- Kit de test headless : il enveloppe des fonctions moteur (core.show_formspec, core.get_player_by_name…)
files["tests/passionphoto_test/"] = { globals = { "passionphoto_test", "core" } }
-- Tests unitaires : LuaJIT pur, hors moteur
files["tests/unit/"] = { globals = { "passionphoto" } }

-- tests/unit/fixtures/ : données générées (tools/gen_png_fixtures.py)
exclude_files = { ".deps/", ".run/", ".headless/", ".cache/", "dist/", "tests/_tmp/", "tests/unit/fixtures/" }
