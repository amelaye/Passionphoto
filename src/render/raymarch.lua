-- Rendu d'une photo : un rayon par échantillon, parcours de grille (DDA) avec core.get_node_raw, texture du nœud
-- échantillonnée au point d'impact, lumière jour/nuit tirée du param1 de la case devant la face, ombrage par face
-- (valeurs du client), transparences (verre, eau, feuillage, plantes en croix), boîtes, ciel, soleil, brouillard.
-- Un rendu est un « travail » : job:step(budget_µs) calcule des rangées jusqu'à épuisement du budget, ce qui
-- permet de l'étaler sur plusieurs pas serveur (skill photo-render §8). M.render() le fait d'un bloc (mesures).
local nodes = passionphoto.render.nodes
local textures = passionphoto.render.textures
local get_raw = core.get_node_raw
local floor, abs, sqrt, min, max, huge = math.floor, math.abs, math.sqrt, math.min, math.max, math.huge
local char, concat = string.char, table.concat

local M = {}

-- Ombrage par face du client (+Y, −Y, +X, −X, +Z, −Z).
local SHADE = { 1.0, 0.447, 0.671, 0.671, 0.837, 0.837 }

-- Courbe d'éclairement niveau 0..15 → facteur, reconstituée d'après celle du client avec ses réglages par défaut
-- (light_curve_low_gradient 0,04, high_gradient 0, boost 0,2 centré sur 0,5, étalement 0,2, gamma 1) :
-- cubique d'Hermite + bosse gaussienne. Niveau 10 ≈ 0,88 : les zones à l'ombre restent claires, comme en jeu.
local LIGHT = {}
do
	local a, b, boost, center, sigma = 0.04, 0, 0.2, 0.5, 0.2
	for i = 0, 15 do
		local x = i / 15
		local y = (a + b - 2) * x ^ 3 + (3 - 2 * a - b) * x ^ 2 + a * x
		LIGHT[i] = math.min(1, y + boost * math.exp(-0.5 * ((x - center) / sigma) ^ 2))
	end
end
local DAY_HORIZON, DAY_ZENITH = { 144, 211, 246 }, { 97, 181, 245 }
local NIGHT_HORIZON, NIGHT_ZENITH = { 18, 24, 44 }, { 6, 9, 22 }

local function mix(a, b, t)
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

local function c8(v)
	v = floor(v + 0.5)
	if v < 0 then return 0 elseif v > 255 then return 255 end
	return v
end

--- Coordonnées de texture (u, v) d'un point de la face `face`, fractions (fx, fy, fz) dans le nœud.
local function uv(face, fx, fy, fz)
	if face == 1 then return fx, 1 - fz
	elseif face == 2 then return fx, fz
	elseif face == 3 then return fz, 1 - fy
	elseif face == 4 then return 1 - fz, 1 - fy
	elseif face == 5 then return 1 - fx, 1 - fy end
	return fx, 1 - fy
end

local function texel(img, u, v)
	local w, h = img.w, img.h
	local tx, ty = floor(u * w), floor(v * h)
	if tx < 0 then tx = 0 elseif tx >= w then tx = w - 1 end
	if ty < 0 then ty = 0 elseif ty >= h then ty = h - 1 end
	local i = ty * w + tx + 1
	return img.r[i], img.g[i], img.b[i], img.a[i]
end

--- Couleur (0..255) et alpha d'un point d'une face, avec couleurs de tuile, de nœud et de palette.
local function surface(inf, face, u, v, param2, approx)
	local r, g, b, a
	local img = inf.faces[face]
	if approx or not img then
		local av = inf.avg[face] or inf.avg[1]
		if av then r, g, b, a = av[1], av[2], av[3], 255 else r, g, b, a = 128, 128, 128, 255 end
	else
		r, g, b, a = texel(img, u, v)
	end
	local fc = inf.fcol[face]
	if fc then r, g, b = r * fc.r / 255, g * fc.g / 255, b * fc.b / 255 end
	local nc = inf.color
	if nc then r, g, b = r * nc.r / 255, g * nc.g / 255, b * nc.b / 255 end
	if inf.palette then
		local pr, pg, pb = nodes.palette_color(inf, param2)
		if pr then r, g, b = r * pr / 255, g * pg / 255, b * pb / 255 end
	end
	return r, g, b, a
end

local function light_of(p1, ratio, emit)
	local l = floor(ratio * (p1 % 16) + (1 - ratio) * floor(p1 / 16) + 0.5)
	if emit > l then l = emit end
	if l > 15 then l = 15 end
	return LIGHT[l]
end

