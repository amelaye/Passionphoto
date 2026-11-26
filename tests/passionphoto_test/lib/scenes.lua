-- Scènes de référence pour juger le rendu des photos : construites de façon déterministe autour de l'origine
-- d'un scénario avec des nœuds de minetest_game. Chaque scène renvoie un point de vue
-- { eye, target, yaw, pitch } (œil de l'appareil, cible, angles en radians, conventions du moteur).
local T = passionphoto_test
T.scenes = {}

local function pick(...)
	for _, n in ipairs({ ... }) do
		if core.registered_nodes[n] then return n end
	end
	return "default:stone"
end

--- Angles (lacet, tangage) du regard de `eye` vers `target`, conventions de get_look_horizontal/vertical.
function T.look_angles(eye, target)
	local d = vector.subtract(target, eye)
	local len = vector.length(d)
	local yaw = math.atan2(-d.x, d.z)
	if yaw < 0 then yaw = yaw + 2 * math.pi end
	return yaw, -math.asin(d.y / len)
end

local function view(eye, target)
	local yaw, pitch = T.look_angles(eye, target)
	return { eye = eye, target = target, yaw = yaw, pitch = pitch }
end

--- Premier nœud solide ou liquide en descendant de ytop à ybottom en (x, z) ; nil si rien ou zone non chargée.
function T.surface_y(x, z, ytop, ybottom)
	for y = ytop, ybottom, -1 do
		local n = core.get_node(vector.new(x, y, z))
		if n.name == "ignore" then return nil end
		local def = core.registered_nodes[n.name]
		if def and (def.walkable or (def.liquidtype or "none") ~= "none") then return y end
	end
	return nil
end

--- Studio : sol de pierre, pelouse devant, mur du fond en bandes de laine colorée, arbre, bassin d'eau,
-- verre, sable, torche. L'appareil est à 9 nœuds du centre, face au mur (direction +Z).
-- Le volume de la scène est vidé d'abord ; dans un monde généré, la construire en altitude (ciel et soleil).
function T.scenes.studio(ctx)
	ctx:prepare()
	local function P(x, y, z) return ctx:p(x, y, z) end
	ctx:fill(P(-11, 0, -11), P(11, 12, 11), "air")
	ctx:fill(P(-11, -2, -11), P(11, -2, 11), pick("default:stone"))
	ctx:fill(P(-11, -1, -11), P(11, -1, 11), pick("default:stone"))
	ctx:fill(P(-11, -1, -11), P(11, -1, -4), pick("default:dirt_with_grass"))
	local wools = { "red", "orange", "yellow", "green", "cyan", "blue", "violet", "magenta", "white", "grey", "black" }
	for i, w in ipairs(wools) do
		local x0 = -11 + 2 * (i - 1)
		ctx:fill(P(x0, 0, 8), P(x0 + 1, 6, 8), pick("wool:" .. w, "default:stone"))
	end
	-- arbre à gauche
	ctx:fill(P(-9, 3, 1), P(-5, 6, 5), pick("default:leaves"))
	ctx:fill(P(-7, 0, 3), P(-7, 4, 3), pick("default:tree"))
	-- bassin d'eau au centre
	ctx:fill(P(-2, -1, -1), P(2, -1, 3), pick("default:water_source"))
	-- verre, sable, briques, torche
	ctx:fill(P(5, 0, 1), P(5, 1, 1), pick("default:glass"))
	ctx:fill(P(6, -1, -2), P(9, -1, 2), pick("default:sand"))
	ctx:fill(P(7, 0, 4), P(9, 2, 4), pick("default:brick"))
	ctx:set(P(3, 0, 5), pick("default:torch"), 1)
	return view(vector.add(P(0, 0, -9), vector.new(0, 1.6, 0)), vector.add(P(0, 2, 8), vector.new(0, 0.5, 0)))
end

--- Paysage : le terrain généré par le mapgen (scénario lancé avec -g v7, graine PP_SEED). Sans `spot` : œil au
-- centre de la zone du scénario, regard vers +Z légèrement plongeant. Avec spot = { x, z, yaw°, pitch° } : point
-- de vue fixe (repéré avec le serveur de dev, même graine). Renvoie nil si la colonne n'a pas de sol.
function T.scenes.paysage(ctx, spot)
	local o = spot and vector.new(spot.x, 0, spot.z) or ctx.origin
	local done = false
	core.emerge_area(vector.offset(o, -96, -32, -96), vector.offset(o, 96, 112, 96), function(_, _, remaining)
		if remaining == 0 then done = true end
	end)
	ctx:assert(ctx:wait_until(function() return done end, 90, 0.1), "génération du paysage trop longue")
	local y = T.surface_y(o.x, o.z, 112, -32)
	if not y then return nil end
	local eye = vector.new(o.x, y + 0.5 + 1.625, o.z)
	if spot and spot.yaw then
		return { eye = eye, yaw = math.rad(spot.yaw), pitch = math.rad(spot.pitch or 0) }
	end
	return view(eye, vector.offset(eye, 0, -6, 40))
end
