-- Mode « scenarios » (tools/headless/run.sh) : exécute les scénarios un par un, chacun dans sa zone
-- (origine idx*64, 0, 0) et sous délai maximal ; résultats dans <monde>/passionphoto_test_results.json,
-- puis arrêt du serveur. Journal : RUN / OK / ÉCHEC / CONNU / CORRIGÉ / IGNORÉ, puis BILAN.
local T = passionphoto_test

local files = core.get_dir_list(T.modpath .. "/scenarios", false) or {}
table.sort(files)
for _, f in ipairs(files) do
	if f:sub(-4) == ".lua" then dofile(T.modpath .. "/scenarios/" .. f) end
end

local filter = core.settings:get("passionphoto_test.filter") or ""
local verbose = core.settings:get_bool("passionphoto_test.verbose", false)
local results = { passed = 0, failed = 0, known = 0, skipped = 0, complete = false,
	engine = core.get_version().string, filter = filter, scenarios = {} }

local function write_results()
	local json, err = core.write_json(results)
	if not json then
		T.log("ERREUR résultats non sérialisables : " .. tostring(err))
		json = '{"complete":false}'
	end
	core.safe_file_write(core.get_worldpath() .. "/passionphoto_test_results.json", json)
end

local run_scenario

local function finish()
	if results.passed + results.failed + results.known + results.skipped == 0 then
		results.failed = 1
		T.log(("ÉCHEC  aucun scénario ne correspond au filtre %q"):format(filter))
	end
	results.complete = true
	T.log(("BILAN %d réussi(s), %d échec(s), %d connu(s), %d ignoré(s) — moteur %s"):format(
		results.passed, results.failed, results.known, results.skipped, results.engine))
	write_results()
	core.request_shutdown("passionphoto_test terminé", false, 0)
end

local function run_next(idx)
	run_scenario(idx + 1)
end

run_scenario = function(idx)
	local sc = T.scenarios[idx]
	if not sc then return finish() end
	if filter ~= "" and not sc.name:find(filter, 1, true) then return run_next(idx) end

	T.reset_records()
	local ctx = T.new_context(sc.name, vector.new(idx * 64, 0, 0))
	local record = { name = sc.name, status = "running", messages = ctx.messages, metrics = ctx.metrics,
		photos = ctx.photos, known_bug = sc.opts.known_bug }
	results.scenarios[#results.scenarios + 1] = record
	local started = core.get_us_time()
	local timeout = sc.opts.timeout or 30
	local done, cancel = false, nil

	local function conclude(ok, err)
		if done then return end
		done = true
		if cancel then cancel() end
		local cok, cerr = pcall(ctx.cleanup, ctx)
		if not cok then
			ok, err = false, "nettoyage : " .. tostring(cerr)
		end
		record.duration = (core.get_us_time() - started) / 1e6
		local d = ("(%.1f s)"):format(record.duration)
		if type(err) == "table" and err.__skip then
			record.status, record.error = "skip", err.msg
			results.skipped = results.skipped + 1
			T.log(("IGNORÉ %s %s — %s"):format(sc.name, d, err.msg))
		else
			if type(err) == "table" then err = err.msg end
			local passed = ok and #ctx.failures == 0
			if not passed then record.error = err or table.concat(ctx.failures, "\n") end
			if sc.opts.known_bug then
				if passed then
					record.status = "fixed"
					results.failed = results.failed + 1
					T.log(("CORRIGÉ %s %s — passer ce scénario en T.register et cocher le bug dans docs/PLAN.md")
						:format(sc.name, d))
				else
					record.status = "known"
					results.known = results.known + 1
					T.log(("CONNU  %s %s"):format(sc.name, d))
				end
			elseif passed then
				record.status = "pass"
				results.passed = results.passed + 1
				T.log(("OK     %s %s"):format(sc.name, d))
			else
				record.status = "fail"
				results.failed = results.failed + 1
				T.log(("ÉCHEC  %s %s"):format(sc.name, d))
			end
			if record.error and (record.status == "fail" or verbose) then
				for line in tostring(record.error):gmatch("[^\n]+") do T.log("       " .. line) end
			end
		end
		write_results()
		core.after(0, run_next, idx)
	end

	T.log("RUN    " .. sc.name)
	cancel = T.run_in_coroutine(function() sc.fn(ctx) end, function(ok, err, co)
		if not ok and type(err) ~= "table" then err = debug.traceback(co, tostring(err)) end
		conclude(ok, err)
	end)
	core.after(timeout, function()
		if not done then conclude(false, ("délai dépassé (%s s)"):format(timeout)) end
	end)
end

core.register_on_mods_loaded(function()
	T.log(("%d scénario(s) chargé(s), filtre=%q"):format(#T.scenarios, filter))
	core.after(0.5, run_scenario, 1)
end)
