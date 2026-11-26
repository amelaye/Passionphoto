-- Mesures de référence pour le rendu (docs/PLAN.md, décision D3) : coût d'un rayon avec core.raycast contre
-- un parcours de grille (DDA) en Lua avec core.get_node_raw. À relancer après un changement de moteur :
-- tools/headless/run.sh -f mesure
local T = passionphoto_test

local function directions(yaw, pitch, w, h, fov)
	local tanv = math.tan(math.rad(fov) / 2)
	local dir = vector.new(-math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	local right = vector.new(math.cos(yaw), 0, math.sin(yaw))
	local up = vector.cross(dir, right)
	local out = {}
	for j = 0, h - 1 do
		for i = 0, w - 1 do
			local u = ((i + 0.5) / w * 2 - 1) * tanv
			local v = (1 - (j + 0.5) / h * 2) * tanv
			out[#out + 1] = vector.normalize(vector.add(dir, vector.add(vector.multiply(right, u), vector.multiply(up, v))))
		end
	end
	return out
end

T.register("mesure: coût d'un rayon — core.raycast contre DDA Lua + core.get_node_raw", function(ctx)
	local view = T.scenes.studio(ctx)
	ctx:wait(0.3)
	local eye = view.eye
	local dirs = directions(view.yaw, view.pitch, 64, 64, 72)
	local N = #dirs

	local first, ha = {}, 0
	local t0 = core.get_us_time()
	for i = 1, N do
		local pt = core.raycast(eye, vector.add(eye, vector.multiply(dirs[i], 96)), false, false):next()
		if pt then
			ha = ha + 1
			first[i] = core.hash_node_position(pt.under)
		end
	end
	local ta = core.get_us_time() - t0

	local solid = {}
	for name, def in pairs(core.registered_nodes) do
		solid[core.get_content_id(name)] = def.drawtype ~= "airlike" and def.pointable ~= false
			and (def.liquidtype or "none") == "none"
	end
	solid[core.CONTENT_AIR], solid[core.CONTENT_IGNORE] = false, false
	local get_raw, floor, huge = core.get_node_raw, math.floor, math.huge
	local function march(ox, oy, oz, dx, dy, dz, maxd)
		local x, y, z = floor(ox + 0.5), floor(oy + 0.5), floor(oz + 0.5)
		local sx, sy, sz = dx > 0 and 1 or -1, dy > 0 and 1 or -1, dz > 0 and 1 or -1
		local tdx = dx ~= 0 and math.abs(1 / dx) or huge
		local tdy = dy ~= 0 and math.abs(1 / dy) or huge
		local tdz = dz ~= 0 and math.abs(1 / dz) or huge
		local tmx = dx ~= 0 and ((x + 0.5 * sx - ox) / dx) or huge
		local tmy = dy ~= 0 and ((y + 0.5 * sy - oy) / dy) or huge
		local tmz = dz ~= 0 and ((z + 0.5 * sz - oz) / dz) or huge
		local t, steps = 0, 0
		while t <= maxd do
			local cid, _, _, ok = get_raw(x, y, z)
			steps = steps + 1
			if not ok then return nil, steps end
			if solid[cid] then return core.hash_node_position(vector.new(x, y, z)), steps end
			if tmx < tmy then
				if tmx < tmz then x = x + sx; t = tmx; tmx = tmx + tdx else z = z + sz; t = tmz; tmz = tmz + tdz end
			else
				if tmy < tmz then y = y + sy; t = tmy; tmy = tmy + tdy else z = z + sz; t = tmz; tmz = tmz + tdz end
			end
		end
		return nil, steps
	end

	local agree, steps_total = 0, 0
	local t1 = core.get_us_time()
	for i = 1, N do
		local d = dirs[i]
		local h, steps = march(eye.x, eye.y, eye.z, d.x, d.y, d.z, 96)
		steps_total = steps_total + steps
		if h and h == first[i] then agree = agree + 1 end
	end
	local tr = core.get_us_time() - t1

	ctx:metric("raycast_us_par_rayon", math.floor(ta / N))
	ctx:metric("dda_raw_us_par_rayon", math.floor(tr / N * 10) / 10)
	ctx:metric("dda_raw_noeuds_par_rayon", math.floor(steps_total / N))
	ctx:metric("dda_raw_meme_noeud_pct", math.floor(agree * 100 / math.max(1, ha)))
	ctx:metric("gain_x", math.floor(ta / math.max(1, tr) * 10) / 10)
	ctx:check(agree >= ha * 0.95, "le DDA touche le même nœud que core.raycast (≥ 95 % des rayons)")
	ctx:check(tr < ta, "le DDA Lua + get_node_raw est plus rapide que core.raycast")
end, { timeout = 60 })
