-- Auto-test du cadre : les assertions détectent bien les écarts.
local T = ...

T.describe("cadre de test", function()
	T.it("eq, near, ok, contains acceptent les valeurs correctes", function()
		T.eq(1 + 1, 2)
		T.near(0.1 + 0.2, 0.3, 1e-9)
		T.ok(true)
		T.contains("pellicule couleur", "couleur")
		T.deep_eq({ a = { 1, 2 } }, { a = { 1, 2 } })
	end)

	T.it("les assertions lèvent une erreur sur un écart", function()
		T.raises(function() T.eq(1, 2) end, "attendu 2")
		T.raises(function() T.near(1, 2, 0.5) end, "±0.5")
		T.raises(function() T.ok(false, "message") end, "message")
		T.raises(function() T.contains("abc", "z") end)
		T.raises(function() T.deep_eq({ 1 }, { 2 }) end)
	end)
end)
