#!/usr/bin/env python3
# ForeverPilot / Tests/preview.py
#
# КАРТИНКА ОКНА БЕЗ ИГРЫ.
#
# Проверки разметки отвечают «ничто ни на что не налезает», но не отвечают «как
# это выглядит» - а игрок жаловался именно на вид («непонятно, куда нажимать»).
# Запустить игру отсюда нельзя, поэтому окно рисуется по тем же рамкам, которые
# аддон создаёт в заглушке клиента (Tests/uistub.lua): где что привязано, какого
# цвета, какой текст. Шрифты и иконки здесь условные - это чертёж, а не снимок
# экрана, - но колонки, отступы, цвета и то, что куда влезло, в нём настоящие.
#
# Запуск (из папки аддона):
#   python3 Tests/preview.py out.png                 # выдуманный мир из тестов
#   python3 Tests/preview.py out.png --real          # сохранения игрока (FP_WTF)
#   python3 Tests/preview.py out.png --tab CHAR --size 860x480 --pick 6
#
# Ничего игрового здесь нет: это только второй способ посмотреть на разметку.

import os
import sys

import lupa.lua51 as lua51
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

args = sys.argv[1:]
out = args[0] if args and not args[0].startswith("--") else "preview.png"
real = "--real" in args
tab = args[args.index("--tab") + 1] if "--tab" in args else "NOW"
size = args[args.index("--size") + 1] if "--size" in args else "980x600"
pick = int(args[args.index("--pick") + 1]) if "--pick" in args else 0
chip = args[args.index("--chip") + 1] if "--chip" in args else None
ready = "--media" in args
W, H = (int(v) for v in size.split("x"))

