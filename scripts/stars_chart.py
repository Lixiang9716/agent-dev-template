#!/usr/bin/env python3
"""Generate stars.svg from stars.csv (columns: date,stars).

Kept on master and invoked by .github/workflows/star-history.yml, which checks
out the ``stats`` branch and runs this script after appending today's count.
"""

import csv

W, H = 720, 260
PAD_L, PAD_R, PAD_T, PAD_B = 56, 24, 20, 44


def main():
    rows = []
    with open("stars.csv", newline="") as fh:
        for row in csv.DictReader(fh):
            try:
                rows.append((row["date"], int(row["stars"])))
            except (KeyError, ValueError):
                continue
    if not rows:
        return

    dates = [d for d, _ in rows]
    counts = [c for _, c in rows]
    lo, hi = min(counts), max(counts)
    if lo == hi:
        hi = lo + 1

    def x(i):
        span = max(1, len(rows) - 1)
        return PAD_L + i * (W - PAD_L - PAD_R) / span

    def y(v):
        return PAD_T + (hi - v) * (H - PAD_T - PAD_B) / (hi - lo)

    points = " ".join(f"{x(i):.1f},{y(c):.1f}" for i, c in enumerate(counts))
    dots = "".join(
        f'<circle cx="{x(i):.1f}" cy="{y(c):.1f}" r="3" fill="#0969da"/>'
        for i, c in enumerate(counts)
    )

    span = hi - lo
    step = max(1, (span + 7) // 8)
    ticks = []
    v = lo
    while v <= hi:
        ticks.append(
            f'<text x="{PAD_L - 8}" y="{y(v) + 4:.1f}" text-anchor="end" '
            f'font-size="12" fill="#57606a">{v}</text>'
        )
        v += step
    if (hi - lo) % step:
        ticks.append(
            f'<text x="{PAD_L - 8}" y="{y(hi) + 4:.1f}" text-anchor="end" '
            f'font-size="12" fill="#57606a">{hi}</text>'
        )

    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}" role="img" aria-label="Star history">'
        f'<rect width="100%" height="100%" fill="#ffffff"/>'
        f'{"".join(ticks)}'
        f'<polyline fill="none" stroke="#0969da" stroke-width="2" points="{points}"/>'
        f'{dots}'
        f'<text x="{PAD_L}" y="{H - 10}" font-size="12" fill="#57606a">{dates[0]}</text>'
        f'<text x="{W - PAD_R}" y="{H - 10}" text-anchor="end" font-size="12" '
        f'fill="#57606a">{dates[-1]}</text>'
        f"</svg>"
    )
    with open("stars.svg", "w") as fh:
        fh.write(svg)


if __name__ == "__main__":
    main()