--- Boîte la plus proche touchée après tmin : t, face d'entrée (1..6). Boîtes relatives au centre (cx, cy, cz).
local function hit_boxes(boxes, cx, cy, cz, ox, oy, oz, dx, dy, dz, tmin, tmax)
	local best, bface = huge, nil
	for i = 1, #boxes do
		local bx = boxes[i]
		local t0, t1, face = tmin - 1e-6, tmax, nil
		if dx ~= 0 then
			local ta, tb, f = (cx + bx[1] - ox) / dx, (cx + bx[4] - ox) / dx, 4
			if ta > tb then ta, tb, f = tb, ta, 3 end
			if ta > t0 then t0, face = ta, f end
			if tb < t1 then t1 = tb end
		elseif ox < cx + bx[1] or ox > cx + bx[4] then
			t1 = -1
		end
		if dy ~= 0 then
			local ta, tb, f = (cy + bx[2] - oy) / dy, (cy + bx[5] - oy) / dy, 2
			if ta > tb then ta, tb, f = tb, ta, 1 end
			if ta > t0 then t0, face = ta, f end
			if tb < t1 then t1 = tb end
		elseif oy < cy + bx[2] or oy > cy + bx[5] then
			t1 = -1
		end
		if dz ~= 0 then
			local ta, tb, f = (cz + bx[3] - oz) / dz, (cz + bx[6] - oz) / dz, 6
			if ta > tb then ta, tb, f = tb, ta, 5 end
			if ta > t0 then t0, face = ta, f end
			if tb < t1 then t1 = tb end
		elseif oz < cz + bx[3] or oz > cz + bx[6] then
			t1 = -1
		end
		if face and t0 <= t1 and t0 < best then best, bface = t0, face end
	end
	if bface then return best, bface end
end

