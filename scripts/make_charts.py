"""Generate the Q1 and Q2 answer charts as PNGs from the strategy mart.

A lightweight stand-in for a BI tool: reads marts.fct_strategy_by_hour and writes two
bar charts to docs/screenshots/. Read-only, safe to run any time after `make build`.
Connection defaults match docker-compose.yml / profiles.yml and are overridable via
the same POSTGRES_* env vars.
"""

from __future__ import annotations

import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display needed (works headless / WSL)

import matplotlib.pyplot as plt  # noqa: E402
import psycopg2  # noqa: E402


def fetch_rows() -> list[tuple[int, float, float]]:
    conn = psycopg2.connect(
        host=os.environ.get("POSTGRES_HOST", "localhost"),
        port=os.environ.get("POSTGRES_PORT", "5432"),
        dbname=os.environ.get("POSTGRES_DB", "bitcoin"),
        user=os.environ.get("POSTGRES_USER", "postgres"),
        password=os.environ.get("POSTGRES_PASSWORD", "postgres"),
    )
    try:
        with conn.cursor() as cur:
            cur.execute(
                "select hour_of_day, total_compounded_return, maximum_drawdown "
                "from marts.fct_strategy_by_hour order by hour_of_day"
            )
            return [(int(h), float(r), float(d)) for h, r, d in cur.fetchall()]
    finally:
        conn.close()


def bar_chart(
    hours: list[int],
    values: list[float],
    title: str,
    ylabel: str,
    out_path: Path,
    highlight_idx: int,
) -> None:
    fig, ax = plt.subplots(figsize=(10, 4.5))
    colors = ["#bbbbbb"] * len(hours)
    colors[highlight_idx] = "#1f77b4"
    ax.bar(hours, values, color=colors)
    ax.set_xticks(hours)
    ax.set_xlabel("Hour of day (UTC)")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.axhline(0, color="#333333", linewidth=0.8)
    ax.yaxis.set_major_formatter(lambda v, _pos: f"{v:.0%}")
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)


def main() -> None:
    rows = fetch_rows()
    if not rows:
        raise SystemExit("marts.fct_strategy_by_hour is empty; run `make build` first.")

    hours = [r[0] for r in rows]
    returns = [r[1] for r in rows]
    drawdowns = [r[2] for r in rows]

    out_dir = Path(__file__).resolve().parent.parent / "docs" / "screenshots"
    out_dir.mkdir(parents=True, exist_ok=True)

    q1_idx = max(range(len(returns)), key=lambda i: returns[i])
    q2_idx = max(range(len(drawdowns)), key=lambda i: drawdowns[i])  # closest to zero

    q1_path = out_dir / "q1_compounded_return_by_hour.png"
    q2_path = out_dir / "q2_max_drawdown_by_hour.png"

    bar_chart(
        hours,
        returns,
        f"Q1: compounded return by hour (best: hour {hours[q1_idx]})",
        "Total compounded return",
        q1_path,
        q1_idx,
    )
    bar_chart(
        hours,
        drawdowns,
        f"Q2: max drawdown by hour (shallowest: hour {hours[q2_idx]})",
        "Maximum drawdown",
        q2_path,
        q2_idx,
    )

    print("charts written (open in a browser or see them embedded in the README):")
    print(f"  Q1  {q1_path.as_uri()}")
    print(f"  Q2  {q2_path.as_uri()}")


if __name__ == "__main__":
    main()
