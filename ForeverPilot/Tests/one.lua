-- ForeverPilot / Tests/one.lua
--
-- Прогнать ОДИН набор, не дожидаясь остальных. Нужно только при разработке:
-- полный прогон занимает минуты, а менять за раз приходится один файл.
--
--   FP_SUITE=test_risk texluajit Tests/one.lua
--
-- Имя набора берётся из переменной окружения FP_SUITE (texluajit не передаёт
-- аргументы так, как обычный lua, поэтому именно переменная). Ничто в игре
-- этот файл не загружает: Tests/ в .toc не упоминается.

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\]one%.lua$") or "."

local H = assert(loadfile(dir .. "/harness.lua"))()

local names = {}
for name in (os.getenv("FP_SUITE") or "test_risk"):gmatch("[^,%s]+") do
    names[#names + 1] = name
end
if os.getenv("FP_VERBOSE") then H.verbose = true end

print("ForeverPilot — набор(ы): " .. table.concat(names, ", ")
    .. " (" .. _VERSION .. ")")
print("База предметов: " .. H.itemDBSourceText())
print(string.rep("=", 64))

for _, name in ipairs(names) do
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
