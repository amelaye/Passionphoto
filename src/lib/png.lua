-- Décodeur PNG en Lua pur : zlib (RFC 1950) + inflate (RFC 1951) + filtres, types de couleur 0/2/3/4/6,
-- profondeurs 1 à 16 bits, palettes et tRNS, entrelacement Adam7. L'API de Luanti n'a pas de décodeur PNG ;
-- celui-ci sert à lire les textures des mods pour colorer les photos (skill photo-render).
-- Logique PURE : aucun appel à core (tests : tests/unit/test_png.lua, images tests/unit/fixtures/png/).
--
-- png.decode(data) → image { w, h, r = {}, g = {}, b = {}, a = {} } (canaux 0–255, index y*w + x + 1),
--                    ou nil, message d'erreur.
local bit = rawget(_G, "bit") or require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local byte, sub = string.byte, string.sub
local floor, abs = math.floor, math.abs

local M = {}
M.MAX_PIXELS = 1024 * 1024 -- au-delà : refusé (mémoire et temps de décodage)

local function fail(msg)
	error("png: " .. msg, 0)
end

---------------------------------------------------------------------------------------------------------------
-- inflate (d'après puff.c de Mark Adler, décodage canonique bit à bit)
---------------------------------------------------------------------------------------------------------------

local MAXBITS = 15
local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163,
	195, 227, 258 }
local LEXT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
	4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

--- Table de Huffman canonique : count[longueur], symbol[0..] (indices 0-based, comme puff.c).
local function construct(lengths, n)
	local count, symbol, offs = {}, {}, {}
	for len = 0, MAXBITS do count[len] = 0 end
	for s = 0, n - 1 do
		local l = lengths[s] or 0
		count[l] = count[l] + 1
	end
	offs[1] = 0
	for len = 1, MAXBITS - 1 do offs[len + 1] = offs[len] + count[len] end
	for s = 0, n - 1 do
		local l = lengths[s] or 0
		if l ~= 0 then
			symbol[offs[l]] = s
			offs[l] = offs[l] + 1
		end
	end
	return { count = count, symbol = symbol }
end

local FIXED_LEN, FIXED_DIST
local function fixed_tables()
	if not FIXED_LEN then
		local l = {}
		for s = 0, 143 do l[s] = 8 end
		for s = 144, 255 do l[s] = 9 end
		for s = 256, 279 do l[s] = 7 end
		for s = 280, 287 do l[s] = 8 end
		FIXED_LEN = construct(l, 288)
		local d = {}
		for s = 0, 29 do d[s] = 5 end
		FIXED_DIST = construct(d, 30)
	end
	return FIXED_LEN, FIXED_DIST
end

--- Décompresse un flux deflate brut commençant à l'octet `start` de `data`. Renvoie out (octets 1..n), n.
local function inflate(data, start)
	local pos, bitbuf, bitcnt, size = start, 0, 0, #data
	local out, n = {}, 0

	local function bits(need)
		while bitcnt < need do
			if pos > size then fail("données compressées tronquées") end
			bitbuf = bor(bitbuf, lshift(byte(data, pos), bitcnt))
			pos = pos + 1
			bitcnt = bitcnt + 8
		end
		local v = band(bitbuf, lshift(1, need) - 1)
		bitbuf = rshift(bitbuf, need)
		bitcnt = bitcnt - need
		return v
	end

	local function decode(h)
		local count, symbol = h.count, h.symbol
		local code, first, index = 0, 0, 0
		for len = 1, MAXBITS do
			if bitcnt == 0 then
				if pos > size then fail("données compressées tronquées") end
				bitbuf = byte(data, pos)
				pos = pos + 1
				bitcnt = 8
			end
			code = bor(code, band(bitbuf, 1))
			bitbuf = rshift(bitbuf, 1)
			bitcnt = bitcnt - 1
			local c = count[len]
			if code - c < first then return symbol[index + code - first] end
			index = index + c
			first = (first + c) * 2
			code = code * 2
		end
		fail("code de Huffman invalide")
	end

	repeat
		local last = bits(1)
		local btype = bits(2)
		if btype == 0 then -- bloc stocké : on abandonne les bits restants de l'octet courant
			bitbuf, bitcnt = 0, 0
			if pos + 3 > size then fail("bloc stocké tronqué") end
			local len = byte(data, pos) + byte(data, pos + 1) * 256
			pos = pos + 4
			if pos + len - 1 > size then fail("bloc stocké tronqué") end
			for i = 0, len - 1 do out[n + i + 1] = byte(data, pos + i) end
			n = n + len
			pos = pos + len
		else
			local lencode, distcode
			if btype == 1 then
				lencode, distcode = fixed_tables()
			elseif btype == 2 then
				local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
				if nlen > 286 or ndist > 30 then fail("table de Huffman invalide") end
				local cl = {}
				for i = 1, 19 do cl[CLORDER[i]] = i <= ncode and bits(3) or 0 end
				local clcode = construct(cl, 19)
				local ll, index, total = {}, 0, nlen + ndist
				while index < total do
					local sym = decode(clcode)
					if sym < 16 then
						ll[index] = sym
						index = index + 1
					else
						local len, rep = 0
						if sym == 16 then
							if index == 0 then fail("répétition sans longueur précédente") end
							len, rep = ll[index - 1], 3 + bits(2)
						elseif sym == 17 then
							rep = 3 + bits(3)
						else
							rep = 11 + bits(7)
						end
						if index + rep > total then fail("trop de longueurs de codes") end
						for _ = 1, rep do
							ll[index] = len
							index = index + 1
						end
					end
				end
				local lit, dist = {}, {}
				for i = 0, nlen - 1 do lit[i] = ll[i] end
				for i = 0, ndist - 1 do dist[i] = ll[nlen + i] end
				lencode, distcode = construct(lit, nlen), construct(dist, ndist)
			else
				fail("type de bloc invalide")
			end
			while true do
				local sym = decode(lencode)
				if sym < 256 then
					n = n + 1
					out[n] = sym
				elseif sym == 256 then
					break
				else
					sym = sym - 257
					if sym >= 29 then fail("longueur invalide") end
					local len = LBASE[sym + 1] + bits(LEXT[sym + 1])
					local dsym = decode(distcode)
					if dsym >= 30 then fail("distance invalide") end
					local d = DBASE[dsym + 1] + bits(DEXT[dsym + 1])
					if d > n then fail("distance trop grande") end
					local from = n - d
					for i = 1, len do out[n + i] = out[from + i] end -- copies qui se chevauchent : voulu
					n = n + len
				end
			end
		end
	until last == 1
	return out, n
