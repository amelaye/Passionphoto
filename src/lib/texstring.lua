-- Analyse des chaînes de texture de Luanti (« a.png^b.png^[colorize:#ff0000:128 », groupes entre parenthèses).
-- Logique PURE (tests : tests/unit/test_texstring.lua). Le rendu (src/render/textures.lua) applique le résultat.
--
-- texstring.parse(s) → liste d'étapes appliquées de gauche à droite à une image accumulée :
--   { kind = "file", name = "a.png" }           superposée à l'accumulateur (ou le crée)
--   { kind = "group", steps = { … } }           sous-expression entre parenthèses, superposée
--   { kind = "mod", name = "colorize", args = "#ff0000:128" }   modificateur appliqué à l'accumulateur
local M = {}

--- Découpe `s` sur `sep` au niveau 0 de parenthèses, en respectant les échappements « \ ».
local function split_top(s, sep)
	local parts, buf, depth, i, n = {}, {}, 0, 1, #s
	while i <= n do
		local c = s:sub(i, i)
		if c == "\\" and i < n then
			buf[#buf + 1] = s:sub(i, i + 1)
			i = i + 1
		elseif c == "(" then
			depth = depth + 1
			buf[#buf + 1] = c
		elseif c == ")" then
			depth = depth - 1
			buf[#buf + 1] = c
		elseif c == sep and depth == 0 then
			parts[#parts + 1] = table.concat(buf)
			buf = {}
		else
			buf[#buf + 1] = c
		end
		i = i + 1
	end
	parts[#parts + 1] = table.concat(buf)
	return parts
end
M.split_top = split_top

local function unescape(s)
	return (s:gsub("\\(.)", "%1"))
end

function M.parse(s)
	local steps = {}
	if type(s) ~= "string" or s == "" then return steps end
	for _, part in ipairs(split_top(s, "^")) do
		if part ~= "" then
			if part:sub(1, 1) == "(" and part:sub(-1) == ")" then
				steps[#steps + 1] = { kind = "group", steps = M.parse(part:sub(2, -2)) }
			elseif part:sub(1, 1) == "[" then
				local name, args = part:match("^%[([%w_]+):?(.*)$")
				steps[#steps + 1] = { kind = "mod", name = name or "", args = unescape(args or "") }
			else
				steps[#steps + 1] = { kind = "file", name = unescape(part) }
			end
		end
	end
	return steps
end

--- Noms de fichiers cités par la chaîne (fichiers de base, groupes, et ceux de [combine).
function M.files(s)
	local out, seen = {}, {}
	local function add(name)
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	local function walk(steps)
		for _, st in ipairs(steps) do
			if st.kind == "file" then
				add(st.name)
			elseif st.kind == "group" then
				walk(st.steps)
			elseif st.kind == "mod" and st.name == "combine" then
				for name in st.args:gmatch("=([^:]+)") do add(name) end
			end
		end
	end
	walk(M.parse(s))
	return out
end

return M
