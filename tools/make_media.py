#!/usr/bin/env python3
# ForeverPilot / tools/make_media.py
#
# Рисует картинки аддона: значки, скругления для кнопок, звёзды для шапки.
# Всё здесь нарисовано для ForeverPilot с нуля, простыми фигурами; чужих
# картинок в аддоне нет. Значки белые на прозрачном - цвет им задаёт сам аддон.
#
# Запуск:  python3 tools/make_media.py   (кладёт файлы в ForeverPilot/Media)
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ForeverPilot", "Media")
S = 64          # сторона значка в файле (степень двойки)
K = 8           # во сколько раз крупнее рисуем, чтобы края были гладкими
N = S * K
WHITE = (255, 255, 255, 255)
LW = 4.6        # толщина линии значка в единицах 64-клеточной сетки


def canvas():
    img = Image.new("RGBA", (N, N), (255, 255, 255, 0))
    return img, ImageDraw.Draw(img)


def P(x, y):
    return (x * K, y * K)


def dot(d, x, y, r, fill=WHITE):
    d.ellipse([(x - r) * K, (y - r) * K, (x + r) * K, (y + r) * K], fill=fill)


def line(d, pts, w=LW, close=False):
    """Ломаная со скруглёнными концами и стыками."""
    if close:
        pts = list(pts) + [pts[0]]
    for a, b in zip(pts, pts[1:]):
        d.line([P(*a), P(*b)], fill=WHITE, width=int(round(w * K)))
    for p in pts:
        dot(d, p[0], p[1], w / 2)


def curve(fn, t0, t1, steps=48):
    return [fn(t0 + (t1 - t0) * i / steps) for i in range(steps + 1)]


def arc(d, cx, cy, r, a0, a1, w=LW):
    """Дуга по часовой стрелке от a0 до a1 (градусы, 0 - вправо, 90 - вниз)."""
    pts = curve(lambda a: (cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))), a0, a1, 64)
    line(d, pts, w)


def ring(d, cx, cy, r, w=LW):
    arc(d, cx, cy, r, 0, 360, w)


def poly(d, pts, fill=WHITE):
    d.polygon([P(*p) for p in pts], fill=fill)


def save(img, name, size=S):
    out = img.resize((size, size) if isinstance(size, int) else size, Image.LANCZOS)
    out.save(os.path.join(OUT, name + ".tga"), format="TGA")
    return out


ICONS = {}


def icon(name):
    def wrap(fn):
        ICONS[name] = fn
        return fn
    return wrap


# ---- разделы -------------------------------------------------------------
@icon("bulb")
def _(d):       # Советы: лампочка
    arc(d, 32, 26, 15, 125, 415)
    line(d, [(23.4, 38.3), (25.5, 43)])
    line(d, [(40.6, 38.3), (38.5, 43)])
    line(d, [(25.5, 44), (38.5, 44)])
    line(d, [(27, 50), (37, 50)])
    line(d, [(30, 55.5), (34, 55.5)], 4)


@icon("person")
def _(d):       # Персонаж
    ring(d, 32, 21, 9)
    arc(d, 32, 56, 19, 195, 345)


@icon("hammer")
def _(d):       # Крафт: молот
    line(d, [(14, 52), (36, 30)], 5.4)
    line(d, [(30, 15), (49, 34)], 11)


@icon("sliders")
def _(d):       # Настройки: ползунки
    for y, x in ((18, 24), (32, 41), (46, 28)):
        line(d, [(11, y), (53, y)], 4)
        dot(d, x, y, 7.2, (255, 255, 255, 0))
        ring(d, x, y, 5, 4)


# ---- профиль ---------------------------------------------------------------
@icon("bolt")
def _(d):       # Сила
    poly(d, [(37, 6), (15, 36), (29, 36), (25, 58), (49, 27), (34, 27)])
    line(d, [(37, 6), (15, 36), (29, 36), (25, 58), (49, 27), (34, 27)], 2.2, close=True)


@icon("levelup")
def _(d):       # Прокачка
    line(d, [(18, 31), (32, 17), (46, 31)], 5)
    line(d, [(18, 47), (32, 33), (46, 47)], 5)


