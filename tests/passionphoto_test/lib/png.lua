-- Export d'images vers <monde>/passionphoto_test_out/ (copié par le runner dans .headless/runs/<id>/photos/,
-- listé par tools/server.sh photos). Sert à REGARDER les photos produites sans ouvrir de client Luanti.
local T = passionphoto_test

T.out_dir = core.get_worldpath() .. "/passionphoto_test_out"

function T.slug(s)
	s = tostring(s):lower():gsub("[^%w%-]+", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
	return s:sub(1, 90)
end

--- pixels : chaîne RGBA brute (w*h*4 octets) ou tableau de w*h ColorSpec.
local function to_raw(w, h, pixels)
	if type(pixels) == "string" then
		assert(#pixels == w * h * 4, ("RGBA brut : %d octets attendus, %d reçus"):format(w * h * 4, #pixels))
		return pixels
	end
	local parts = {}
	for i = 1, w * h do
		parts[i] = core.colorspec_to_bytes(pixels[i] or "#ff00ff")
	end
	return table.concat(parts)
end

--- Agrandissement au plus proche voisin (lisible à l'écran, pixels nets).
local function upscale(w, h, raw, s)
	if not s or s <= 1 then return w, h, raw end
	local rows = {}
	for y = 0, h - 1 do
		local line = {}
		for x = 0, w - 1 do
			local i = (y * w + x) * 4
			line[#line + 1] = raw:sub(i + 1, i + 4):rep(s)
		end
		local row = table.concat(line)
		for _ = 1, s do rows[#rows + 1] = row end
	end
	return w * s, h * s, table.concat(rows)
end

function T.write_file(filename, data)
	core.mkdir(T.out_dir)
	local path = T.out_dir .. "/" .. filename
	assert(core.safe_file_write(path, data), "écriture impossible : " .. path)
	T.log("FICHIER " .. path)
	return path
end

--- Enregistre une image. opts.scale : agrandissement entier (défaut 1). Renvoie le chemin absolu.
function T.save_png(name, w, h, pixels, opts)
	opts = opts or {}
	local sw, sh, raw = upscale(w, h, to_raw(w, h, pixels), opts.scale)
	return T.write_file(T.slug(name) .. ".png", core.encode_png(sw, sh, raw, 6))
end

--- Statistiques d'une image RGBA brute : couleurs distinctes (quantifiées sur 5 bits), luminance moyenne 0..255.
function T.image_stats(w, h, raw)
	local seen, distinct, luma = {}, 0, 0
	for i = 0, w * h - 1 do
		local r, g, b = raw:byte(i * 4 + 1, i * 4 + 3)
		local key = math.floor(r / 8) * 1024 + math.floor(g / 8) * 32 + math.floor(b / 8)
		if not seen[key] then
			seen[key] = true
			distinct = distinct + 1
		end
		luma = luma + 0.299 * r + 0.587 * g + 0.114 * b
	end
	return { distinct = distinct, mean_luma = luma / (w * h) }
end

--- Enregistre une texture « [png:<base64> », ou un média dynamique envoyé avec filedata (T.rec.media_data).
function T.save_texture(name, texture)
	local b64 = type(texture) == "string" and texture:match("^%[png:([%w%+/=]+)$")
	if b64 then return T.write_file(T.slug(name) .. ".png", core.decode_base64(b64)) end
	local data = T.rec.media_data[texture]
	if data then return T.write_file(T.slug(name) .. ".png", data) end
	return nil, "texture non exportable : " .. tostring(texture):sub(1, 60)
end
