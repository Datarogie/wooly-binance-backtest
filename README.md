# Bitcoin Backtesting Engine

Intraday Bitcoin strategy backtester, built with dbt on Postgres. One command runs the full thing.

Strategy: buy at the first second of a chosen hour, sell at the last second of that same hour,
reinvesting all proceeds daily. Two questions: which hour had the biggest compounded return,
and which had the lowest maximum losses.

## Prerequisites

- **Docker** to run the database ([Docker Desktop](https://docs.docker.com/get-docker/) on macOS/Windows; [Docker Engine](https://docs.docker.com/engine/install/) on Linux).
- **uv** for Python and dbt: [install guide](https://docs.astral.sh/uv/getting-started/installation/). Reads the committed lockfile; no separate dbt or Python setup needed.

## Quick start

1. Put the dataset CSV in the project root (never committed). Kaggle CLI:

   ```bash
   kaggle datasets download -d tzelal/binance-bitcoin-dataset-1s-timeframe-p2 --unzip -p .
   ```

   or download and unzip manually from the Kaggle dataset page.

2. Run everything:

   ```bash
   bash run.sh
   ```

`run.sh` starts Postgres, loads the data, builds and tests the dbt models, and
prints the answers.

### Running steps individually

| command | does |
| --- | --- |
| `make up` / `make down` | start / stop Postgres |
| `make load` | load the dataset into `raw.bitcoin_prices` |
| `make deps` | install dbt packages |
| `make build` | `dbt deps` then `dbt build` |
| `make test` | run dbt tests |
| `make answers` | print the answers from the built marts |
| `make all` | full pipeline: up, load, build, answers |
| `make lint` / `make format` | sqlfluff lint / fix |
| `make lightdash` | validate Lightdash metadata offline (see below) |

The `Makefile` exports `DBT_PROFILES_DIR`. To run dbt directly:
`uv run dbt build --profiles-dir .`

### Developing

```bash
uv sync                      # create .venv
source .venv/bin/activate    # or use direnv (committed .envrc)
```

## Explore in Lightdash

The two per-hour strategy marts are annotated for [Lightdash](https://www.lightdash.com),
explorable with no extra modeling. The metadata lives in
`models/marts/_marts__models.yml` under each column's `config.meta`:
`hour_of_day` and the trade-date columns are dimensions; the headline measures
(`total_compounded_return`, `maximum_drawdown`, `maximum_loss_from_start`,
`worst_single_day_return`, `average_daily_return`, and the comparability columns)
are metrics. Each mart is already one row per hour, so metrics use `type: max`,
a passthrough that returns the hour's single value when grouped by `hour_of_day`.
Charting `total_compounded_return` by `hour_of_day` answers Q1 (hour 22 is the
tallest bar); charting `maximum_drawdown` answers Q2 (hour 10 is closest to zero).

Lightdash reads the connection from this project's `profiles.yml`, which is
already env-var driven; no separate connection file needed.

To validate the metadata offline with no Lightdash instance:

```bash
npm install -g @lightdash/cli   # one-time
make lightdash                  # compiles the four explores from the dbt manifest
```

`make lightdash` runs `lightdash compile --skip-warehouse-catalog` (uses YAML
column types, no warehouse round-trip) and should report `SUCCESS=4 ERRORS=0`.
To build charts live, point Lightdash at this dbt project (`lightdash deploy` or
`start-preview`). When running against a live warehouse, activate the venv first
(`source .venv/bin/activate`) so the CLI's bare `dbt` call resolves.

## Stack

dbt Core 1.x on Postgres, managed with uv. Pinned to `dbt-postgres==1.10.0`
(dbt Fusion / Core 2.0 does not yet support the Postgres adapter).

## How it works

Three layers, each in its own schema:

- **staging** (views, `staging` schema): `stg_binance__bitcoin_prices` cleans the
  one-second bars - null/zero price filter, type casts, column aliases. Kept close
  to source; no grain changes or business logic.
- **intermediate** (ephemeral, `intermediate` schema): the heavy work.
  `int_bitcoin__hourly_bars` dedupes to one second per timestamp then resamples to
  hourly OHLCV (open = first, high = max, low = min, close = last, volume = sum);
  materialized as a `table` since it is the one expensive query. The strategy
  models (`int_bitcoin__strategy_daily_trades`, `int_bitcoin__strategy_equity_curve`)
  simulate trades and compound the returns.
- **marts** (tables, `marts` schema): `fct_bitcoin_hourly_bars` is a thin view
  over the hourly bars intermediate; anything needing hourly OHLCV reads from here. `fct_strategy_performance_by_hour` and `fct_strategy_drawdown_by_hour`
  are 24-row aggregates, one per hour of day, for BI tools or the analysis query.

The answers are produced by `analyses/answer_strategy_questions.sql`, an ad-hoc
query over the marts run by `make answers`.

## Buy / sell prices

- **Buy = open of the hour's first second bar.** Covers `[HH:00:00, HH:00:01)`; its open is the first trade at the start of the hour.
- **Sell = close of the hour's last second bar.** The last trade before the hour ends.

**Carry-forward for gaps.** If the hour's first second has no bar, entry uses the
prior hourly bar's close, lagged over hourly bars ordered by time. Staleness is
flagged in `carried_price_staleness_seconds`. An hour with no data at all is a
no-trade day.

## Assumptions

Where the brief was ambiguous, the calls are documented in
[`docs/assumptions.md`](docs/assumptions.md). Key ones: all analysis is UTC;
prices are `numeric` not float; the backtest is frictionless by default with an
optional `fee_basis_points` variable; answers are sample-period-dependent
(Kaggle dump covers 2021-02-23 to 2024-08-27). SQL style rules are in
[`docs/style-guide.md`](docs/style-guide.md).

## What I'd do next

- CI: sqlfluff lint + dbt unit tests on PRs against an ephemeral Postgres.
- Parameterized resample macro (minute / 4-hour / day bars).
- Incremental resample and drawdown for a live append-only feed.
- Multi-asset support via a `dim_symbol`; day-of-week slicing via a `dim_date`.
- Risk-adjusted ranking (e.g. deflated Sharpe for 24-hypothesis correction).
- dbt Fusion once its Postgres adapter ships.
