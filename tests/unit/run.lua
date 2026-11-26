-- Lance les tests unitaires : luajit tests/unit/run.lua [filtre]   (fichiers tests/unit/test_*.lua)
-- Chaque fichier reçoit le cadre T (tests/unit/harness.lua) et T.root (racine du dépôt) pour charger un
-- module pur : local m = dofile(T.root .. "/src/lib/xxx.lua")
local root = (arg and arg[0] or ""):match("^(.*)/tests/unit/run%.lua$") or "."
local T = dofile(root .. "/tests/unit/harness.lua")
T.root = root

local filter = arg and arg[1]
local files = {}
local p = io.popen('ls "' .. root .. '"/tests/unit/test_*.lua 2>/dev/null')
for f in p:lines() do
	if not filter or f:find(filter, 1, true) then files[#files + 1] = f end
end
p:close()

for _, f in ipairs(files) do
	local chunk, err = loadfile(f)
	if not chunk then
		T.failed = T.failed + 1
		print("ERREUR " .. err)
	else
		local ok, e = pcall(chunk, T)
		if not ok then
			T.failed = T.failed + 1
			print("ERREUR " .. f .. " : " .. tostring(e))
		end
	end
end

print(("tests unitaires : %d fichier(s), %d réussi(s), %d échec(s), %d bug(s) connu(s)%s"):format(#files, T.passed,
	T.failed, T.known, T.fixed > 0 and (", " .. T.fixed .. " CORRIGÉ(S)") or ""))
os.exit((T.failed == 0 and T.fixed == 0) and 0 or 1)
