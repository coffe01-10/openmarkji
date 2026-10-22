import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "charts"
OUT.mkdir(parents=True, exist_ok=True)

ORANGE = "#E8603C"
TEAL = "#2AA198"
AMBER = "#D97706"
GREEN = "#4E9A8A"
BG = "#FFFFFF"
GRID = "#E8EAED"
TXT = "#202124"
SUB = "#5F6368"


def _line_path(pts):
    return " ".join(f"{'M' if i == 0 else 'L'}{x:.1f},{y:.1f}" for i, (x, y) in enumerate(pts))


def _ebbinghaus(d):
    return 100 * math.exp(-d / 2.2)


def _actual(d):
    return 100 * math.exp(-d / 3.4) + (8 if d > 15 else 0) * math.exp(-(d - 15) / 6)


def _fmt(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def svg_header(w, h):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" font-family="Segoe UI,Microsoft YaHei,Arial,sans-serif">'
        f'<rect width="{w}" height="{h}" fill="{BG}" rx="10"/>'
    )


def axes(w, h, ml, mr, mt, mb, ymin, ymax, ylabel, xlabel, xticks):
    parts = []
    pw, ph = w - ml - mr, h - mt - mb
    for i in range(5):
        v = ymin + (ymax - ymin) * i / 4
        y = mt + ph - (v - ymin) / (ymax - ymin) * ph
        parts.append(f'<line x1="{ml}" y1="{y:.1f}" x2="{w - mr}" y2="{y:.1f}" stroke="{GRID}" stroke-width="1"/>')
        parts.append(f'<text x="{ml - 10}" y="{y + 4:.1f}" text-anchor="end" font-size="13" fill="{SUB}">{_fmt(v)}</text>')
    parts.append(
        f'<text x="{ml - 44}" y="{mt + ph / 2}" text-anchor="middle" font-size="14" fill="{SUB}" '
        f'transform="rotate(-90 {ml - 44} {mt + ph / 2})">{ylabel}</text>'
    )
    for label, frac in xticks:
        x = ml + frac * pw
        parts.append(f'<text x="{x:.1f}" y="{h - mb + 20}" text-anchor="middle" font-size="13" fill="{SUB}">{label}</text>')
    parts.append(f'<text x="{ml + pw / 2}" y="{h - 8}" text-anchor="middle" font-size="14" fill="{SUB}">{xlabel}</text>')
    parts.append(f'<rect x="{ml}" y="{mt}" width="{pw}" height="{ph}" fill="none" stroke="{GRID}" stroke-width="1"/>')
    return "".join(parts)


def map_pts(vals, w, h, ml, mr, mt, mb, ymin, ymax):
    pw, ph = w - ml - mr, h - mt - mb
    n = len(vals) - 1
    return [
        (ml + i / n * pw, mt + ph - (v - ymin) / (ymax - ymin) * ph)
        for i, v in enumerate(vals)
    ]


def legend(items, x, y):
    parts = [f'<g font-size="14" fill="{TXT}">']
    for i, (label, color) in enumerate(items):
        yy = y + i * 24
        parts.append(
            f'<line x1="{x}" y1="{yy - 4}" x2="{x + 26}" y2="{yy - 4}" stroke="{color}" stroke-width="3"/>'
            f'<text x="{x + 34}" y="{yy}" fill="{TXT}">{label}</text>'
        )
    parts.append("</g>")
    return "".join(parts)


def chart_curve(lang):
    zh = lang == "zh"
    w, h = 920, 420
    ml, mr, mt, mb = 70, 30, 56, 56
    days = list(range(0, 31))
    eb = [_ebbinghaus(d) for d in days]
    me = [_actual(d) for d in days]
    ymin, ymax = 0, 100
    xticks = [
        ("今天" if zh else "Today", 0),
        ("5天后" if zh else "Day 5", 5 / 30),
        ("10天后" if zh else "Day 10", 10 / 30),
        ("15天后" if zh else "Day 15", 15 / 30),
        ("20天后" if zh else "Day 20", 20 / 30),
        ("30天后" if zh else "Day 30", 1),
    ]
    s = svg_header(w, h)
    title = "遗忘曲线 · 你的记忆 vs 艾宾浩斯" if zh else "Forgetting Curve · Yours vs Ebbinghaus"
    s += f'<text x="{w / 2}" y="34" text-anchor="middle" font-size="20" font-weight="600" fill="{TXT}">{title}</text>'
    s += axes(w, h, ml, mr, mt, mb, ymin, ymax,
              "记忆保持率 (%)" if zh else "Retention (%)",
              "天数" if zh else "Days", xticks)
    eb_pts = map_pts(eb, w, h, ml, mr, mt, mb, ymin, ymax)
    me_pts = map_pts(me, w, h, ml, mr, mt, mb, ymin, ymax)
    s += f'<path d="{_line_path(eb_pts)}" fill="none" stroke="{TEAL}" stroke-width="3"/>'
    s += f'<path d="{_line_path(me_pts)}" fill="none" stroke="{ORANGE}" stroke-width="3"/>'
    for p in me_pts[::5]:
        s += f'<circle cx="{p[0]:.1f}" cy="{p[1]:.1f}" r="3.5" fill="{ORANGE}"/>'
    items = [
        ("你的学习遗忘曲线" if zh else "Your Forgetting Curve", ORANGE),
        ("艾宾浩斯遗忘曲线" if zh else "Ebbinghaus Curve", TEAL),
    ]
    s += legend(items, w - 280, mt + 22)
    s += "</svg>"
    (OUT / ("retention-curve-zh.svg" if zh else "retention-curve-en.svg")).write_text(s, encoding="utf-8")


