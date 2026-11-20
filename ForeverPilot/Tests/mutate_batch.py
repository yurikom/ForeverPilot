#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Мутационная проверка ПАРТИЯМИ, с накоплением результата между запусками.

Зачем отдельный файл. Tests/mutate.py прогоняет весь набор на каждую мутацию, и
один полный проход - это 35 мутаций по полминуты, то есть больше 20 минут. Там,
где на один вызов отведено меньше (а в песочнице это ~3 минуты), полный проход
не умещается, и прерванный по таймауту прогон оставляет порчу в рабочем коде -
это уже случалось.

Поэтому здесь: партия из нескольких номеров за запуск, результат копится в
Tests/.mutate_results.json, итог печатается по накопленному. Базовый прогон
делается один раз на партию, а не на мутацию.

ВОССТАНОВЛЕНИЕ - ПЕРВОЕ, ЧТО ДЕЛАЕТ СКРИПТ. Если предыдущий запуск прервали,
оригинал лежит в Tests/.mutate_stash.txt и возвращается на место до любых
других действий. Папка аддона обязана оставаться рабочей в любой момент:
игрок перезагружает интерфейс когда захочет.

    python3 -I Tests/mutate_batch.py 1 2 3      # прогнать мутации 1,2,3
    python3 -I Tests/mutate_batch.py --report   # показать накопленное
    python3 -I Tests/mutate_batch.py --reset    # начать подсчёт заново
"""

import io
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))

# Список мутаций берётся из mutate.py - второго места с ним быть не должно.
_src = io.open(os.path.join(ROOT, "Tests", "mutate.py"), encoding="utf-8").read()
_ns = {"__file__": os.path.join(ROOT, "Tests", "mutate.py"), "__name__": "mutate"}
exec(compile(_src.split("# Прерванный прогон")[0], "mutate.py", "exec"), _ns)
MUTATIONS = _ns["MUTATIONS"]
SUITE = _ns["SUITE"]

RESULTS = os.path.join(ROOT, "Tests", ".mutate_results.json")
STASH = os.path.join(ROOT, "Tests", ".mutate_stash.txt")
STASH_SEP = "\n--[[ ===== ORIGINAL ===== ]]\n"


def restore_stash():
    if not os.path.exists(STASH):
        return
    blob = io.open(STASH, encoding="utf-8").read()
    if STASH_SEP not in blob:
        return
    rel, text = blob.split(STASH_SEP, 1)
    rel = rel.strip()
    if rel:
        io.open(os.path.join(ROOT, rel), "w", encoding="utf-8").write(text)
        print("Восстановлено после прерванного прогона: " + rel)
    io.open(STASH, "w", encoding="utf-8").write("")


def load_results():
    if not os.path.exists(RESULTS):
        return {}
    try:
        return json.load(io.open(RESULTS, encoding="utf-8"))
    except Exception:
        return {}


def save_results(data):
    json.dump(data, io.open(RESULTS, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1, sort_keys=True)


def run_suite():
    p = subprocess.run(SUITE, cwd=ROOT, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    line = ""
    for l in out.splitlines():
        if l.startswith("Итого"):
            line = l.strip()
    if not line:
        tail = out.strip().splitlines()
        return False, "набор не доработал до итога (" + (tail[-1][:80] if tail else "?") + ")"
    # Число провалов разбирается, а не ищется подстрокой: «10 провалено»
    # содержит «0 провалено», и набор с десятью провалами сходил за зелёный.
    # Подробности - в Tests/mutate.py, suite_is_green.
    m = re.search(r"(\d+)\s+провалено", line)
    return (bool(m) and int(m.group(1)) == 0), line


def report(data):
    caught = sorted(int(k) for k, v in data.items() if v.get("caught"))
    missed = sorted(int(k) for k, v in data.items() if not v.get("caught"))
    todo = sorted(m[0] for m in MUTATIONS if str(m[0]) not in data)
    print("")
    print("=" * 68)
    print("Поймано %d, НЕ поймано %d, ещё не прогнано %d (всего мутаций %d)"
          % (len(caught), len(missed), len(todo), len(MUTATIONS)))
    by_num = {m[0]: m[1] for m in MUTATIONS}
    for num in missed:
        print("  НЕ ПОЙМАНА M%d: %s — %s"
              % (num, by_num.get(num, "?"), data[str(num)].get("line", "")))
    if todo:
        print("  Осталось прогнать: " + " ".join(str(n) for n in todo))
    print("=" * 68)
    return len(missed) == 0 and not todo


def main():
    restore_stash()
    args = sys.argv[1:]
    data = load_results()

    if "--reset" in args:
        save_results({})
        print("Накопленный результат сброшен.")
        return 0
    if "--report" in args or not args:
        return 0 if report(data) else 1

    want = [int(a) for a in args if a.isdigit()]
    todo = [m for m in MUTATIONS if m[0] in want]
    if not todo:
        print("Нечего прогонять: номера не найдены.")
        return 2

    ok, line = run_suite()
    print("Исходный код: " + line)
    if not ok:
        print("!! набор не зелёный ДО мутаций — проверка бессмысленна")
        return 2

    for num, what, path, old, new in todo:
        src = io.open(os.path.join(ROOT, path), encoding="utf-8").read()
        if old not in src:
            print("M%-2d %-52s ОПОРА СЪЕХАЛА (%s)" % (num, what, path))
            data[str(num)] = {"caught": False, "line": "опора съехала в " + path}
            save_results(data)
            continue
        io.open(STASH, "w", encoding="utf-8").write(path + STASH_SEP + src)
        io.open(os.path.join(ROOT, path), "w", encoding="utf-8").write(
            src.replace(old, new, 1))
        try:
            good, line = run_suite()
        finally:
            io.open(os.path.join(ROOT, path), "w", encoding="utf-8").write(src)
            io.open(STASH, "w", encoding="utf-8").write("")
        data[str(num)] = {"caught": (not good), "line": line, "what": what}
        save_results(data)
        print("M%-2d %-52s %s   %s"
              % (num, what, "поймана   " if not good else "НЕ ПОЙМАНА", line))

    report(data)
    ok, line = run_suite()
    print("Код после партии: " + line)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
