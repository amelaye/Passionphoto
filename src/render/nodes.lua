-- Ce que le rendu doit savoir de chaque type de nœud, calculé une fois par identifiant de contenu (à la première
-- rencontre) : forme, textures des 6 faces, couleurs, transparence, lumière émise, boîtes (tournées selon param2).
-- Faces dans l'ordre des tuiles du moteur : 1 = +Y, 2 = −Y, 3 = +X, 4 = −X, 5 = +Z, 6 = −Z.
local textures = passionphoto.render.textures
local floor = math.floor

local M = {}

local KIND = {
	airlike = "air", normal = "cube", liquid = "liquid", flowingliquid = "liquid",
	glasslike = "glass", glasslike_framed = "glass", glasslike_framed_optional = "glass",
	allfaces = "allfaces", allfaces_optional = "allfaces", plantlike = "plant", firelike = "plant",
	plantlike_rooted = "cube", nodebox = "boxes", mesh = "approx", raillike = "rail", fencelike = "fence",
	torchlike = "air", signlike = "air",
}

local info = {} -- [content_id] = fiche

local function tile_image(t)
	local name, spec = t, nil
	if type(t) == "table" then name, spec = t.name or t.image, t end
	local img = type(name) == "string" and textures.resolve(name) or nil
	if img and spec and type(spec.animation) == "table" then
		local an = spec.animation
		if an.type == "vertical_frames" then
			local fh = floor(img.w * (an.aspect_h or img.w) / (an.aspect_w or img.w))
			if fh > 0 and fh < img.h then img = textures.crop(img, 0, 0, img.w, fh) end
		elseif an.type == "sheet_2d" then
			local fw, fh = floor(img.w / (an.frames_w or 1)), floor(img.h / (an.frames_h or 1))
			if fw > 0 and fh > 0 then img = textures.crop(img, 0, 0, fw, fh) end
		end
	end
	local col = spec and spec.color and core.colorspec_to_table(spec.color) or nil
	return img, col
end

