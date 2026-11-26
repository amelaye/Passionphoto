-- Décodeur PNG (src/lib/png.lua) contre les images de tools/gen_png_fixtures.py (attendu connu par construction),
-- puis contre toutes les textures de minetest_game si .deps/ est présent.
local T = ...
local png = dofile(T.root .. "/src/lib/png.lua")
local FIX = T.root .. "/tests/unit/fixtures/png/"

local function read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local d = f:read("*a")
	f:close()
	return d
end

local function to_hex(img)
	local parts = {}
	for i = 1, img.w * img.h do
		parts[i] = ("%02x%02x%02x%02x"):format(img.r[i], img.g[i], img.b[i], img.a[i])
	end
	return table.concat(parts)
end

T.describe("png", function()
	for _, case in ipairs(dofile(FIX .. "expected.lua")) do
		T.it("décode " .. case.file, function()
			local img, err = png.decode(read(FIX .. case.file))
			T.ok(img, err)
			T.eq(img.w, case.w, "largeur")
			T.eq(img.h, case.h, "hauteur")
			local got = to_hex(img)
			if got ~= case.rgba then
				for i = 1, #got, 8 do
					if got:sub(i, i + 7) ~= case.rgba:sub(i, i + 7) then
						error(("pixel %d : attendu %s, obtenu %s"):format((i - 1) / 8, case.rgba:sub(i, i + 7),
							got:sub(i, i + 7)))
					end
				end
			end
		end)
	end

	T.it("refuse proprement les données invalides", function()
		T.eq(png.decode("pas un png"), nil)
		T.eq(png.decode(nil), nil)
		local data = read(FIX .. "rgba8_filtres.png")
		local img, err = png.decode(data:sub(1, 60))
		T.eq(img, nil, "PNG tronqué refusé")
		T.contains(err, "png:")
	end)

	local p = io.popen('ls "' .. T.root .. '"/.deps/games/minetest/mods/*/textures/*.png 2>/dev/null')
	local files = {}
	for f in p:lines() do files[#files + 1] = f end
	p:close()
	if #files > 0 then
		T.it(("décode les %d textures de minetest_game"):format(#files), function()
			for _, f in ipairs(files) do
				local data = read(f)
				local img, err = png.decode(data)
				T.ok(img, f .. " : " .. tostring(err))
				T.eq(#img.r, img.w * img.h, f .. " : nombre de pixels")
			end
		end)
	end
end)
