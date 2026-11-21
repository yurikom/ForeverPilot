#!/usr/bin/env python3
# ForeverPilot / Tests/preview.py
#
# КАРТИНКА ОКНА БЕЗ ИГРЫ.
#
# Проверки разметки отвечают «ничто ни на что не налезает», но не отвечают «как
# это выглядит» - а игрок жаловался именно на вид («топорно», «буквы мелкие,
# нечитабельные», «всё на всё налазит»). Запустить игру отсюда нельзя, поэтому
# окно рисуется по тем же рамкам, которые аддон создаёт в заглушке клиента
# (Tests/uistub.lua): где что привязано, какого цвета, какой текст, какая
# картинка.
#
# С ключом --media окно рисуется так, как после полного перезапуска игры: своим
# шрифтом (Fira Sans из Media/Fonts) и своими значками (Media/icon-*.tga). Шрифт
# здесь настоящий, и мерки текста аддону отдаются настоящие - поэтому что
# влезло, что перенеслось и что укоротилось, на картинке то же, что будет в
# игре. Без ключа - вид до перезапуска: шрифты игры (здесь их заменяет DejaVu)
# и без значков. Иконки предметов из самой игры - условные цветные квадраты.
#
# Запуск (из папки аддона):
#   python3 Tests/preview.py out.png --media               # выдуманный мир из тестов
#   python3 Tests/preview.py out.png --media --real        # сохранения игрока (FP_WTF)
#   python3 Tests/preview.py out.png --tab CHAR --size 860x480 --pick 6 --chip GOLD
#
# Ничего игрового здесь нет: это только второй способ посмотреть на разметку.

import os
import re
import sys

import lupa.lua51 as lua51
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

args = sys.argv[1:]
out = args[0] if args and not args[0].startswith("--") else "preview.png"
real = "--real" in args
tab = args[args.index("--tab") + 1] if "--tab" in args else "NOW"
size = args[args.index("--size") + 1] if "--size" in args else "960x580"
pick = int(args[args.index("--pick") + 1]) if "--pick" in args else 0
chip = args[args.index("--chip") + 1] if "--chip" in args else None
profile = args[args.index("--profile") + 1] if "--profile" in args else None
recipe = int(args[args.index("--recipe") + 1]) if "--recipe" in args else 0
ready = "--media" in args
W, H = (int(v) for v in size.split("x"))
SCALE = 2

# ШРИФТЫ ------------------------------------------------------------------
#
# Свои - из таблицы W.FONTS в UI/Widgets.lua (имя объекта шрифта, файл, размер):
# читаются оттуда, чтобы картинка не разошлась с кодом. Шрифты игры заменяет
# DejaVu Sans Condensed - у него похожая ширина знака.
FONT_SPACING = 2          # font:SetSpacing(2) в W.InitFonts
OWN_FONTS = {}
with open(os.path.join(ROOT, "UI", "Widgets.lua"), encoding="utf-8") as fh:
    for m in re.finditer(r'\{\s*"FONT_\w+",\s*"(\w+)",\s*"([\w\-\.]+)",\s*([\d\.]+)', fh.read()):
        OWN_FONTS[m.group(1)] = (os.path.join(ROOT, "Media", "Fonts", m.group(2)), float(m.group(3)))
DEJAVU = "/usr/share/fonts/truetype/dejavu/"
GAME_FONTS = {
    "GameFontNormalLarge": (DEJAVU + "DejaVuSansCondensed-Bold.ttf", 15.0),
    "GameFontNormal": (DEJAVU + "DejaVuSansCondensed-Bold.ttf", 11.5),
    "GameFontHighlight": (DEJAVU + "DejaVuSansCondensed.ttf", 11.5),
    "GameFontDisable": (DEJAVU + "DejaVuSansCondensed.ttf", 11.5),
    "GameFontHighlightSmall": (DEJAVU + "DejaVuSansCondensed.ttf", 9.8),
    "GameFontDisableSmall": (DEJAVU + "DejaVuSansCondensed.ttf", 9.8),
}
DEFAULT_COLOR = {"GameFontNormalLarge": (1, 0.82, 0), "GameFontNormal": (1, 0.82, 0),
                 "GameFontHighlight": (1, 1, 1), "GameFontDisable": (0.5, 0.5, 0.5),
                 "GameFontHighlightSmall": (1, 1, 1), "GameFontDisableSmall": (0.5, 0.5, 0.5)}
