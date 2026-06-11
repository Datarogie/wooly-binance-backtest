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

### Running it yourself

`bash run.sh` is the whole pipeline in one command and needs nothing beyond the
prerequisites; it manages the dbt environment for you. To run pieces yourself,
point dbt at the project-local profiles once, then use `uv run` (it installs
from the lockfile on first use, so there is no separate setup step):

```bash
export DBT_PROFILES_DIR="$PWD"   # once per shell
uv run dbt build                 # build and test every model
uv run dbt test                  # just the tests
uv run dbt docs generate && uv run dbt docs serve   # browse the lineage and docs
```

`bash scripts/print_answers.sh` prints the two answers, and `docker compose up -d
--wait` / `docker compose down` controls Postgres.

`bash scripts/setup.sh` does the one-time bits (create the venv, install the dbt
packages, enable direnv if present), though `uv run` and `run.sh` work without it.

Two optional conveniences:

- **Makefile shortcuts** (they set `DBT_PROFILES_DIR` for you): `make build`,
  `make test`, `make answers`, `make up` / `make down`, `make load`,
  `make lint` / `make format`, `make lightdash`, and `make all`.
- **[direnv](https://direnv.net)** to drop the `uv run` prefix entirely: run
  `uv sync` once to create the venv, then `direnv allow`. The committed `.envrc`
  activates the venv and sets `DBT_PROFILES_DIR` on `cd`, so bare `dbt build`
  works.

## Explore in Lightdash

The two per-hour strategy marts are annotated for [Lightdash](https://www.lightdash.com)
so they are explorable with no extra modeling. The metadata lives in
`models/marts/_marts__models.yml` under each column's `config.meta`:
`hour_of_day` and the trade-date columns are dimensions, and the headline
measures (`total_compounded_return`, `maximum_drawdown`, `maximum_loss_from_start`,
`worst_single_day_return`, `average_daily_return`, and the comparability columns)
are metrics. Because each mart is already one row per hour, the metrics use
`type: max`, a passthrough that returns the hour's single value when grouped by
`hour_of_day`. Charting `total_compounded_return` by `hour_of_day` surfaces Q1
(hour 22 is the tallest bar); charting `maximum_drawdown` by `hour_of_day`
surfaces Q2 (hour 10 is closest to zero).

Lightdash reads the warehouse connection straight from this project's
`profiles.yml`, which is already env-var driven, so there is no separate
connection file to keep in sync.

To validate the metadata offline, with no Lightdash instance:

```bash
npm install -g @lightdash/cli   # one-time
make lightdash                  # compiles the four explores from the dbt manifest
```

`make lightdash` runs `lightdash compile --skip-warehouse-catalog` (it uses the
YAML column types, so it needs no warehouse round-trip) and should report
`SUCCESS=5 ERRORS=0`. To build the two answer charts live, point the Lightdash
app at this dbt project (`lightdash deploy`); the click-by-click steps are in
[`docs/lightdash-viz.md`](docs/lightdash-viz.md).

When running the Lightdash CLI against a live warehouse (`generate`, `deploy`),
activate the venv first (`source .venv/bin/activate`) so its bare `dbt` call
resolves, and note `profiles.yml` sets `sslmode: disable` so it connects to the
local Postgres, which does not speak SSL.

## Stack

dbt Core 1.x on Postgres, managed with uv. Pinned to `dbt-postgres==1.10.0`
rather than dbt Fusion / Core 2.0, which does not yet support the Postgres
adapter.

## How it works

The guiding principle is "model the data, not the question." The reusable
centerpiece is a detail-preserving general market-data layer; the strategy is a
thin specialization on top. Aggregation is a one-way door, so the lossy
reduction to one number per hour happens only at the final step.

Each layer reads only from the layer below it, each in its own schema:

- **staging** (views, schema `staging`): `stg_binance__bitcoin_prices` keeps the
  one-second bars close to source. It aliases the columns, casts prices to
  `numeric`, and filters null or non-positive prices, nothing more. Lossless:
  anything needing sub-hour detail reads here.
- **intermediate** (schema `intermediate`): `int_bitcoin__hourly_bars` is the one
  heavy collapse. It dedupes to one row per second, derives `trade_date` and
  `hour_of_day`, and resamples the seconds to hourly open-high-low-close-volume
  (open = first, high = max, low = min, close = last, volume = sum) with audit
  columns (`observed_seconds`, `trade_count`, first / last observed second);
  materialized as a table so it is computed once. On top of it the strategy
  specialization stays ephemeral: `int_bitcoin__strategy_daily_trades` turns each
  hour into one buy/sell with carry-forward, and
  `int_bitcoin__strategy_equity_curve` compounds the reinvested growth factors
  into a per-hour equity curve.
- **marts** (schema `marts`): `fct_bitcoin_hourly_bars` is a thin view publishing
  the hourly bars as the reusable general-layer product any hourly Bitcoin
  question reads. `fct_strategy_performance_by_hour` and
  `fct_strategy_drawdown_by_hour` are tables, one wide row per hour of day,
  join-free for BI. The two questions are answered by ranking these in
  `analyses/answer_strategy_questions.sql`.

Materializations follow cost and layering: staging is cheap views; the hourly
collapse is a table computed once; the post-collapse strategy intermediates stay
ephemeral; the published hourly view is thin and the per-hour strategy marts are
tables. The general layer never knows the strategy exists.

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
- The optional `dim_trading_hour` session-label seed for human-readable hour
  labels in the Lightdash dimension.
- dbt Fusion once its Postgres adapter ships; the project is already
  Fusion-shaped (standard YAML, unit tests, materializations).