end

--- Décompresse un flux zlib (en-tête de 2 octets vérifié, somme Adler-32 ignorée).
function M.zlib_decompress(data)
	local cmf, flg = byte(data, 1), byte(data, 2)
	if not cmf or not flg or band(cmf, 15) ~= 8 or (cmf * 256 + flg) % 31 ~= 0 or band(flg, 0x20) ~= 0 then
		fail("en-tête zlib invalide")
	end
	return inflate(data, 3)
end

---------------------------------------------------------------------------------------------------------------
-- PNG
---------------------------------------------------------------------------------------------------------------

local SIG = "\137PNG\r\n\26\n"
local CHANNELS = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }
local DEPTHS = { [0] = { 1, 2, 4, 8, 16 }, [2] = { 8, 16 }, [3] = { 1, 2, 4, 8 }, [4] = { 8, 16 }, [6] = { 8, 16 } }
local ADAM7 = { { 0, 0, 8, 8 }, { 4, 0, 8, 8 }, { 0, 4, 4, 8 }, { 2, 0, 4, 4 }, { 0, 2, 2, 4 }, { 1, 0, 2, 2 },
	{ 0, 1, 1, 2 } }

local function u32(s, i)
	local a, b, c, d = byte(s, i, i + 3)
	return ((a * 256 + b) * 256 + c) * 256 + d
end

local function u16(s, i)
	local a, b = byte(s, i, i + 1)
	return a * 256 + b
end

