-- Mini-cadre de tests unitaires pour la logique PURE du mod (src/lib/*.lua) : LuaJIT seul, sans moteur.
-- Ces tests prouvent la logique, pas le comportement dans Luanti (voir les scénarios headless).
local T = { passed = 0, failed = 0, known = 0, fixed = 0, prefix = "" }

local function fmt(v)
	if type(v) == "string" then return string.format("%q", v) end
	return tostring(v)
end

function T.describe(name, fn)
	local old = T.prefix
	T.prefix = old .. name .. " › "
	fn()
	T.prefix = old
end

function T.it(name, fn)
	local ok, err = pcall(fn)
	if ok then
		T.passed = T.passed + 1
	else
		T.failed = T.failed + 1
		print("ÉCHEC  " .. T.prefix .. name .. "\n       " .. tostring(err))
	end
end

--- Bug connu : décrit le comportement CORRECT ; échoue tant que le bug existe (non bloquant), fait échouer
-- la suite dès qu'il passe (le transformer en T.it et cocher le bug dans docs/PLAN.md).
function T.known_bug(name, fn)
	local ok, err = pcall(fn)
	if ok then
		T.fixed = T.fixed + 1
		print("CORRIGÉ " .. T.prefix .. name .. " — passer en T.it et cocher le bug dans docs/PLAN.md")
	else
		T.known = T.known + 1
		if os.getenv("PP_TEST_VERBOSE") then print("CONNU  " .. T.prefix .. name .. " : " .. tostring(err)) end
	end
end

function T.ok(v, msg)
	if not v then error((msg or "valeur vraie attendue"), 2) end
end

function T.eq(actual, expected, msg)
	if actual ~= expected then
		error(("%s : attendu %s, obtenu %s"):format(msg or "égalité", fmt(expected), fmt(actual)), 2)
	end
end

function T.near(actual, expected, tol, msg)
	if math.abs(actual - expected) > tol then
		error(("%s : attendu %s ±%s, obtenu %s"):format(msg or "proche", fmt(expected), tol, fmt(actual)), 2)
	end
end

function T.contains(s, sub, msg)
	if not tostring(s):find(sub, 1, true) then
		error(("%s : %s ne contient pas %s"):format(msg or "contient", fmt(s), fmt(sub)), 2)
	end
end

function T.raises(fn, pattern, msg)
	local ok, err = pcall(fn)
	if ok then error((msg or "erreur attendue") .. " : aucune erreur levée", 2) end
	if pattern and not tostring(err):find(pattern) then
		error(("%s : erreur %s ne correspond pas à %s"):format(msg or "erreur attendue", fmt(err), fmt(pattern)), 2)
	end
end

local function deep_eq(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not deep_eq(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

function T.deep_eq(a, b, msg)
	if not deep_eq(a, b) then error((msg or "tables égales attendues"), 2) end
end

return T
