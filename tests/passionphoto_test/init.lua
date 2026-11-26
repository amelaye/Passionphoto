-- Kit de test headless de passionphoto : scénarios (tools/headless/run.sh) et serveur de dev (tools/server.sh).
-- Inactif sauf si le réglage `passionphoto_test.mode` vaut "scenarios" ou "dev". Jamais livré (tools/dist.sh).
-- Mode d'emploi : skill headless-luanti (.claude/skills/headless-luanti/SKILL.md).

local mode = core.settings:get("passionphoto_test.mode") or ""
if mode ~= "scenarios" and mode ~= "dev" then
	return
end

local modpath = core.get_modpath(core.get_current_modname())

passionphoto_test = {
	mode = mode,
	modpath = modpath,
	scenarios = {},
	fakes = {}, -- nom -> faux joueur (lib/fake_player.lua)
}
local T = passionphoto_test

function T.log(msg)
	core.log("action", "[passionphoto_test] " .. msg)
end

--- Enregistre un scénario. fn(ctx) tourne dans une coroutine : ctx:wait(s) laisse le serveur tourner.
-- opts.timeout : secondes (défaut 30). opts.known_bug : voir T.known_bug.
function T.register(name, fn, opts)
	T.scenarios[#T.scenarios + 1] = { name = name, fn = fn, opts = opts or {} }
end

--- Bug connu : le scénario décrit le comportement CORRECT et échoue tant que le bug existe (statut CONNU,
-- non bloquant). S'il se met à passer : statut CORRIGÉ, bloquant → le transformer en T.register et cocher
-- le bug dans docs/PLAN.md. label = "Bxx sujet: comportement attendu".
function T.known_bug(label, fn, opts)
	opts = opts or {}
	opts.known_bug = label
	T.register(label, fn, opts)
end

for _, f in ipairs({ "intercept", "fake_player", "png", "ctx", "scenes", "probe_render" }) do
	dofile(modpath .. "/lib/" .. f .. ".lua")
end

if mode == "scenarios" then
	dofile(modpath .. "/runner.lua")
else
	dofile(modpath .. "/dev.lua")
end