local function faces_of(tiles)
	local imgs, cols = {}, {}
	if type(tiles) == "table" and #tiles > 0 then
		for i = 1, 6 do imgs[i], cols[i] = tile_image(tiles[math.min(i, #tiles)]) end
	end
	return imgs, cols
end

--- Boîtes « fixed » d'un node_box / selection_box (une boîte seule ou une liste), coordonnées relatives au centre.
local function fixed_boxes(nb)
	if type(nb) ~= "table" then return nil end
	if nb.type == "regular" or nb.type == nil then return nil end
	local fixed = nb.fixed
	if nb.type == "wallmounted" then fixed = nb.wall_bottom end
	if nb.type == "connected" and fixed == nil then return nil end
	if type(fixed) ~= "table" then return nil end
	if type(fixed[1]) == "number" then fixed = { fixed } end
	local out = {}
	for _, b in ipairs(fixed) do
		if type(b) == "table" and #b >= 6 then
			out[#out + 1] = { math.min(b[1], b[4]), math.min(b[2], b[5]), math.min(b[3], b[6]),
				math.max(b[1], b[4]), math.max(b[2], b[5]), math.max(b[3], b[6]) }
		end
	end
	return #out > 0 and out or nil
end

-- Rotations par quarts de tour, comme le moteur (irrlicht rotateXZBy / rotateYZBy / rotateXYBy).
local function rot(a, b, deg) -- renvoie (a·cos − b·sin, a·sin + b·cos) pour deg multiple de 90
	local q = (deg / 90) % 4
	if q == 0 then return a, b elseif q == 1 then return -b, a elseif q == 2 then return -a, -b end
	return b, -a
end

local function rotate_point(x, y, z, facedir)
	local axis, r = floor(facedir / 4) % 8, facedir % 4
	if r == 1 then x, z = rot(x, z, -90)
	elseif r == 2 then x, z = rot(x, z, 180)
	elseif r == 3 then x, z = rot(x, z, 90) end
	if axis == 1 then y, z = rot(y, z, 90)
	elseif axis == 2 then y, z = rot(y, z, -90)
	elseif axis == 3 then x, y = rot(x, y, -90)
	elseif axis == 4 then x, y = rot(x, y, 90)
	elseif axis == 5 then x, y = rot(x, y, 180) end
	return x, y, z
end

--- Boîtes de la fiche tournées selon param2 (mises en cache par valeur de param2).
function M.boxes(inf, param2)
	if not inf.rotate then return inf.boxes end
	local fd = inf.rotate == "4dir" and param2 % 4 or param2 % 32
	local c = inf.rotated[fd]
	if c then return c end
	c = {}
	for i, b in ipairs(inf.boxes) do
		local x1, y1, z1 = rotate_point(b[1], b[2], b[3], fd)
		local x2, y2, z2 = rotate_point(b[4], b[5], b[6], fd)
		c[i] = { math.min(x1, x2), math.min(y1, y2), math.min(z1, z2), math.max(x1, x2), math.max(y1, y2), math.max(z1, z2) }
	end
	inf.rotated[fd] = c
	return c
end

local function build(cid)
	local name = core.get_name_from_content_id(cid)
	local def = core.registered_nodes[name]
	local inf = { name = name, kind = "air", faces = {}, fcol = {}, light = 0 }
	if not def or cid == core.CONTENT_AIR or cid == core.CONTENT_IGNORE then return inf end
	inf.kind = KIND[def.drawtype or "normal"] or "cube"
	if inf.kind == "air" then return inf end
	inf.faces, inf.fcol = faces_of(def.tiles or def.tile_images)
	if type(def.overlay_tiles) == "table" and #def.overlay_tiles > 0 then
		local ov = faces_of(def.overlay_tiles)
		for i = 1, 6 do
			if inf.faces[i] and ov[i] then inf.faces[i] = textures.overlay(inf.faces[i], ov[i]) end
		end
	end
	inf.color = def.color and core.colorspec_to_table(def.color) or nil
	local pt2 = def.paramtype2 or "none"
	if def.palette and pt2:find("^color") then
		inf.palette = textures.resolve(def.palette)
		inf.pt2 = pt2
	end
	inf.light = def.light_source or 0
	inf.own_light = def.paramtype == "light"
	inf.clip = def.use_texture_alpha == "clip" or def.use_texture_alpha == "blend"
	inf.alpha = def.alpha -- ancien champ des liquides
	inf.vscale = def.visual_scale or 1
	-- couleur moyenne par face (formes approchées, repli)
	inf.avg = {}
	for i = 1, 6 do
		if inf.faces[i] then
			local r, g, b = textures.average(inf.faces[i])
			inf.avg[i] = { r, g, b }
		end
	end
	if inf.kind == "boxes" or inf.kind == "approx" then
		inf.boxes = inf.kind == "boxes" and fixed_boxes(def.node_box)
			or fixed_boxes(def.selection_box) or fixed_boxes(def.collision_box)
		if not inf.boxes then
			inf.kind = inf.kind == "boxes" and "cube" or "approx_cube"
		elseif pt2 == "facedir" or pt2 == "colorfacedir" then
			inf.rotate, inf.rotated = "facedir", {}
		elseif pt2 == "4dir" or pt2 == "color4dir" then
			inf.rotate, inf.rotated = "4dir", {}
		end
	elseif inf.kind == "fence" then
		inf.kind, inf.boxes = "boxes", { { -0.125, -0.5, -0.125, 0.125, 0.5, 0.125 } }
	end
	return inf
end

--- Fiche du nœud d'identifiant `cid` (calculée à la première demande).
function M.get(cid)
	local inf = info[cid]
	if not inf then
		inf = build(cid)
		info[cid] = inf
	end
	return inf
end

--- Couleur de palette (0..255) pour param2, ou nil.
function M.palette_color(inf, param2)
	local pal = inf.palette
	if not pal then return nil end
	local i = param2
	if inf.pt2 == "colorwallmounted" then i = floor(param2 / 8)
	elseif inf.pt2 == "colorfacedir" or inf.pt2 == "colordegrotate" then i = floor(param2 / 32)
	elseif inf.pt2 == "color4dir" then i = floor(param2 / 4) end
	if i >= pal.w * pal.h then return nil end
	local k = i + 1
	return pal.r[k], pal.g[k], pal.b[k]
end

return M