LUA = r'''
return function(ROOT, real, tab, W, Hh, pick, chip, mediaReady)
    local H = assert(loadfile(ROOT .. "/Tests/harness.lua"))()
    H.ROOT = ROOT
    local S = assert(loadfile(ROOT .. "/Tests/uistub.lua"))(H)
    local env
    if real then
        local captured
        local proxyH = setmetatable({ load = function(opts)
            local e = H.load(opts); captured = captured or e; return e end }, { __index = H })
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
        H.build(env)
    else
        env = S.load(H)
        S.populate(env, H)
    end
    local ns = env.ns
    if mediaReady then ns.Api.mediaReady = true end
    ns.Config:SaveFrame("CENTER", "CENTER", 0, 0, W, Hh)
    ns.MainFrame:Build()
    ns.MainFrame:ApplyPosition()
    if chip then ns.Config:SetChip(chip) end
    ns.MainFrame:Select(tab)
    S.layout(env, W, Hh)
    ns.MainFrame:RenderActive()
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
            -- Содержимое списка: стоит в левом верхнем углу окна прокрутки.
            local o = rect(el.__parent, depth)
            local w, h = S.sizeOf(el)
            if o then r = { l = o.l, t = o.t, r = o.l + w, b = o.t + h } end
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
            and f.__shown ~= false and f.__parent and visible(f.__parent) then
            local r = rect(f)
            local c = clip(f)
            if r and c and (r.t < c.t - 0.5 or r.b > c.b + 0.5) then r = nil end
            if r then
                local item = { index = index, kind = f.__type, l = r.l, t = r.t, r = r.r, b = r.b,
                               layer = LAYER[f.__layer or ""] or 3 }
                -- Глубина владельца: дочерняя рамка рисуется поверх родительской.
                local depth, level, node = 0, 0, f.__parent
                while node and node ~= root do
                    depth = depth + 1
                    level = math.max(level, tonumber(node.__frameLevel) or 0)
                    node = node.__parent
                end
                item.depth, item.level = depth, level
                if f.__type == "Texture" then
                    if f.__color then
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
                end
                if item.color or item.texture or (item.text and item.text ~= "") then
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
items = build(ROOT, real, tab, W, H, pick, chip, ready)

SCALE = 2
img = Image.new("RGBA", (W * SCALE, H * SCALE), (10, 12, 18, 255))
FONT_DIR = "/usr/share/fonts/truetype/dejavu/"
_fonts = {}


def font(name, bold=False):
    px = {"GameFontNormalLarge": 15, "GameFontNormal": 11.5, "GameFontHighlightSmall": 9.6,
          "GameFontDisableSmall": 9.6}.get(name, 10)
    key = (px, bold)
    if key not in _fonts:
        path = FONT_DIR + ("DejaVuSansCondensed-Bold.ttf" if bold else "DejaVuSansCondensed.ttf")
        _fonts[key] = ImageFont.truetype(path, int(px * SCALE))
    return _fonts[key]


DEFAULT_COLOR = {"GameFontNormalLarge": (1, 0.82, 0), "GameFontNormal": (1, 0.82, 0),
                 "GameFontHighlightSmall": (1, 1, 1), "GameFontDisableSmall": (0.5, 0.5, 0.5)}

records = []
for i in range(1, len(items) + 1):
    it = items[i]
    records.append(it)
# Порядок рисования: уровень рамки (кнопки поверх раздела), потом вложенность,
# потом слой внутри рамки, потом порядок создания.
records.sort(key=lambda it: (it["level"], it["depth"], it["layer"], it["index"]))

ICON = None
icon_path = os.path.join(ROOT, "Media", "Icon.tga")
if os.path.exists(icon_path):
    ICON = Image.open(icon_path).convert("RGBA")


def wrap(text, fnt, width):
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


for it in records:
    l, t, r, b = (it["l"] * SCALE, it["t"] * SCALE, it["r"] * SCALE, it["b"] * SCALE)
    if it["kind"] == "Texture":
        if r - l < 0.5 or b - t < 0.5:
            continue
        if it["color"] is not None:
            c = it["color"]
            rgba = tuple(int(max(0, min(1, c[k])) * 255) for k in (1, 2, 3, 4))
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            ImageDraw.Draw(layer).rectangle([l, t, r - 1, b - 1], fill=rgba)
            img = Image.alpha_composite(img, layer)
        elif it["texture"]:
            path = it["texture"]
            box = (int(l), int(t), int(r), int(b))
            w, h = box[2] - box[0], box[3] - box[1]
            if w < 2 or h < 2:
                continue
            if "ForeverPilot" in path and ICON is not None:
                pic = ICON.resize((w, h), Image.LANCZOS)
                img.paste(pic, box[:2], pic)
            elif "Icons" in path:
                # условная иконка: цвет по имени, чтобы разные отличались
                seed = sum(path.encode("utf-8"))
                col = (70 + seed % 90, 80 + (seed // 7) % 80, 110 + (seed // 3) % 90, 255)
                layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
                d = ImageDraw.Draw(layer)
                d.rounded_rectangle([box[0], box[1], box[2] - 1, box[3] - 1], radius=3 * SCALE, fill=col,
                                    outline=(0, 0, 0, 120))
                img = Image.alpha_composite(img, layer)
    else:
        text = it["text"]
        fnt = font(it["font"])
        tc = it["textColor"]
        if tc is not None:
            color = tuple(int(max(0, min(1, tc[k])) * 255) for k in (1, 2, 3))
        else:
            color = tuple(int(v * 255) for v in DEFAULT_COLOR.get(it["font"], (1, 1, 1)))
        d = ImageDraw.Draw(img)
        width = it["width"] * SCALE
        lines = wrap(text, fnt, width) if (it["wrap"] and width > 0) else text.split("\n")
        line_h = int(fnt.size * 1.22)
        y = t
        if not it["wrap"]:
            y = t + ((b - t) - line_h) / 2
        for line in lines:
            tw = fnt.getlength(line)
            if it["justify"] == "RIGHT":
                x = r - tw
            elif it["justify"] == "CENTER":
                x = (l + r) / 2 - tw / 2
            else:
                x = l
            d.text((x, y), line, font=fnt, fill=color + (255,))
            y += line_h

img.convert("RGB").save(out)
print("нарисовано:", out, f"{W}x{H}", "элементов", len(records))
