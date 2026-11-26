-- Textures des mods pour le rendu des photos : index des fichiers de tous les mods (sous-dossiers compris),
-- décodage à la demande (src/lib/png.lua) avec cache, composition des chaînes de texture (src/lib/texstring.lua).
-- La lecture des dossiers des autres mods est permise par la sécurité des mods (vérifié : scénario « moteur: »).
-- Image : { w, h, r = {}, g = {}, b = {}, a = {} } (index y*w + x + 1), jamais modifiée une fois en cache.
local png, texstring = passionphoto.png, passionphoto.texstring
local floor, max = math.floor, math.max

local M = {}

local index -- nom de fichier -> chemin
local files = {} -- nom de fichier -> image | false
local resolved = {} -- chaîne de texture -> image | false
local stats = { decoded = 0, failed = 0, missing = 0, us = 0 }

local function scan(dir, depth)
	for _, f in ipairs(core.get_dir_list(dir, false) or {}) do
		if f:sub(-4):lower() == ".png" and not index[f] then index[f] = dir .. "/" .. f end
	end
	if depth < 4 then
		for _, d in ipairs(core.get_dir_list(dir, true) or {}) do scan(dir .. "/" .. d, depth + 1) end
	end
end

--- (Re)construit l'index nom de fichier → chemin pour tous les mods chargés.
function M.build_index()
	index = {}
	for _, m in ipairs(core.get_modnames()) do
		local mp = core.get_modpath(m)
		if mp then scan(mp .. "/textures", 0) end
	end
	return index
end

-------------------------------------------------------------------------------------------------------------
-- opérations sur les images (chacune renvoie une NOUVELLE image)
-------------------------------------------------------------------------------------------------------------

local function new_image(w, h)
	return { w = w, h = h, r = {}, g = {}, b = {}, a = {} }
end

function M.crop(img, x0, y0, w, h)
	local out = new_image(w, h)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local si, di = (y0 + y) * img.w + x0 + x + 1, y * w + x + 1
			out.r[di], out.g[di], out.b[di], out.a[di] = img.r[si] or 0, img.g[si] or 0, img.b[si] or 0, img.a[si] or 0
		end
	end
	return out
end

--- Redimensionnement au plus proche voisin (toujours une copie).
function M.resize(img, w, h)
	local out = new_image(w, h)
	for y = 0, h - 1 do
		local row = floor(y * img.h / h) * img.w + 1
		for x = 0, w - 1 do
			local si, di = row + floor(x * img.w / w), y * w + x + 1
			out.r[di], out.g[di], out.b[di], out.a[di] = img.r[si], img.g[si], img.b[si], img.a[si]
		end
	end
	return out
end

--- `top` par-dessus `base` (mélange alpha), à la plus grande des deux tailles, comme le moteur.
function M.overlay(base, top)
	local w, h = max(base.w, top.w), max(base.h, top.h)
	local b = (base.w == w and base.h == h) and base or M.resize(base, w, h)
	local t = (top.w == w and top.h == h) and top or M.resize(top, w, h)
	local out = new_image(w, h)
	for i = 1, w * h do
		local ta, ba = t.a[i] / 255, b.a[i] / 255
		local oa = ta + ba * (1 - ta)
		if oa <= 0 then
			out.r[i], out.g[i], out.b[i], out.a[i] = 0, 0, 0, 0
		else
			local kb = ba * (1 - ta)
			out.r[i] = (t.r[i] * ta + b.r[i] * kb) / oa
			out.g[i] = (t.g[i] * ta + b.g[i] * kb) / oa
			out.b[i] = (t.b[i] * ta + b.b[i] * kb) / oa
			out.a[i] = oa * 255
		end
	end
	return out
end

local function map_pixels(img, f)
	local out = new_image(img.w, img.h)
	for i = 1, img.w * img.h do
		out.r[i], out.g[i], out.b[i], out.a[i] = f(img.r[i], img.g[i], img.b[i], img.a[i])
	end
	return out
end

local function color(s)
	local t = core.colorspec_to_table(s)
	if t then return t.r, t.g, t.b, t.a end
end

