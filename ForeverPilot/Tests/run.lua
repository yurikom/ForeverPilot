-- ForeverPilot / Tests/run.lua
-- Entry point. Run from the addon folder:  lua Tests/run.lua
-- Add  real  to also run the integration test against the live SavedVariables.

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\]run%.lua$") or "."

local H = assert(loadfile(dir .. "/harness.lua"))()

-- test_load идёт ПЕРВЫМ, и это не вкусовщина: он отвечает на вопрос «а аддон
-- вообще загрузится в игре», и если нет - остальные 3000 проверок рассказывают
-- про код, которого в клиенте не существует. Ровно так и было с `goto` в
-- Logic\ActionEngine.lua: набор был зелёным, а аддон не работал совсем.
local suites = { "test_load",
                 "test_planner", "test_cost", "test_stats", "test_rank",
                 "test_nav", "test_diag", "test_ui", "test_regress",
                 "test_skillcap", "test_bugs", "test_economy", "test_schools",
                 "test_audit", "test_live", "test_swap", "test_risk",
                 "test_text", "test_wanted", "test_ahead", "test_alive",
                 "test_auction", "test_growth", "test_sources",
                 "test_arbitrage", "test_market", "test_favor", "test_camp",
                 "test_assistant", "test_handoff", "test_vanish",
                 "test_recipe", "test_confirm", "test_nonsense",
                 "test_void", "test_ledger", "test_anyclass",
                 "test_ceiling", "test_appearance", "test_quiet", "test_aware",
                 "test_sense" }

-- Arguments arrive two different ways depending on the interpreter: plain lua
-- hands them to the chunk as `...`, while texluajit (the one this project tests
-- on) leaves `...` empty and fills the global `arg` table instead. Read both,
-- or `run.lua real` silently runs without the integration suite - which is
-- exactly what it did until this was noticed.
local args = {}
for _, a in ipairs({ ... }) do args[#args + 1] = a end
if type(arg) == "table" then
    for i = 1, #arg do args[#args + 1] = arg[i] end
end

local wantReal = false
for _, a in ipairs(args) do
    if a == "real" then wantReal = true end
    if a == "-v" then H.verbose = true end
end
if wantReal then suites[#suites + 1] = "test_real" end

print("ForeverPilot - юнит-тесты (" .. _VERSION .. ")")
print("База предметов: " .. H.itemDBSourceText())
print(string.rep("=", 64))

for _, name in ipairs(suites) do
    local path = dir .. "/" .. name .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then
        print("!! не загрузился набор " .. name .. ": " .. tostring(err))
        H.failed = H.failed + 1
        H.failures[#H.failures + 1] = name .. " (не загрузился)"
    else
        local body = chunk(H)
        local ok, runErr = pcall(body)
        if not ok then
            print("!! набор " .. name .. " упал: " .. tostring(runErr))
            H.failed = H.failed + 1
            H.failures[#H.failures + 1] = name .. " (упал: " .. tostring(runErr) .. ")"
        end
    end
end

local pass = H.summary()
os.exit(pass and 0 or 1)
