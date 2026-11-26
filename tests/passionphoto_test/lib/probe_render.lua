-- SONDE de faisabilité — ce n'est PAS le rendu du mod (skill photo-render) : un rayon core.raycast par pixel,
-- couleur approximative déduite du nom du nœud touché, ombrage par face, lumière du nœud, brouillard, ciel.
-- Sert à mesurer le coût d'un rayon dans le vrai moteur et à vérifier la chaîne d'export des images.
local T = passionphoto_test

local NAMED = {
	red = { 200, 45, 45 }, orange = { 225, 125, 40 }, yellow = { 230, 205, 55 }, green = { 70, 160, 60 },
	dark_green = { 35, 95, 35 }, cyan = { 45, 165, 185 }, blue = { 45, 70, 190 }, violet = { 120, 60, 170 },
	magenta = { 195, 60, 165 }, pink = { 235, 150, 170 }, white = { 235, 235, 235 }, grey = { 130, 130, 130 },
	dark_grey = { 75, 75, 75 }, black = { 30, 30, 30 }, brown = { 110, 72, 40 },
}
local KEYWORDS = {
	{ "water", { 45, 95, 200 } }, { "lava", { 230, 100, 20 } }, { "leaves", { 55, 125, 40 } },
	{ "needles", { 40, 90, 50 } }, { "grass", { 85, 150, 50 } }, { "dirt", { 120, 85, 55 } },
	{ "sand", { 215, 200, 145 } }, { "gravel", { 120, 115, 110 } }, { "tree", { 105, 78, 45 } },
	{ "wood", { 165, 125, 80 } }, { "glass", { 205, 230, 240 } }, { "snow", { 240, 242, 248 } },
	{ "ice", { 170, 200, 240 } }, { "cobble", { 105, 105, 105 } }, { "brick", { 150, 72, 55 } },
	{ "stone", { 125, 125, 128 } }, { "torch", { 255, 205, 90 } }, { "flower", { 220, 90, 120 } },
	{ "clay", { 160, 160, 175 } },
}
local SKY_DAY_ZENITH, SKY_DAY_HORIZON = { 97, 181, 245 }, { 144, 211, 246 }
local SKY_NIGHT = { 8, 12, 32 }

local cache = {}
local function base_color(name)
	local c = cache[name]
	if c then return c end
	local word = name:match(":(.+)$") or name
	c = NAMED[word]
	if not c then
		for _, kv in ipairs(KEYWORDS) do
			if word:find(kv[1], 1, true) then c = kv[2]; break end
		end
	end
	if not c then
		local h = 0
		for i = 1, #name do h = (h * 31 + name:byte(i)) % 16777216 end
		c = { 60 + h % 160, 60 + math.floor(h / 256) % 160, 60 + math.floor(h / 65536) % 160 }
	end
	cache[name] = c
	return c
end

local function mix(a, b, t)
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

local function make_job(eye, yaw, pitch, opts)
	local w, h = opts.w or 64, opts.h or 64
	local maxd = opts.distance or 96
	local tanv = math.tan(math.rad(opts.fov or 72) / 2)
	local tanh = tanv * w / h
	local dir = vector.new(-math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	local right = vector.new(math.cos(yaw), 0, math.sin(yaw))
	local up = vector.cross(dir, right)
	local ratio = core.time_to_day_night_ratio(core.get_timeofday())
	local hz = { mix(SKY_NIGHT, SKY_DAY_HORIZON, ratio) }
	local zen = { mix(SKY_NIGHT, SKY_DAY_ZENITH, ratio) }
	local job = { w = w, h = h, y = 0, parts = {}, rays = 0, hits = 0, colors = {}, distinct = 0, luma = 0 }

	local function sky(d)
		local t = math.max(0, d.y) ^ 0.5
		return mix(hz, zen, t)
	end

	local function trace(d)
		local to = vector.add(eye, vector.multiply(d, maxd))
		local r, g, b, transmit = 0, 0, 0, 1
		for pt in core.raycast(eye, to, false, true) do
			if pt.type == "node" then
				local node = core.get_node(pt.under)
				local def = core.registered_nodes[node.name]
				local dt = def and def.drawtype or "normal"
				local c = base_color(node.name)
				local n = pt.intersection_normal
				local shade = n.y > 0.5 and 1 or (n.y < -0.5 and 0.5 or (math.abs(n.x) > 0.5 and 0.8 or 0.65))
				local light = core.get_node_light(pt.above) or 15
				local k = shade * (0.06 + 0.94 * (light / 15) ^ 1.5)
				local fog = math.min(1, (vector.distance(eye, pt.intersection_point) / maxd) ^ 2)
				local cr, cg, cb = mix({ c[1] * k, c[2] * k, c[3] * k }, hz, fog)
				local opacity = 1
				if dt == "liquid" or dt == "flowingliquid" then
					opacity = 0.55
				elseif dt:find("^glasslike") then
					opacity = 0.15
				end
				r, g, b = r + transmit * opacity * cr, g + transmit * opacity * cg, b + transmit * opacity * cb
				transmit = transmit * (1 - opacity)
				if transmit < 0.05 then return r, g, b, true end
			end
		end
		local sr, sg, sb = sky(d)
		return r + transmit * sr, g + transmit * sg, b + transmit * sb, transmit < 1
	end

	function job.row()
		local j = job.y
		for i = 0, w - 1 do
			local u = ((i + 0.5) / w * 2 - 1) * tanh
			local v = (1 - (j + 0.5) / h * 2) * tanv
			local d = vector.normalize(vector.add(dir, vector.add(vector.multiply(right, u), vector.multiply(up, v))))
			local r, g, b, hit = trace(d)
			r = math.max(0, math.min(255, math.floor(r + 0.5)))
			g = math.max(0, math.min(255, math.floor(g + 0.5)))
			b = math.max(0, math.min(255, math.floor(b + 0.5)))
			job.rays = job.rays + 1
			if hit then job.hits = job.hits + 1 end
			local key = math.floor(r / 8) * 1024 + math.floor(g / 8) * 32 + math.floor(b / 8)
			if not job.colors[key] then
				job.colors[key] = true
				job.distinct = job.distinct + 1
			end
			job.luma = job.luma + 0.299 * r + 0.587 * g + 0.114 * b
			job.parts[#job.parts + 1] = string.char(r, g, b, 255)
		end
		job.y = j + 1
	end

	function job.done() return job.y >= h end

	function job.result(us)
		return { w = w, h = h, raw = table.concat(job.parts), rays = job.rays, hits = job.hits,
			distinct = job.distinct, mean_luma = job.luma / math.max(1, job.rays), us = us }
	end
	return job
end

--- Rendu synchrone (bloque le serveur le temps du rendu : réservé aux scénarios de mesure).
-- Renvoie { w, h, raw (RGBA), rays, hits, distinct, mean_luma, us }.
function T.probe_render(eye, yaw, pitch, opts)
	local job = make_job(eye, yaw, pitch, opts or {})
	local t0 = core.get_us_time()
	while not job.done() do job.row() end
	return job.result(core.get_us_time() - t0)
end

--- Rendu étalé sur plusieurs pas serveur (15 ms au plus par pas), puis on_done(résultat).
function T.probe_render_async(eye, yaw, pitch, opts, on_done)
	local job = make_job(eye, yaw, pitch, opts or {})
	local spent = 0
	local function step()
		local t0 = core.get_us_time()
		repeat job.row() until job.done() or core.get_us_time() - t0 > 15000
		spent = spent + (core.get_us_time() - t0)
		if job.done() then on_done(job.result(spent)) else core.after(0, step) end
	end
	step()
end
