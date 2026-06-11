# Bitcoin Backtesting Engine

A reproducible backtesting engine for a single intraday Bitcoin trading strategy,
built as a dbt project on Postgres and runnable end to end with one bash script.

The strategy under test: buy at the first second of a chosen hour, sell at the
last second of that same hour, every day, reinvesting all proceeds so returns
compound. It answers two questions: which hour of the day had the biggest
compounded returns, and which had the lowest maximum losses.

## Prerequisites

Two things, both free and quick to install:

- **Docker**, to run the database. On macOS or Windows the simplest option is
  [Docker Desktop](https://docs.docker.com/get-docker/) (one installer); on
  Linux, [Docker Engine](https://docs.docker.com/engine/install/). The project
  drives it with `docker compose`, which ships with both.
- **uv**, for Python and dbt:
  [install guide](https://docs.astral.sh/uv/getting-started/installation/). It
  reads the committed lockfile, so dbt and its dependencies are pulled in
  automatically at pinned versions; no separate dbt or Python setup needed.

## Quick start

1. Put the dataset CSV in the project root (it is never committed). Either use
   the Kaggle CLI:

   ```bash
   kaggle datasets download -d tzelal/binance-bitcoin-dataset-1s-timeframe-p2 --unzip -p .
   ```

   or download and unzip it manually from
   <https://www.kaggle.com/datasets/tzelal/binance-bitcoin-dataset-1s-timeframe-p2>.

2. Run everything:

   ```bash
   bash run.sh
   ```

`run.sh` starts Postgres, loads the data, builds and tests the dbt models, and
prints the answers.

### Running the steps individually

The `Makefile` wraps each stage so any one can be run in isolation:

| command | does |
| --- | --- |
| `make up` / `make down` | start / stop Postgres |
| `make load` | load the dataset into `raw.bitcoin_prices` |
| `make deps` | install the dbt packages |
| `make build` | `dbt deps` then `dbt build` (runs and tests every model) |
| `make test` | run the dbt tests (generic and unit) |
| `make answers` | print the answer to each question from the built marts |
| `make all` | the whole pipeline: up, load, build, answers |
| `make lint` / `make format` | sqlfluff lint / fix |

The `Makefile` exports `DBT_PROFILES_DIR`, so dbt finds the project-local
`profiles.yml`. To run dbt directly, either `export DBT_PROFILES_DIR=$(pwd)`
first or pass `--profiles-dir .`, e.g.
`uv run dbt build --select fct_bitcoin_hourly_bars`.

### Developing

Set up the Python environment once:

```bash
uv sync                      # create .venv with dbt + sqlfluff
source .venv/bin/activate    # so dbt / sqlfluff run without the `uv run` prefix
```

A committed `.envrc` does this activation automatically on `cd` if you use
[direnv](https://direnv.net) (`direnv allow` once after cloning).

## Stack

dbt Core 1.x on Postgres, managed with uv. Pinned to `dbt-postgres==1.10.0`
rather than dbt Fusion / Core 2.0, which does not yet support the Postgres
adapter.

## How it works

The guiding principle is "model the data, not the question." The reusable
centerpiece is a detail-preserving general market-data layer; the strategy is a
thin specialization on top. Aggregation is a one-way door, so the lossy
reduction to one number per hour happens only at the final step.

Three layers, no skipping, each in its own schema:

- **staging** (views, schema `staging`): `stg_binance__bitcoin_prices` cleans the
  one-second bars, one row per second. It filters null or non-positive prices,
  dedupes to one row per second, types prices as `numeric`, and derives
  `trade_date`, `hour_of_day`, and `day_of_week` once. Lossless: anything needing
  sub-hour detail reads here.
- **marts, general** (table, schema `marts`): `fct_bitcoin_hourly_bars` resamples
  the seconds to hourly open-high-low-close-volume (open = first, high = max,
  low = min, close = last, volume = sum) with audit columns
  (`observed_seconds`, `trade_count`, first / last observed second). This is the
  one heavy collapse and the reusable product any hourly Bitcoin question reads.
- **intermediate** (ephemeral, schema `intermediate`): the strategy specialization.
  `int_bitcoin__strategy_daily_trades` turns each hour into one buy/sell with
  carry-forward; `int_bitcoin__strategy_equity_curve` compounds the reinvested
  growth factors into a per-hour equity curve.
- **marts, strategy** (tables, schema `marts`): `fct_strategy_performance_by_hour`
  and `fct_strategy_drawdown_by_hour`, one wide row per hour of day, join-free for
  BI. The two questions are answered by ranking these in
  `analyses/answer_strategy_questions.sql`.

Materializations follow cost: staging recomputes cheaply as views; the hourly
collapse is a table; the post-collapse intermediates are tiny and stay ephemeral;
the per-hour marts are tables. The general layer never knows the strategy exists.

## Buy / sell rationale

The strategy buys at the first second of the chosen hour and sells at the last
second of the same hour. Concretely:

- **Buy = the open of the hour's first second bar.** The bar stamped `HH:00:00`
  covers `[HH:00:00, HH:00:01)`; its open is the first trade at the instant the
  hour begins. Using that bar's close instead would enter roughly one second
  late, which is the bug to avoid.
- **Sell = the close of the hour's last second bar.** The last trade before the
  hour ends.

This is symmetric at the two edges and faithful to the assignment's framing: a
15:00 strategy buys at `15:00:00` and sells at `15:59:59`.

**Carry-forward for gaps.** If the hour's first second has no bar, the entry uses
the last known price by lagging the prior hourly bar's close over hourly bars
ordered by time. Because empty hours are simply absent rows, the lag reaches back
across multi-hour gaps for free, with no calendar spine. The staleness of the
carried price is flagged (`carried_price_staleness_seconds`) rather than silently
injected. An hour with no data at all is treated as a no-trade day, not carried.

## Assumptions

The deliberate decisions made where the prompt is ambiguous are recorded in
[`docs/assumptions.md`](docs/assumptions.md). The headline ones: all analysis is
in UTC; prices are `numeric`, never float; the backtest is frictionless by
default with an optional `fee_basis_points` haircut; and the answers are
sample-period-dependent (the Kaggle dump is a partial slice, 2021-02-23 to
2024-08-27). The SQL style rules live in [`docs/style-guide.md`](docs/style-guide.md).

## What I'd do next

Documented but intentionally not built, to keep the scope honest:

- A slim CI: sqlfluff lint plus dbt unit tests, and a state-deferred `dbt build`
  against an ephemeral Postgres on pull requests. The schema macro's env-gated
  prefix is the seam for per-PR schema isolation.
- A timeframe-parameterized resample macro (minute / 4-hour / day bars) so the
  hourly hardcoding generalizes; the resample rule is already the same pattern.
- Incremental / watermark resample and drawdown for a live append-only feed.
- Multi-asset support via a `dim_symbol`, and day-of-week / seasonality slicing
  via a `dim_date` (the daily grain is already preserved upstream for this).
- Risk-adjusted ranking (e.g. a deflated Sharpe to correct for testing 24 hours
  at once), built with a quant partner.
- The optional `dim_trading_hour` session-label seed and a Lightdash connection
  for charting the per-hour marts.
- dbt Fusion once its Postgres adapter ships; the project is already
  Fusion-shaped (standard YAML, unit tests, materializations).