_fonts = {}


def font_def(name):
    name = str(name or "")
    if name in OWN_FONTS:
        return OWN_FONTS[name], True
    return GAME_FONTS.get(name, GAME_FONTS["GameFontHighlight"]), False


def font(name):
    (path, px), _ = font_def(name)
    key = (path, px)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, int(round(px * SCALE)))
    return _fonts[key]


CODES = re.compile(r"\|c[0-9a-fA-F]{8}|\|r")


def plain(text):
    return CODES.sub("", str(text or ""))


def measure(text, name):
    return font(name).getlength(plain(text)) / SCALE


def line_height(name):
    (_, px), own = font_def(name)
    # Клиент ставит строки с шагом «высота шрифта плюс интервал»; интервал
    # аддон задаёт только своим шрифтам (font:SetSpacing в W.InitFonts).
    return px + (FONT_SPACING if own else 0)


def wrap_lines(text, fnt, width):
    lines = []
    for para in text.split("\n"):
        words, cur = para.split(" "), ""
        for w in words:
            trial = (cur + " " + w) if cur else w
            if fnt.getlength(trial) <= width or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
    return lines


def measure_wrap(para, name, width):
    return max(1, len(wrap_lines(plain(para), font(name), float(width) * SCALE)))


LUA = r'''
return function(ROOT, opts, measure, lineHeight, measureWrap)
    local real, tab, W, Hh, pick, chip = opts.real, opts.tab, opts.W, opts.H, opts.pick, opts.chip
    local H = assert(loadfile(ROOT .. "/Tests/harness.lua"))()
    H.ROOT = ROOT
    local S = assert(loadfile(ROOT .. "/Tests/uistub.lua"))(H)
    S.measure, S.measureLine, S.measureWrap = measure, lineHeight, measureWrap
    S.FORCE_MEDIA = opts.media and true or false
    local env
    if real then
        local captured
        local proxyH = setmetatable({ load = function(o)
            local e = H.load(o); captured = captured or e; return e end }, { __index = H })
        local chunk = assert(loadfile(ROOT .. "/Tests/inspect_real.lua"))
        local sandbox = setmetatable({
            print = function() end,
            os = setmetatable({ exit = function() error("exit", 0) end }, { __index = os }),
            io = setmetatable({ write = function() end }, { __index = io }),
            loadfile = function(p, ...)
                if type(p) == "string" and p:match("[/\\]harness%.lua$") then
                    return function() return proxyH end
                end
                return loadfile(p, ...)
            end,
        }, { __index = _G })
        setfenv(chunk, sandbox)
        pcall(chunk)
        env = assert(captured, "настоящий мир не собран: задайте FP_WTF и FP_ADDONS")
        S.attachUI(H, env)
        if opts.profile then env.ns.Config:SetProfile(opts.profile) end
        H.build(env)
    else
        env = S.load(H)
        S.populate(env, H)
        if opts.profile then
            env.ns.Config:SetProfile(opts.profile)
            H.build(env)
        end
    end
    local ns = env.ns
    ns.Config:SaveFrame("CENTER", "CENTER", 0, 0, W, Hh)
    ns.MainFrame:Build()
    ns.MainFrame:ApplyPosition()
    if chip then ns.Config:SetChip(chip) end
    if opts.recipe and opts.recipe > 0 then ns.TabCraft.selected = opts.recipe end
    ns.MainFrame:Select(tab)
    S.layout(env, W, Hh)
    ns.MainFrame:RenderActive()
    ns.MainFrame:UpdateStatus()
    if tab == "NOW" and pick > 0 then
        local rows = {}
        for _, row in ipairs(ns.Card.pool) do
            if row.__shown and row.card then rows[#rows + 1] = row end
        end
        table.sort(rows, function(a, b)
            return S.rectOf(a, ns.TabNow.content).top > S.rectOf(b, ns.TabNow.content).top
        end)
        if rows[pick] then S.pick(ns, rows[pick]) end
    end

    local root = ns.MainFrame.frame
    -- Прямоугольник по ВСЕМ привязкам, а не по первой: рамка, растянутая двумя
    -- точками, получает ширину из них, как в клиенте.
    local memo = {}
    local function rect(el, depth)
        if memo[el] ~= nil then return memo[el] or nil end
        depth = (depth or 0) + 1
        if depth > 24 then return nil end
        local r
        if el == root then
            r = { l = 0, t = 0, r = W, b = Hh }
        elseif el.__parent and el.__parent.__type == "ScrollFrame"
            and el.__parent.__scrollChild == el then
            -- Содержимое списка: стоит в левом верхнем углу окна прокрутки,
            -- сдвинутое на текущую прокрутку.
            local o = rect(el.__parent, depth)
            local w, h = S.sizeOf(el)
            local off = tonumber(el.__parent.__vscroll) or 0
            if o then r = { l = o.l, t = o.t - off, r = o.l + w, b = o.t - off + h } end
        elseif el.__allPoints then
            local other = (type(el.__allPoints) == "table") and el.__allPoints or el.__parent
            local o = other and rect(other, depth)
            if o then r = { l = o.l, t = o.t, r = o.r, b = o.b } end
        else
            local w, h = S.sizeOf(el)
            local L, R, T, B, CX, CY
            for _, p in ipairs(S.pointsOf(el)) do
                local o = p.rel and rect(p.rel, depth)
                if o then
                    local ox
                    if p.relPoint:find("LEFT") then ox = o.l
                    elseif p.relPoint:find("RIGHT") then ox = o.r
                    else ox = (o.l + o.r) / 2 end
                    ox = ox + p.x
                    local oy
                    if p.relPoint:find("TOP") then oy = o.t
                    elseif p.relPoint:find("BOTTOM") then oy = o.b
                    else oy = (o.t + o.b) / 2 end
                    oy = oy - p.y
                    if p.point:find("LEFT") then L = L or ox
                    elseif p.point:find("RIGHT") then R = R or ox
                    else CX = CX or ox end
                    if p.point:find("TOP") then T = T or oy
                    elseif p.point:find("BOTTOM") then B = B or oy
                    else CY = CY or oy end
                end
            end
            if L and R then w = R - L end
            if T and B then h = B - T end
            local left = L or (R and R - w) or (CX and CX - w / 2)
            local top = T or (B and B - h) or (CY and CY - h / 2)
            if left and top then r = { l = left, t = top, r = left + w, b = top + h } end
        end
        memo[el] = r or false
        return r
    end
    local function visible(f)
        local node, seen = f, {}
        while node do
            if seen[node] then return false end
            seen[node] = true
            if node == root then return true end
            if not node.__shown then return false end
            node = node.__parent
        end
        return false
    end
    -- Список прокручивается: что не попало в его окно, на экране не видно.
    local function clip(f)
        local node = f.__parent
        while node and node ~= root do
            local scroll = node.__parent
            if scroll and scroll.__type == "ScrollFrame" and scroll.__scrollChild == node then
                return rect(scroll)
            end
            node = node.__parent
        end
        return nil
    end
    local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
    local out = {}
    for index, f in ipairs(env.world.frames) do
        if (f.__type == "Texture" or f.__type == "FontString") and S.descends(f, root)
            and f.__shown ~= false and f.__parent and visible(f.__parent)
            and f.__layer ~= "HIGHLIGHT" then
            local r = rect(f)
            local c = clip(f)
            if r and c and (r.b < c.t + 0.5 or r.t > c.b - 0.5) then r = nil end
            if r then
                local item = { index = index, kind = f.__type, l = r.l, t = r.t, r = r.r, b = r.b,
                               layer = LAYER[f.__layer or ""] or 3 }
                if c then item.clipT, item.clipB = c.t, c.b end
                -- Глубина владельца: дочерняя рамка рисуется поверх родительской.
                local depth, level, node = 0, 0, f.__parent
                while node and node ~= root do
                    depth = depth + 1
                    level = math.max(level, tonumber(node.__frameLevel) or 0)
                    node = node.__parent
                end
                item.depth, item.level = depth, level
                if f.__type == "Texture" then
                    local v = f.__vertex
                    if v then item.vertex = { v[1] or 1, v[2] or 1, v[3] or 1, v[4] or 1 } end
                    local tc = f.__texCoord
                    if tc and #tc == 4 then item.texCoord = { tc[1], tc[2], tc[3], tc[4] } end
                    local g = f.__gradient
                    if g and type(g[2]) == "table" and type(g[3]) == "table" then
                        item.gradient = { g[2].r, g[2].g, g[2].b, g[3].r, g[3].g, g[3].b }
                    elseif f.__color then
                        item.color = { f.__color[1] or 0, f.__color[2] or 0, f.__color[3] or 0, f.__color[4] or 1 }
                    elseif type(f.__texture) == "string" then
                        item.texture = f.__texture
                    end
                else
                    item.text = S.plain(f.__text or "")
                    local tc = f.__textColor
                    item.textColor = tc and { tc[1] or 1, tc[2] or 1, tc[3] or 1 } or nil
                    item.font = f.__font or "GameFontNormal"
                    item.justify = f.__justifyH or "LEFT"
                    item.wrap = (f.__wrap ~= false) and (tonumber(f.__width) or 0) > 0
                    item.width = tonumber(f.__width) or 0
                    item.fixedH = tonumber(f.__height) or 0
                end
                if item.color or item.texture or item.gradient or (item.text and item.text ~= "") then
                    out[#out + 1] = item
                end
            end
        end
    end
    return out
end
'''