-------------------------------------------------------------------------------------------------------------
-- modificateurs pris en charge (les autres sont ignorés : l'image reste telle quelle)
-------------------------------------------------------------------------------------------------------------

local MODS = {}

function MODS.colorize(img, args)
	local col, ratio = args:match("^([^:]*):?(.*)$")
	local cr, cg, cb, ca = color(col)
	if not cr then return img end
	local k = ca / 255
	if ratio ~= "" and ratio ~= "alpha" then k = (tonumber(ratio) or 255) / 255 end
	return map_pixels(img, function(r, g, b, a)
		return r + (cr - r) * k, g + (cg - g) * k, b + (cb - b) * k, a
	end)
end

function MODS.multiply(img, args)
	local cr, cg, cb = color(args)
	if not cr then return img end
	return map_pixels(img, function(r, g, b, a) return r * cr / 255, g * cg / 255, b * cb / 255, a end)
end

function MODS.opacity(img, args)
	local k = (tonumber(args) or 255) / 255
	return map_pixels(img, function(r, g, b, a) return r, g, b, a * k end)
end

function MODS.brighten(img)
	return map_pixels(img, function(r, g, b, a) return (r + 255) / 2, (g + 255) / 2, (b + 255) / 2, a end)
end

function MODS.noalpha(img)
	return map_pixels(img, function(r, g, b) return r, g, b, 255 end)
end

function MODS.invert(img, args)
	local ir, ig, ib, ia = args:find("[Rr]"), args:find("[Gg]"), args:find("[Bb]"), args:find("[Aa]")
	return map_pixels(img, function(r, g, b, a)
		return ir and 255 - r or r, ig and 255 - g or g, ib and 255 - b or b, ia and 255 - a or a
	end)
end

function MODS.verticalframe(img, args)
	local n, i = args:match("^(%d+):(%d+)$")
	n, i = tonumber(n), tonumber(i)
	if not n or n < 1 then return img end
	local fh = floor(img.h / n)
	if fh < 1 then return img end
	return M.crop(img, 0, math.min(i, n - 1) * fh, img.w, fh)
end

function MODS.sheet(img, args)
	local cw, ch, x, y = args:match("^(%d+)x(%d+):(%d+),(%d+)$")
	cw, ch, x, y = tonumber(cw), tonumber(ch), tonumber(x), tonumber(y)
	if not cw or cw < 1 or ch < 1 then return img end
	local tw, th = floor(img.w / cw), floor(img.h / ch)
	if tw < 1 or th < 1 then return img end
	return M.crop(img, (x % cw) * tw, (y % ch) * th, tw, th)
end

function MODS.resize(img, args)
	local w, h = args:match("^(%d+)x(%d+)$")
	w, h = tonumber(w), tonumber(h)
	if not w or w < 1 or h < 1 or w * h > 512 * 512 then return img end
	return M.resize(img, w, h)
end

--- Générateur « [combine:LxH:x,y=texture:… » (textures imbriquées acceptées).
local function combine(args)
	local w, h, rest = args:match("^(%d+)x(%d+):?(.*)$")
	w, h = tonumber(w), tonumber(h)
	if not w or w < 1 or h < 1 or w * h > 512 * 512 then return nil end
	local canvas = new_image(w, h)
	for i = 1, w * h do canvas.r[i], canvas.g[i], canvas.b[i], canvas.a[i] = 0, 0, 0, 0 end
	local starts = {}
	for s in rest:gmatch("()%-?%d+,%-?%d+=") do starts[#starts + 1] = s end
	for k, s in ipairs(starts) do
		local piece = rest:sub(s, (starts[k + 1] or #rest + 2) - 2)
		local px, py, tex = piece:match("^(%-?%d+),(%-?%d+)=(.+)$")
		local img = tex and M.resolve(tex)
		if img then
			px, py = tonumber(px), tonumber(py)
			for y = 0, img.h - 1 do
				for x = 0, img.w - 1 do
					local cx, cy = px + x, py + y
					if cx >= 0 and cx < w and cy >= 0 and cy < h then
						local si, di = y * img.w + x + 1, cy * w + cx + 1
						local ta = img.a[si] / 255
						canvas.r[di] = img.r[si] * ta + canvas.r[di] * (1 - ta)
						canvas.g[di] = img.g[si] * ta + canvas.g[di] * (1 - ta)
						canvas.b[di] = img.b[si] * ta + canvas.b[di] * (1 - ta)
						canvas.a[di] = math.min(255, img.a[si] + canvas.a[di] * (1 - ta))
					end
				end
			end
		end
	end
	return canvas
end

-------------------------------------------------------------------------------------------------------------
-- fichiers et chaînes de texture
-------------------------------------------------------------------------------------------------------------

--- Image décodée d'un fichier de texture (nil si absent ou illisible).
function M.file(name)
	local c = files[name]
	if c ~= nil then return c or nil end
	if not index then M.build_index() end
	local img
	local path = index[name]
	if path then
		local f = io.open(path, "rb")
		if f then
			local data = f:read("*a")
			f:close()
			local t0 = core.get_us_time()
			local err
			img, err = png.decode(data)
			stats.us = stats.us + core.get_us_time() - t0
			if img then
				stats.decoded = stats.decoded + 1
			else
				stats.failed = stats.failed + 1
				core.log("warning", ("[passionphoto] texture illisible pour le rendu : %s (%s)"):format(name, tostring(err)))
			end
		end
	else
		stats.missing = stats.missing + 1
	end
	files[name] = img or false
	return img
end

local function apply(steps)
	local acc
	for _, st in ipairs(steps) do
		local img
		if st.kind == "file" then
			img = M.file(st.name)
		elseif st.kind == "group" then
			img = apply(st.steps)
		elseif st.name == "combine" then
			img = combine(st.args)
		elseif acc and MODS[st.name] then
			acc = MODS[st.name](acc, st.args)
		end
		if img then acc = acc and M.overlay(acc, img) or img end
	end
	return acc
end

--- Image d'une chaîne de texture complète (nil si rien de lisible). Résultat mis en cache.
function M.resolve(tex)
	if type(tex) ~= "string" or tex == "" then return nil end
	local c = resolved[tex]
	if c ~= nil then return c or nil end
	local ok, img = pcall(apply, texstring.parse(tex))
	if not ok then
		core.log("warning", ("[passionphoto] chaîne de texture non rendue : %s (%s)"):format(tex:sub(1, 80), tostring(img)))
		img = nil
	end
	resolved[tex] = img or false
	return img
end

--- Couleur moyenne pondérée par l'alpha : r, g, b, couverture (part de pixels opaques, 0..1).
function M.average(img)
	local r, g, b, wsum, opaque = 0, 0, 0, 0, 0
	for i = 1, img.w * img.h do
		local a = img.a[i] / 255
		r, g, b, wsum = r + img.r[i] * a, g + img.g[i] * a, b + img.b[i] * a, wsum + a
		if a >= 0.5 then opaque = opaque + 1 end
	end
	if wsum <= 0 then return 128, 128, 128, 0 end
	return r / wsum, g / wsum, b / wsum, opaque / (img.w * img.h)
end

function M.stats()
	return { decoded = stats.decoded, failed = stats.failed, missing = stats.missing, ms = floor(stats.us / 1000),
		indexed = index and (function() local n = 0 for _ in pairs(index) do n = n + 1 end return n end)() or 0 }
end

return M
