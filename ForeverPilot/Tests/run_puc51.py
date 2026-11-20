#!/usr/bin/env python3
# ForeverPilot / Tests/run_puc51.py
#
# ПРОГНАТЬ НАБОР ПОД НАСТОЯЩИМ PUC Lua 5.1, А НЕ ПОД LuaJIT.
#
# Зачем это нужно, написано в Tests/loadcheck.lua: texluajit - это LuaJIT, он
# принимает синтаксис Lua 5.2, которого в клиенте игры нет. Один раз это уже
# стоило неработающего аддона при зелёном наборе: `goto continue` в
# Logic/ActionEngine.lua прошёл проверку и не скомпилировался в игре.
#
# Лексическая проверка диалекта (Tests/dialect.lua) ловит синтаксис, но не
# ловит разницу в ПОВЕДЕНИИ. Этот запуск её закрывает: внутри работает
# настоящая виртуальная машина PUC-Rio Lua 5.1 - та же, что в клиенте.
#
# Запуск (из папки аддона):
#   pip install --break-system-packages lupa      # один раз
#   python3 Tests/run_puc51.py            # весь набор
#   python3 Tests/run_puc51.py real       # плюс проверки на сохранениях игрока
#   python3 Tests/run_puc51.py --suite test_ledger,test_void
#
# Ничего игрового здесь нет: это только второй интерпретатор для тех же файлов.

import os
import sys

try:
    import lupa.lua51 as lua51
except ImportError:
    sys.exit("нет lupa: pip install --break-system-packages lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

args = sys.argv[1:]
suite = None
if "--suite" in args:
    i = args.index("--suite")
    suite = args[i + 1]
    del args[i:i + 2]

runtime = lua51.LuaRuntime(unpack_returned_tuples=True)
version = runtime.eval("_VERSION")
jit = runtime.eval("type(jit)")
print("интерпретатор: %s, jit: %s (это и есть проверка — должно быть nil)"
      % (version, jit))
if jit != "nil":
    sys.exit("!! это LuaJIT, а не PUC Lua — проверка бессмысленна")

# os.exit внутри Lua убил бы процесс Python вместе с отчётом, поэтому он
# подменён на ошибку с кодом, которую мы ловим ниже.
#
# `_G.arg`, А НЕ `arg`. В Lua 5.1 функция, объявленная с `...`, получает
# СОБСТВЕННУЮ локальную `arg` с варargs (совместимость с 5.0 включена в сборке
# по умолчанию). Присваивание `arg = {}` внутри такой функции пишет в эту
# локальную переменную, а не в глобальную, и Tests/run.lua аргумента «real» не
# видел: весь набор проверок на сохранениях игрока (31 раздел) молча не
# запускался, а итог выглядел зелёным.
bootstrap = r"""
local root, entry, want = ...
_G.arg = {}
for a in want:gmatch("[^,]+") do _G.arg[#_G.arg + 1] = a end
local realExit = os.exit
os.exit = function(code) error({ exit = code or 0 }, 0) end
local chunk, err = loadfile(root .. "/Tests/" .. entry)
if not chunk then
    print("!! не загрузился " .. entry .. ": " .. tostring(err))
    return 2
end
local ok, e = pcall(chunk)
os.exit = realExit
if ok then return 0 end
if type(e) == "table" and e.exit ~= nil then return e.exit end
print("!! набор упал: " .. tostring(e))
return 3
"""

if suite:
    os.environ["FP_SUITE"] = suite
    entry, want = "one.lua", ""
else:
    entry, want = "run.lua", ",".join(args)

code = runtime.eval("function(...) " + bootstrap + " end")
rc = code(ROOT, entry, want)
sys.exit(int(rc or 0))