rt = lua51.LuaRuntime(unpack_returned_tuples=True)
build = rt.execute(LUA)
opts = rt.table_from({"real": real, "tab": tab, "W": W, "H": H, "pick": pick, "chip": chip,
                      "media": ready, "profile": profile, "recipe": recipe})
items = build(ROOT, opts, measure, line_height, measure_wrap)

img = Image.new("RGBA", (W * SCALE, H * SCALE), (10, 12, 18, 255))

records = [items[i] for i in range(1, len(items) + 1)]
# Порядок рисования: уровень рамки (кнопки поверх раздела), потом вложенность,
# потом слой внутри рамки, потом порядок создания.
records.sort(key=lambda it: (it["level"], it["depth"], it["layer"], it["index"]))

_tga = {}


def media(name):
    """Картинка из папки Media по пути, который аддон отдал клиенту."""
    base = name.replace("/", "\\").split("\\")[-1]
    if base not in _tga:
        path = os.path.join(ROOT, "Media", base + ".tga")
        _tga[base] = Image.open(path).convert("RGBA") if os.path.exists(path) else None
    return _tga[base]


def tint(pic, vertex):
    if vertex is None:
        return pic
    r, g, b, a = (max(0.0, min(1.0, float(vertex[k]))) for k in (1, 2, 3, 4))
    bands = pic.split()
    out_bands = [bands[0].point(lambda v, m=r: int(v * m)), bands[1].point(lambda v, m=g: int(v * m)),
                 bands[2].point(lambda v, m=b: int(v * m)), bands[3].point(lambda v, m=a: int(v * m))]
    return Image.merge("RGBA", out_bands)