def chart_forecast(lang):
    zh = lang == "zh"
    w, h = 920, 400
    ml, mr, mt, mb = 70, 30, 56, 60
    days = list(range(0, 16))
    new_ = [2, 3, 2, 1, 2, 3, 2, 1, 2, 1, 2, 3, 2, 1, 2, 1]
    rev = [5, 4, 6, 3, 5, 4, 6, 3, 5, 4, 6, 3, 5, 4, 6, 3]
    ymax = 8
    s = svg_header(w, h)
    title = "学习情况 · 未来15天预测" if zh else "Learning Load · Next 15 Days"
    s += f'<text x="{w / 2}" y="34" text-anchor="middle" font-size="20" font-weight="600" fill="{TXT}">{title}</text>'
    pw, ph = w - ml - mr, h - mt - mb
    for i in range(5):
        v = ymax * i / 4
        y = mt + ph - v / ymax * ph
        s += f'<line x1="{ml}" y1="{y:.1f}" x2="{w - mr}" y2="{y:.1f}" stroke="{GRID}"/>'
        s += f'<text x="{ml - 10}" y="{y + 4:.1f}" text-anchor="end" font-size="13" fill="{SUB}">{_fmt(v)}</text>'
    s += f'<text x="{ml - 44}" y="{mt + ph / 2}" text-anchor="middle" font-size="14" fill="{SUB}" transform="rotate(-90 {ml - 44} {mt + ph / 2})">{"卡片数" if zh else "Cards"}</text>'
    group_w = pw / len(days)
    bar_w = group_w * 0.34
    for i, d in enumerate(days):
        gx = ml + i * group_w + group_w / 2
        nh = new_[i] / ymax * ph
        rh = rev[i] / ymax * ph
        s += f'<rect x="{gx - bar_w - 1:.1f}" y="{mt + ph - nh:.1f}" width="{bar_w:.1f}" height="{nh:.1f}" fill="{GREEN}" rx="2"/>'
        s += f'<rect x="{gx + 1:.1f}" y="{mt + ph - rh:.1f}" width="{bar_w:.1f}" height="{rh:.1f}" fill="{ORANGE}" rx="2"/>'
        s += f'<text x="{gx - bar_w / 2 - 1:.1f}" y="{mt + ph - nh - 4:.1f}" text-anchor="middle" font-size="10" fill="{SUB}">{new_[i]}</text>'
        s += f'<text x="{gx + bar_w / 2 + 1:.1f}" y="{mt + ph - rh - 4:.1f}" text-anchor="middle" font-size="10" fill="{SUB}">{rev[i]}</text>'
        lbl = ("今" if zh else "D0") if d == 0 else (("明" if zh else "D1") if d == 1 else (("后" if zh else "D2") if d == 2 else str(d)))
        s += f'<text x="{gx:.1f}" y="{h - mb + 20}" text-anchor="middle" font-size="12" fill="{SUB}">{lbl}</text>'
    s += f'<text x="{ml + pw / 2}" y="{h - 8}" text-anchor="middle" font-size="14" fill="{SUB}">{"天数" if zh else "Days"}</text>'
    items = [
        ("新学" if zh else "New", GREEN),
        ("复习" if zh else "Review", ORANGE),
    ]
    s += legend(items, w - 160, mt + 16)
    s += "</svg>"
    (OUT / ("forecast-zh.svg" if zh else "forecast-en.svg")).write_text(s, encoding="utf-8")


def chart_cognition(lang):
    zh = lang == "zh"
    w, h = 920, 340
    ml, mr, mt, mb = 110, 130, 56, 48
    rows = [
        ("熟知" if zh else "Familiar", 15, TEAL),
        ("忘记" if zh else "Forgot", 15, ORANGE),
        ("模糊" if zh else "Vague", 25, AMBER),
        ("认识" if zh else "Know", 45, GREEN),
    ]
    xmax = 50
    s = svg_header(w, h)
    title = "认知情况 · 过去30天评级分布" if zh else "Cognition · Ratings (Last 30 Days)"
    s += f'<text x="{w / 2}" y="34" text-anchor="middle" font-size="20" font-weight="600" fill="{TXT}">{title}</text>'
    pw, ph = w - ml - mr, h - mt - mb
    for i in range(6):
        v = xmax * i / 5
        x = ml + v / xmax * pw
        s += f'<line x1="{x:.1f}" y1="{mt}" x2="{x:.1f}" y2="{mt + ph}" stroke="{GRID}"/>'
        s += f'<text x="{x:.1f}" y="{h - mb + 18}" text-anchor="middle" font-size="13" fill="{SUB}">{_fmt(v)}</text>'
    s += f'<text x="{ml + pw / 2}" y="{h - 6}" text-anchor="middle" font-size="14" fill="{SUB}">{"卡片数" if zh else "Cards"}</text>'
    row_h = ph / len(rows)
    for i, (name, val, color) in enumerate(rows):
        cy = mt + i * row_h + row_h / 2
        bw = val / xmax * pw
        s += f'<text x="{ml - 12}" y="{cy + 5:.1f}" text-anchor="end" font-size="15" font-weight="600" fill="{TXT}">{name}</text>'
        s += f'<rect x="{ml}" y="{cy - 17:.1f}" width="{bw:.1f}" height="34" fill="{color}" rx="3"/>'
        s += f'<text x="{ml + bw + 8:.1f}" y="{cy + 5:.1f}" font-size="14" fill="{TXT}">{val} ({val}%)</text>'
    s += "</svg>"
    (OUT / ("cognition-zh.svg" if zh else "cognition-en.svg")).write_text(s, encoding="utf-8")


for lang in ("zh", "en"):
    chart_curve(lang)
    chart_forecast(lang)
    chart_cognition(lang)

print("wrote", len(list(OUT.glob("*.svg"))), "svgs to", OUT)