local function decode_png(data)
	local size, pos = #data, 9
	local w, h, depth, ctype, interlace, plte, trns
	local idat = {}
	while pos + 7 <= size do
		local len, tag = u32(data, pos), sub(data, pos + 4, pos + 7)
		local body = pos + 8
		if body + len - 1 > size then fail("bloc " .. tag .. " tronqué") end
		if tag == "IHDR" then
			w, h = u32(data, body), u32(data, body + 4)
			depth, ctype = byte(data, body + 8), byte(data, body + 9)
			if byte(data, body + 10) ~= 0 or byte(data, body + 11) ~= 0 then fail("méthode inconnue") end
			interlace = byte(data, body + 12)
		elseif tag == "PLTE" then
			plte = sub(data, body, body + len - 1)
		elseif tag == "tRNS" then
			trns = sub(data, body, body + len - 1)
		elseif tag == "IDAT" then
			idat[#idat + 1] = sub(data, body, body + len - 1)
		elseif tag == "IEND" then
			break
		end
		pos = body + len + 4
	end
	if not w then fail("IHDR absent") end
	if w < 1 or h < 1 or w * h > M.MAX_PIXELS then fail(("taille refusée %dx%d"):format(w, h)) end
	local channels = CHANNELS[ctype]
	if not channels then fail("type de couleur inconnu " .. tostring(ctype)) end
	local depth_ok = false
	for _, d in ipairs(DEPTHS[ctype]) do depth_ok = depth_ok or d == depth end
	if not depth_ok then fail(("profondeur %d invalide pour le type %d"):format(depth, ctype)) end
	if ctype == 3 and not plte then fail("palette absente") end
	if #idat == 0 then fail("IDAT absent") end
	local raw = M.zlib_decompress(table.concat(idat))

	-- conversion d'un échantillon natif en 8 bits et transparence par couleur-clé (tRNS)
	local maxv = depth < 8 and (lshift(1, depth) - 1) or 255
	local key_gray = (ctype == 0 and trns and #trns >= 2) and u16(trns, 1) or nil
	local key_r, key_g, key_b
	if ctype == 2 and trns and #trns >= 6 then key_r, key_g, key_b = u16(trns, 1), u16(trns, 3), u16(trns, 5) end
	local npal = plte and floor(#plte / 3) or 0
	local function to8(v)
		if depth == 16 then return floor(v / 256) end
		if depth < 8 then return floor(v * 255 / maxv + 0.5) end
		return v
	end

	local bits_pp = channels * depth
	local bpp = bits_pp >= 8 and bits_pp / 8 or 1
	local R, G, B, A = {}, {}, {}, {}
	local ptr = 1

	local function sample(row, px, k)
		if depth == 8 then return row[px * channels + k + 1] end
		if depth == 16 then
			local i = (px * channels + k) * 2 + 1
			return row[i] * 256 + row[i + 1]
		end
		local bo = (px * channels + k) * depth
		return band(rshift(row[floor(bo / 8) + 1], 8 - depth - bo % 8), maxv)
	end

	local function pass(pw, ph, x0, y0, dx, dy)
		local stride = floor((pw * bits_pp + 7) / 8)
		local prev, cur = {}, {}
		for i = 1, stride do prev[i] = 0 end
		for y = 0, ph - 1 do
			local ft = raw[ptr]
			if ft == nil or raw[ptr + stride] == nil then fail("données d'image tronquées") end
			ptr = ptr + 1
			for i = 1, stride do
				local x = raw[ptr + i - 1]
				local a = i > bpp and cur[i - bpp] or 0
				if ft == 1 then
					x = x + a
				elseif ft == 2 then
					x = x + prev[i]
				elseif ft == 3 then
					x = x + floor((a + prev[i]) / 2)
				elseif ft == 4 then
					local b = prev[i]
					local c = i > bpp and prev[i - bpp] or 0
					local p = a + b - c
					local pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
					if pa <= pb and pa <= pc then x = x + a elseif pb <= pc then x = x + b else x = x + c end
				elseif ft ~= 0 then
					fail("filtre inconnu " .. tostring(ft))
				end
				cur[i] = x % 256
			end
			ptr = ptr + stride
			local base = (y0 + y * dy) * w + x0 + 1
			for px = 0, pw - 1 do
				local idx = base + px * dx
				if ctype == 0 then
					local v = sample(cur, px, 0)
					local g8 = to8(v)
					R[idx], G[idx], B[idx], A[idx] = g8, g8, g8, (v == key_gray) and 0 or 255
				elseif ctype == 2 then
					local r, g, b = sample(cur, px, 0), sample(cur, px, 1), sample(cur, px, 2)
					R[idx], G[idx], B[idx] = to8(r), to8(g), to8(b)
					A[idx] = (r == key_r and g == key_g and b == key_b) and 0 or 255
				elseif ctype == 3 then
					local i = sample(cur, px, 0)
					if i >= npal then fail("index de palette hors limites") end
					R[idx], G[idx], B[idx] = byte(plte, i * 3 + 1, i * 3 + 3)
					A[idx] = trns and byte(trns, i + 1) or 255
				elseif ctype == 4 then
					local g8 = to8(sample(cur, px, 0))
					R[idx], G[idx], B[idx], A[idx] = g8, g8, g8, to8(sample(cur, px, 1))
				else
					R[idx], G[idx], B[idx] = to8(sample(cur, px, 0)), to8(sample(cur, px, 1)), to8(sample(cur, px, 2))
					A[idx] = to8(sample(cur, px, 3))
				end
			end
			prev, cur = cur, prev
		end
	end

	if interlace == 0 then
		pass(w, h, 0, 0, 1, 1)
	elseif interlace == 1 then
		for _, p in ipairs(ADAM7) do
			local x0, y0, dx, dy = p[1], p[2], p[3], p[4]
			local pw, ph = floor((w - x0 + dx - 1) / dx), floor((h - y0 + dy - 1) / dy)
			if pw > 0 and ph > 0 then pass(pw, ph, x0, y0, dx, dy) end
		end
	else
		fail("entrelacement inconnu")
	end
	return { w = w, h = h, r = R, g = G, b = B, a = A }
end

--- Décode un PNG (chaîne binaire). Renvoie l'image, ou nil et un message.
function M.decode(data)
	if type(data) ~= "string" or sub(data, 1, 8) ~= SIG then return nil, "png: signature absente" end
	local ok, res = pcall(decode_png, data)
	if not ok then return nil, tostring(res) end
	return res
end

return M
