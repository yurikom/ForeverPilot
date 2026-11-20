-- ForeverPilot / Tests/_run_nocap.lua
--
-- Runs ONLY the suites that existed before the skill-ceiling work, with
-- test_skillcap deliberately left out. The point is a clean regression number:
-- if this file prints a different total from the one recorded below, something
-- in the old behaviour moved.
--
--   before the skill-ceiling change:  1099 passed, 0 failed
--   after:                            1100 passed, 0 failed
--   after the dismissal fix:          1299 passed, 0 failed
--
-- The jump to 1236 is new assertions only: the dismissal regression suite, the
-- per-branch reasons, the profession de-duplication and the empty-state rules.
-- No old check was dropped or loosened.
--
-- The one extra check is in test_rank.lua. That suite used to assert the card
-- for a capped profession says "нужен тренер"; it now asserts the card says the
-- ceiling rises as the game goes on AND that it does not mention a trainer, so
-- one assertion became two. No old check was dropped.
--
-- Run with:  texluajit Tests/_run_nocap.lua   (from the addon folder)
-- The full set, including the new suite, is Tests/run.lua.
--
-- Nothing loads this file in game: Tests/ is not referenced from the .toc.
-- Safe to delete.

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]+%.lua$") or "."

local H = assert(loadfile(dir .. "/harness.lua"))()

local suites = { "test_planner", "test_cost", "test_stats", "test_rank",
                 "test_nav", "test_diag", "test_ui", "test_regress" }

for _, a in ipairs({ ... }) do
    if a == "-v" then H.verbose = true end
end

print("ForeverPilot - юнит-тесты БЕЗ набора про потолок навыка (" .. _VERSION .. ")")
print(string.rep("=", 64))

for _, name in ipairs(suites) do
    local chunk, err = loadfile(dir .. "/" .. name .. ".lua")
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
