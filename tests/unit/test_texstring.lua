-- Analyse des chaînes de texture (src/lib/texstring.lua).
local T = ...
local ts = dofile(T.root .. "/src/lib/texstring.lua")

T.describe("texstring", function()
	T.it("fichier simple", function()
		T.deep_eq(ts.parse("default_stone.png"), { { kind = "file", name = "default_stone.png" } })
	end)

	T.it("superpositions et modificateurs, de gauche à droite", function()
		local s = ts.parse("default_dirt.png^default_grass_side.png^[colorize:#ff0000:128")
		T.eq(#s, 3)
		T.eq(s[2].name, "default_grass_side.png")
		T.eq(s[3].kind, "mod")
		T.eq(s[3].name, "colorize")
		T.eq(s[3].args, "#ff0000:128")
	end)

	T.it("groupes entre parenthèses", function()
		local s = ts.parse("a.png^(b.png^[multiply:#00ff00)^[opacity:200")
		T.eq(#s, 3)
		T.eq(s[2].kind, "group")
		T.eq(s[2].steps[1].name, "b.png")
		T.eq(s[2].steps[2].name, "multiply")
		T.eq(s[3].args, "200")
	end)

	T.it("modificateur sans argument et générateur en tête", function()
		T.deep_eq(ts.parse("[combine:16x16:0,0=a.png:0,8=b.png^[noalpha"), {
			{ kind = "mod", name = "combine", args = "16x16:0,0=a.png:0,8=b.png" },
			{ kind = "mod", name = "noalpha", args = "" },
		})
	end)

	T.it("échappements : texture imbriquée dans [combine", function()
		local s = ts.parse("a.png^[combine:16x16:0,0=b.png\\^[colorize\\:red")
		T.eq(#s, 2, "le ^ échappé ne coupe pas")
		T.eq(s[2].args, "16x16:0,0=b.png^[colorize:red", "arguments déséchappés")
		T.eq(#ts.split_top("a\\^b^c", "^"), 2)
	end)

	T.it("liste des fichiers utilisés", function()
		T.deep_eq(ts.files("a.png^(b.png^[colorize:red)^[combine:4x4:0,0=c.png:1,1=a.png"), { "a.png", "b.png", "c.png" })
		T.deep_eq(ts.files(""), {})
	end)
end)