def paste(pic, box, clip_box=None):
    global img
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    layer.paste(pic, (box[0], box[1]))
    if clip_box is not None:
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rectangle(clip_box, fill=255)
        layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", img.size, 0), mask))
    img = Image.alpha_composite(img, layer)


for it in records:
    l, t, r, b = (it["l"] * SCALE, it["t"] * SCALE, it["r"] * SCALE, it["b"] * SCALE)
    clip_box = None
    if it["clipT"] is not None:
        clip_box = [0, int(it["clipT"] * SCALE), img.size[0], int(it["clipB"] * SCALE)]
    if it["kind"] == "Texture":
        if r - l < 0.5 or b - t < 0.5:
            continue
        box = (int(round(l)), int(round(t)), int(round(r)), int(round(b)))
        w, h = max(1, box[2] - box[0]), max(1, box[3] - box[1])
        if it["gradient"] is not None:
            g = [float(it["gradient"][k]) for k in range(1, 7)]
            pic = Image.new("RGBA", (w, h))
            d = ImageDraw.Draw(pic)
            for y in range(h):
                k = y / max(1, h - 1)          # 0 сверху, 1 снизу
                col = tuple(int(255 * (g[3 + i] * (1 - k) + g[i] * k)) for i in range(3))
                d.line([(0, y), (w, y)], fill=col + (255,))
            paste(pic, box, clip_box)
        elif it["color"] is not None:
            c = it["color"]
            rgba = tuple(int(max(0, min(1, c[k])) * 255) for k in (1, 2, 3, 4))
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            top, bottom = box[1], box[3] - 1
            if clip_box is not None:
                top, bottom = max(top, clip_box[1]), min(bottom, clip_box[3])
            if bottom >= top:
                ImageDraw.Draw(layer).rectangle([box[0], top, max(box[0], box[2] - 1), bottom], fill=rgba)
                img = Image.alpha_composite(img, layer)
        elif it["texture"]:
            path = it["texture"]
            if "ForeverPilot" in path:
                pic = media(path)
                if pic is None:
                    continue
                tc = it["texCoord"]
                if tc is not None:
                    x0, x1, y0, y1 = (float(tc[k]) for k in (1, 2, 3, 4))
                    pw, ph = pic.size
                    crop = (int(round(x0 * pw)), int(round(y0 * ph)),
                            max(int(round(x0 * pw)) + 1, int(round(x1 * pw))),
                            max(int(round(y0 * ph)) + 1, int(round(y1 * ph))))
                    pic = pic.crop(crop)
                pic = tint(pic.resize((w, h), Image.LANCZOS), it["vertex"])
                paste(pic, box, clip_box)
            elif "Icons" in path:
                # условная иконка предмета: цвет по имени, чтобы разные отличались
                seed = sum(path.encode("utf-8"))
                col = (70 + seed % 90, 80 + (seed // 7) % 80, 110 + (seed // 3) % 90, 255)
                pic = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                ImageDraw.Draw(pic).rounded_rectangle([0, 0, w - 1, h - 1], radius=3 * SCALE, fill=col,
                                                      outline=(0, 0, 0, 120))
                paste(pic, box, clip_box)
    else:
        text = it["text"]
        fnt = font(it["font"])
        tc = it["textColor"]
        if tc is not None:
            color = tuple(int(max(0, min(1, tc[k])) * 255) for k in (1, 2, 3))
        else:
            color = tuple(int(v * 255) for v in DEFAULT_COLOR.get(it["font"], (1, 1, 1)))
        width = it["width"] * SCALE
        lines = wrap_lines(text, fnt, width) if (it["wrap"] and width > 0) else text.split("\n")
        line_h = line_height(it["font"]) * SCALE
        ascent, descent = fnt.getmetrics()
        glyph_h = ascent + descent
        y = t
        if len(lines) == 1:
            # одна строка стоит по середине своей высоты
            y = t + ((b - t) - glyph_h) / 2
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        limit = b + 2 if (it["fixedH"] and it["fixedH"] > 0 and len(lines) > 1) else None
        for line in lines:
            if limit is not None and y + glyph_h > limit:
                break
            tw = fnt.getlength(line)
            if it["justify"] == "RIGHT":
                x = r - tw
            elif it["justify"] == "CENTER":
                x = (l + r) / 2 - tw / 2
            else:
                x = l
            d.text((x, y), line, font=fnt, fill=color + (255,))
            y += line_h
        if clip_box is not None:
            mask = Image.new("L", img.size, 0)
            ImageDraw.Draw(mask).rectangle(clip_box, fill=255)
            layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", img.size, 0), mask))
        img = Image.alpha_composite(img, layer)

img.convert("RGB").save(out)
print("нарисовано:", out, f"{W}x{H}", "элементов", len(records), "свой шрифт" if ready else "шрифты игры")