@icon("wallet")
def _(d):       # Экономия: кошелёк
    d.rounded_rectangle([P(9, 17), P(55, 49)], radius=7 * K, outline=WHITE, width=int(LW * K))
    line(d, [(38, 33), (55, 33)], 4.2)
    dot(d, 41.5, 33, 3.6)
    line(d, [(15, 17), (40, 11.5), (45, 17)], 4.2)


@icon("trend")
def _(d):       # Заработок
    line(d, [(9, 47), (24, 32), (33, 41), (53, 19)], 5)
    line(d, [(41, 18), (53.5, 18.5), (54, 31)], 5)


# ---- фильтр ----------------------------------------------------------------
@icon("list")
def _(d):       # Всё
    for y in (19, 32, 45):
        dot(d, 14, y, 3.4)
        line(d, [(24, y), (52, y)], 4.6)


@icon("ready")
def _(d):       # Можно сейчас
    ring(d, 32, 32, 20)
    line(d, [(22.5, 33), (29.5, 40), (42, 25.5)], 5)


@icon("shield")
def _(d):       # Экипировка
    pts = [(32, 8), (51, 15), (51, 30)]
    pts += curve(lambda t: (32 + 19 * math.cos(t), 30 + 26 * math.sin(t)), 0, math.pi / 2, 16)[1:]
    pts += curve(lambda t: (32 + 19 * math.cos(t), 30 + 26 * math.sin(t)), math.pi / 2, math.pi, 16)[1:]
    pts += [(13, 15)]
    line(d, pts, LW, close=True)


@icon("sparkle")
def _(d):       # Чары
    def star(cx, cy, r, k=0.26):
        pts = []
        for i in range(8):
            a = math.pi / 4 * i - math.pi / 2
            rr = r if i % 2 == 0 else r * k
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        poly(d, pts)
    star(26, 36, 20)
    star(47, 16, 10)


@icon("coin")
def _(d):       # Золото
    ring(d, 32, 32, 20)
    line(d, [(32, 21.5), (32, 42.5)], 4)
    arc(d, 32, 27.6, 5.6, 150, 360, 4)
    arc(d, 32, 36.4, 5.6, -30, 180, 4)


# ---- кнопки ----------------------------------------------------------------
@icon("close")
def _(d):
    line(d, [(19, 19), (45, 45)], 5)
    line(d, [(45, 19), (19, 45)], 5)


@icon("reload")
def _(d):
    arc(d, 32, 32, 19, -60, 215, 5)
    line(d, [(31, 8.5), (42.5, 14.5), (37, 26)], 5)


@icon("grip")
def _(d):
    for k in (0, 14, 28):
        line(d, [(22 + k, 54), (54, 22 + k)], 4.4)


@icon("chevron")
def _(d):       # вниз
    line(d, [(19, 26), (32, 39), (45, 26)], 5)


@icon("search")
def _(d):       # Искать на аукционе
    ring(d, 27, 27, 15, 5)
    line(d, [(38.5, 38.5), (53, 53)], 5.6)


@icon("book")
def _(d):       # Показать в профессии
    line(d, [(32, 17), (32, 51)], 4.2)
    line(d, [(32, 17), (22, 12.5), (9, 12.5), (9, 46.5), (22, 46.5), (32, 51)], 4.4)
    line(d, [(32, 17), (42, 12.5), (55, 12.5), (55, 46.5), (42, 46.5), (32, 51)], 4.4)


@icon("plus")
def _(d):       # В список покупок
    line(d, [(32, 14), (32, 50)], 5.4)
    line(d, [(14, 32), (50, 32)], 5.4)


@icon("eye")
def _(d):       # Показать предмет
    top = curve(lambda t: (8 + 48 * t, 32 - 17 * math.sin(math.pi * t)), 0, 1, 40)
    bottom = curve(lambda t: (56 - 48 * t, 32 + 17 * math.sin(math.pi * t)), 0, 1, 40)
    line(d, top + bottom[1:], 4.6)
    ring(d, 32, 32, 7.5, 4.6)


@icon("route")
def _(d):       # Показать путь: стрелка навигации
    line(d, [(52, 12), (11, 27), (29, 35), (37, 53)], 4.8, close=True)


@icon("undo")
def _(d):       # Вернуть
    arc(d, 34, 36, 17, -160, 110, 5)
    line(d, [(8, 21), (17.5, 31), (28, 22)], 5)