--- Prépare un rendu. view = { eye, yaw, pitch } (conventions du moteur) ;
-- opts = { w, h, ssaa (1 ou 2), fov (vertical, degrés, défaut 72), distance (défaut 120), time, exposure }.
function M.new_job(view, opts)
	opts = opts or {}
	local w = opts.w or 128
	local h = opts.h or w
	local ss = opts.ssaa or 1
	local maxd = opts.distance or 120
	local exposure = opts.exposure or 1
	local tanv = math.tan(math.rad(opts.fov or 72) / 2)
	local tanh = tanv * w / h
	local yaw, pitch = view.yaw, view.pitch
	local fx, fy, fz = -math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch)
	local rx, rz = math.cos(yaw), math.sin(yaw)
	local ux, uy, uz = fy * rz, fz * rx - fx * rz, -fy * rx -- haut = direction × droite (droite.y = 0)
	local tod = opts.time or core.get_timeofday()
	local ratio = core.time_to_day_night_ratio(tod)
	local sa = (tod - 0.25) * 2 * math.pi
	local sunx, suny = math.cos(sa), math.sin(sa)
	local hz = { mix(NIGHT_HORIZON, DAY_HORIZON, ratio) }
	local zen = { mix(NIGHT_ZENITH, DAY_ZENITH, ratio) }
	local dawn = ratio > 0.05 and max(0, 1 - abs(suny) / 0.3) or 0
	local fog_start = 0.55 * maxd
	local ox, oy, oz = view.eye.x, view.eye.y, view.eye.z
	local infos = {}

	local function sky(dx, dy, dz)
		local t = dy > 0 and sqrt(dy) or 0
		local r, g, b = hz[1] + (zen[1] - hz[1]) * t, hz[2] + (zen[2] - hz[2]) * t, hz[3] + (zen[3] - hz[3]) * t
		if dy < 0 then
			local k = 1 + dy * 0.35
			r, g, b = r * k, g * k, b * k
		end
		local sd = dx * sunx + dy * suny
		if dawn > 0 then
			local k = dawn * max(0, sd) * (1 - min(1, abs(dy) * 3))
			r, g, b = r + (255 - r) * k * 0.8, g + (150 - g) * k * 0.6, b + (80 - b) * k * 0.6
		end
		if suny > -0.05 and sd > 0.9986 then return 255, 248, 220 end -- disque solaire (~3°)
		if suny < 0.05 and sd < -0.9990 then return 215, 222, 235 end -- lune, à l'opposé
		return r, g, b
	end

	local fog_r, fog_g, fog_b = sky(1, 0, 0)
	fog_r, fog_g, fog_b = (fog_r + hz[1]) / 2, (fog_g + hz[2]) / 2, (fog_b + hz[3]) / 2

	local function trace(dx, dy, dz)
		local x, y, z = floor(ox + 0.5), floor(oy + 0.5), floor(oz + 0.5)
		local sx, sy, sz = dx > 0 and 1 or -1, dy > 0 and 1 or -1, dz > 0 and 1 or -1
		local tdx = dx ~= 0 and abs(1 / dx) or huge
		local tdy = dy ~= 0 and abs(1 / dy) or huge
		local tdz = dz ~= 0 and abs(1 / dz) or huge
		local tmx = dx ~= 0 and (x + 0.5 * sx - ox) / dx or huge
		local tmy = dy ~= 0 and (y + 0.5 * sy - oy) / dy or huge
		local tmz = dz ~= 0 and (z + 0.5 * sz - oz) / dz or huge
		local prev_cid, prev_p1 = get_raw(x, y, z)
		local cr, cg, cb, tr = 0, 0, 0, 1
		local water_t, wr, wg, wb = nil, 0, 0, 0
		while true do
			local t, axis
			if tmx < tmy then
				if tmx < tmz then x, t, tmx, axis = x + sx, tmx, tmx + tdx, 1
				else z, t, tmz, axis = z + sz, tmz, tmz + tdz, 3 end
			elseif tmy < tmz then y, t, tmy, axis = y + sy, tmy, tmy + tdy, 2
			else z, t, tmz, axis = z + sz, tmz, tmz + tdz, 3 end
			if t > maxd then break end
			local cid, p1, p2, ok = get_raw(x, y, z)
			if not ok then break end
			local inf = infos[cid]
			if not inf then
				inf = nodes.get(cid)
				infos[cid] = inf
			end
			local kind = inf.kind
			if kind ~= "air" then
				local face
				if axis == 1 then face = sx > 0 and 4 or 3 elseif axis == 2 then face = sy > 0 and 2 or 1
				else face = sz > 0 and 6 or 5 end
				local t_exit = min(tmx, tmy, tmz)
				local hr, hg, hb, ha, hface, ht, lp1
				if kind == "cube" or kind == "approx_cube" then
					local u, v = uv(face, ox + dx * t - x + 0.5, oy + dy * t - y + 0.5, oz + dz * t - z + 0.5)
					local r, g, b, a = surface(inf, face, u, v, p2, kind == "approx_cube")
					if not inf.clip or a >= 128 then hr, hg, hb, ha, hface, ht, lp1 = r, g, b, 1, face, t, prev_p1 end
				elseif kind == "liquid" or kind == "glass" then
					if prev_cid ~= cid then -- pas de face entre deux nœuds identiques (comme le moteur)
						local u, v = uv(face, ox + dx * t - x + 0.5, oy + dy * t - y + 0.5, oz + dz * t - z + 0.5)
						local r, g, b, a = surface(inf, face, u, v, p2)
						local op = a / 255
						if kind == "liquid" then
							if op > 0.98 then op = inf.alpha and inf.alpha / 255 or 0.6 end
							water_t = t
						end
						if op > 0.02 then
							hr, hg, hb, ha, hface, ht, lp1 = r, g, b, op, face, t, inf.own_light and p1 or prev_p1
						end
					end
				elseif kind == "allfaces" then
					local u, v = uv(face, ox + dx * t - x + 0.5, oy + dy * t - y + 0.5, oz + dz * t - z + 0.5)
					local r, g, b, a = surface(inf, face, u, v, p2)
					if a >= 128 then
						hr, hg, hb, ha, hface, ht, lp1 = r, g, b, 1, face, t, prev_p1
					else -- trou du feuillage : face intérieure du côté opposé
						local ef
						if t_exit == tmx then ef = sx > 0 and 3 or 4 elseif t_exit == tmy then ef = sy > 0 and 1 or 2
						else ef = sz > 0 and 5 or 6 end
						local eu, ev = uv(ef, ox + dx * t_exit - x + 0.5, oy + dy * t_exit - y + 0.5, oz + dz * t_exit - z + 0.5)
						r, g, b, a = surface(inf, ef, eu, ev, p2)
						if a >= 128 then hr, hg, hb, ha, hface, ht, lp1 = r, g, b, 1, ef, t_exit, inf.own_light and p1 or prev_p1 end
					end
				elseif kind == "plant" then -- deux plans en croix, base au bas du nœud
					local s, lx0, lz0, ly0 = inf.vscale, ox - x, oz - z, oy - y
					local ta = (dx - dz) ~= 0 and -(lx0 - lz0) / (dx - dz) or huge
					local tb = (dx + dz) ~= 0 and -(lx0 + lz0) / (dx + dz) or huge
					if tb < ta then ta, tb = tb, ta end
					for _, tp in ipairs({ ta, tb }) do
						if tp > t and tp < t_exit then
							local lx, ly = lx0 + dx * tp, ly0 + dy * tp
							if abs(lx) <= 0.5 * s and ly >= -0.5 and ly <= s - 0.5 then
								local r, g, b, a = surface(inf, 1, lx / s + 0.5, 1 - (ly + 0.5) / s, p2)
								if a >= 128 then
									hr, hg, hb, ha, hface, ht, lp1 = r, g, b, 1, 5, tp, inf.own_light and p1 or prev_p1
									break
								end
							end
						end
					end
				elseif kind == "boxes" or kind == "approx" then
					local bt, bf = hit_boxes(nodes.boxes(inf, p2), x, y, z, ox, oy, oz, dx, dy, dz, t, t_exit)
					if bt then
						local u, v = uv(bf, ox + dx * bt - x + 0.5, oy + dy * bt - y + 0.5, oz + dz * bt - z + 0.5)
						local r, g, b = surface(inf, bf, u, v, p2, kind == "approx")
						hr, hg, hb, ha, hface, ht, lp1 = r, g, b, 1, bf, bt, inf.own_light and p1 or prev_p1
					end
				elseif kind == "rail" and dy ~= 0 then
					local tp = (y - 0.5 + 0.0625 - oy) / dy
					if tp > t and tp < t_exit then
						local lx, lz = ox + dx * tp - x + 0.5, oz + dz * tp - z + 0.5
						local r, g, b, a = surface(inf, 1, lx, 1 - lz, p2)
						if a >= 128 then hr, hg, hb, ha, hface, ht, lp1 = r, g, b, 1, 1, tp, inf.own_light and p1 or prev_p1 end
					end
				end
				if hr then
					local lf = light_of(lp1, ratio, inf.light) * SHADE[hface] * exposure
					local r, g, b = hr * lf, hg * lf, hb * lf
					if kind == "liquid" then
						wr, wg, wb = r, g, b
					elseif water_t and ha >= 1 then -- fond vu à travers l'eau : s'estompe avec la profondeur
						local k = 0.78 ^ (ht - water_t)
						r, g, b = r * k + wr * (1 - k), g * k + wg * (1 - k), b * k + wb * (1 - k)
					end
					if ht > fog_start then
						local f = min(1, (ht - fog_start) / (maxd - fog_start))
						r, g, b = r + (fog_r - r) * f, g + (fog_g - g) * f, b + (fog_b - b) * f
					end
					cr, cg, cb = cr + tr * ha * r, cg + tr * ha * g, cb + tr * ha * b
					tr = tr * (1 - ha)
					if tr < 0.03 then return cr, cg, cb end
				end
			end
			prev_cid, prev_p1 = cid, p1
		end
		local r, g, b = sky(dx, dy, dz)
		return cr + tr * r, cg + tr * g, cb + tr * b
	end

	local job = { w = w, h = h, row = 0, parts = {}, n = 0, us = 0, rays = w * h * ss * ss }
	local inv = 1 / (ss * ss)

	--- Calcule des rangées jusqu'à `budget_us` microsecondes (nil = tout). Renvoie true quand c'est fini.
	function job.step(budget_us)
		local t0 = core.get_us_time()
		local parts, n = job.parts, job.n
		while job.row < h do
			local j = job.row
			for i = 0, w - 1 do
				local ar, ag, ab = 0, 0, 0
				for sj = 0, ss - 1 do
					local v = (1 - (j + (sj + 0.5) / ss) / h * 2) * tanv
					for si = 0, ss - 1 do
						local u = ((i + (si + 0.5) / ss) / w * 2 - 1) * tanh
						local dx, dy, dz = fx + rx * u + ux * v, fy + uy * v, fz + rz * u + uz * v
						local len = sqrt(dx * dx + dy * dy + dz * dz)
						local r, g, b = trace(dx / len, dy / len, dz / len)
						ar, ag, ab = ar + r, ag + g, ab + b
					end
				end
				n = n + 1
				parts[n] = char(c8(ar * inv), c8(ag * inv), c8(ab * inv), 255)
			end
			job.row = j + 1
			if budget_us and core.get_us_time() - t0 >= budget_us then break end
		end
		job.n = n
		job.us = job.us + core.get_us_time() - t0
		return job.row >= h
	end

	--- Résultat : { w, h, raw (RGBA de haut en bas), rays, us (temps de calcul cumulé) }.
	function job.result()
		return { w = w, h = h, raw = concat(job.parts), rays = job.rays, us = job.us }
	end

	return job
end

--- Rendu d'un bloc (bloque le serveur le temps du calcul : réservé aux scénarios de mesure et aux essais).
function M.render(view, opts)
	local job = M.new_job(view, opts)
	job.step(nil)
	local res = job.result()
	res.textures = textures.stats()
	return res
end

return M