@icon("check")
def _(d):       # Понятно
    line(d, [(14, 33), (26, 45), (50, 19)], 5.6)


@icon("pin")
def _(d):       # Где
    arc(d, 32, 25, 14, 160, 380)
    line(d, [(18.8, 29.8), (32, 54), (45.2, 29.8)], LW)
    dot(d, 32, 25, 5)


def shapes():
    # Скруглённая плашка под кнопки: рисуется тремя кусками (левый край,
    # растянутая середина, правый край), поэтому важны только края.
    for name, radius, outline in (("round", 14, None), ("round-line", 14, 3.2), ("pill", 32, None), ("pill-line", 32, 3.0)):
        img, d = canvas()
        box = [P(0.5, 0.5), P(63.5, 63.5)]
        if outline:
            d.rounded_rectangle(box, radius=radius * K, outline=WHITE, width=int(outline * K))
        else:
            d.rounded_rectangle(box, radius=radius * K, fill=WHITE)
        save(img, name)

    # Мягкое свечение: под иконкой совета и за значком аддона.
    g = Image.new("L", (256, 256), 0)
    gp = g.load()
    for y in range(256):
        for x in range(256):
            r = math.hypot(x - 127.5, y - 127.5) / 127.5
            gp[x, y] = int(255 * max(0.0, 1 - r) ** 2.2)
    glow = Image.merge("RGBA", (Image.new("L", (256, 256), 255),) * 3 + (g,))
    glow.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, "glow.tga"), format="TGA")

    # Звёзды для шапки: прозрачный фон, редкие точки разной яркости. Картинка
    # накладывается на цвет шапки, поэтому фона у неё нет.
    rnd = random.Random(20261121)
    Wd, Hd, k = 512, 128, 4
    sky = Image.new("RGBA", (Wd * k, Hd * k), (255, 255, 255, 0))
    sd = ImageDraw.Draw(sky)
    for _ in range(150):
        x, y = rnd.uniform(0, Wd), rnd.uniform(0, Hd)
        # к низу шапки звёзд меньше и они тусклее
        fade = 1 - (y / Hd) ** 1.6
        if rnd.random() > fade + 0.15:
            continue
        r = rnd.choice((0.55, 0.55, 0.7, 0.7, 0.9, 1.25))
        a = int(255 * rnd.uniform(0.22, 0.85) * (0.35 + 0.65 * fade))
        sd.ellipse([(x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k], fill=(255, 255, 255, a))
    for _ in range(5):       # несколько искр покрупнее
        x, y = rnd.uniform(20, Wd - 20), rnd.uniform(8, Hd * 0.6)
        r = rnd.uniform(2.6, 4.2)
        a = int(255 * rnd.uniform(0.5, 0.8))
        pts = []
        for i in range(8):
            ang = math.pi / 4 * i - math.pi / 2
            rr = r if i % 2 == 0 else r * 0.22
            pts.append(((x + rr * math.cos(ang)) * k, (y + rr * math.sin(ang)) * k))
        sd.polygon(pts, fill=(255, 255, 255, a))
    sky.resize((Wd, Hd), Image.LANCZOS).save(os.path.join(OUT, "stars.tga"), format="TGA")


def main():
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for name, fn in ICONS.items():
        img, d = canvas()
        fn(d)
        made[name] = save(img, "icon-" + name)
    shapes()
    # лист предпросмотра: как значки выглядят на тёмном и мелко
    cols = 9
    rows = (len(made) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * 84 + 12, rows * 104 + 12), (20, 25, 40, 255))
    sd = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(made.items()):
        x, y = 12 + (i % cols) * 84, 12 + (i // cols) * 104
        tint = Image.new("RGBA", im.size, (236, 240, 248, 255))
        sheet.paste(tint, (x, y), im)
        small = im.resize((22, 22), Image.LANCZOS)
        gold = Image.new("RGBA", small.size, (227, 184, 97, 255))
        sheet.paste(gold, (x + 2, y + 68), small)
        white = Image.new("RGBA", small.size, (236, 240, 248, 255))
        sheet.paste(white, (x + 30, y + 68), small)
        sd.text((x, y + 92), name, fill=(150, 160, 180, 255))
    sheet.save("/tmp/icons_sheet.png")
    print("значков:", len(made), "файлов в Media:", len(os.listdir(OUT)))


if __name__ == "__main__":
    main()
