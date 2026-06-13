# Bitcoin Backtesting Engine

Intraday Bitcoin strategy backtester, built with dbt on Postgres. One command runs the full thing.

Strategy: buy at the first second of a chosen hour, sell at the last second of that same hour,
reinvesting all proceeds daily. Two questions: which hour had the biggest compounded return,
and which had the lowest maximum losses.

## Prerequisites

- **Docker** to run the database ([Docker Desktop](https://docs.docker.com/get-docker/) on macOS/Windows; [Docker Engine](https://docs.docker.com/engine/install/) on Linux).
- **uv** for Python and dbt: [install guide](https://docs.astral.sh/uv/getting-started/installation/). Reads the committed lockfile; no separate dbt or Python setup needed.

## Quick start

1. Clone the repo and enter it:

   ```bash
   git clone https://github.com/Datarogie/wooly-binance-backtest.git
   cd wooly-binance-backtest
   ```

2. Put the dataset CSV in the project root (any `.csv` filename works; the loader
   auto-detects the single CSV in the root). It is never committed. Kaggle CLI:

   ```bash
   kaggle datasets download -d tzelal/binance-bitcoin-dataset-1s-timeframe-p2 --unzip -p .
   ```

   or download and unzip manually from the Kaggle dataset page.

3. Run everything:

   ```bash
   bash run.sh
   ```

`run.sh` starts Postgres, loads the data, builds and tests the dbt models, prints
the answers, and writes the answer charts to `docs/screenshots/`.

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
| `make charts` | write the Q1 / Q2 answer charts to `docs/screenshots/` |

The `Makefile` exports `DBT_PROFILES_DIR`. To run dbt directly:
`uv run dbt build --profiles-dir .`

### Developing

```bash
uv sync                      # create .venv
source .venv/bin/activate    # or use direnv (committed .envrc)
```

`bash scripts/setup.sh` does the one-time setup (venv + dbt packages) and enables
direnv if it's installed. The committed `.envrc` activates the venv and exports
`DBT_PROFILES_DIR` on `cd`, so bare `dbt build` works without any prefix.

SQL style rules live in [`docs/style-guide.md`](docs/style-guide.md); `make lint`
and `make format` enforce them with sqlfluff.

## Charts

`run.sh` writes two answer charts to `docs/screenshots/` (or run `make charts` on
its own): `total_compounded_return` by hour for Q1 (hour 22 is the tallest bar) and
`maximum_drawdown` by hour for Q2 (hour 10 is closest to zero). It is a small
matplotlib script (`scripts/make_charts.py`) reading `fct_strategy_by_hour`, and it
prints a clickable link to each PNG at the end of the run.

![Q1: compounded return by hour](docs/screenshots/q1_compounded_return_by_hour.png)

![Q2: maximum drawdown by hour](docs/screenshots/q2_max_drawdown_by_hour.png)

I first wired the marts for [Lightdash](https://www.lightdash.com) (the column
metadata is still in `models/marts/_marts__models.yml`), but the local self-host is
heavier to stand up than it used to be, so for a one-off I pivoted to the matplotlib
script above.

## Stack

dbt Core 1.x on Postgres, managed with uv. Pinned to `dbt-postgres==1.10.0`
(dbt Fusion / Core 2.0 does not yet support the Postgres adapter).

## How it works

Three layers, each in its own schema:

- **staging** (views, `staging` schema): `stg_binance__bitcoin_prices` cleans the
  one-second bars: drops exact duplicate rows, type casts, column aliases. Kept close
  to source; no grain changes or business logic.
- **intermediate** (`intermediate` schema): the heavy work.
  `int_bitcoin__hourly_bars` resamples the deduped seconds to hourly OHLCV
  (open = first, high = max, low = min, close = last, volume = sum), materialized as a
  `table` since it is the one expensive query. The strategy models
  (`int_bitcoin__strategy_daily_trades`, `int_bitcoin__strategy_equity_curve`) are
  ephemeral; they simulate trades then compound the returns.
- **marts** (tables, `marts` schema): `fct_bitcoin_hourly_bars` is a thin view
  over the hourly bars intermediate; anything needing hourly OHLCV reads from here.
  `fct_strategy_by_hour` is a 24-row aggregate, one per hour of day, holding both
  the return measures (Q1) and the loss/drawdown measures (Q2) for BI tools or the
  analysis query.

The answers are produced by `analyses/answer_strategy_questions.sql`, an ad-hoc
query over the marts run by `make answers`.

## Implementation thoughts

Why I made the calls I did, by layer. The models show the what; this is the why,
the trade-offs, and what I'd change in a different scenario.

### Staging

**`stg_binance__bitcoin_prices`.** The only real judgement call was the duplicate
rows. The source repeats some seconds verbatim, which reads like ingestion replay,
so I drop them with `select distinct` rather than a `row_number` filter: distinct
only removes fully identical rows, so it can't silently merge two genuinely
different prints in the same second. In a real pipeline I'd fix this upstream in
ingestion, not the warehouse, but staging is the right place when the warehouse is
all you own. Prices are `numeric` not float so rounding doesn't compound over
thousands of days.

The one cost I'd flag is the `unique` test on the second-grain key: it scans the
full raw table (~110M rows) and runs for minutes. I wouldn't lean on a dbt test for
that in production, I'd enforce the key at ingestion with a real primary-key
constraint so uniqueness holds on write and the test is redundant. The Postgres
levers I'd reach for: a unique index on the key (dbt's `indexes=` model config),
declarative partitioning of the raw seconds by month on `event_at` so the hourly
resample prunes to just the range it needs, and a BRIN index on `event_at` since
the feed is append-only and time-ordered (tiny, and built for range scans).
Postgres has no Snowflake-style cluster key, the nearest equivalents are that BRIN
index and the one-shot `CLUSTER` physical reorder.

### Intermediate layer

This is where the heavy work and the strategy live. I kept it as small steps that
build on each other rather than one big query, so each is independently testable:
the heavy resample, the trade simulation, then the compounding.

**Hourly bars (`int_bitcoin__hourly_bars`).** Rolled seconds up to the hour mostly
for scale: one row per second per symbol doesn't hold up once you picture every
crypto, and maybe stocks, reporting every second. The hour is the smallest grain
the questions need and a fine unit to serve future ones from. It's the only table
in this layer since it's the one heavy collapse: do it once, everything downstream
stays cheap. The one resample subtlety: open/close must be first/last by time, not
min/max, hence `array_agg`.

I model only the hours that actually traded (sparse). A handful of hours in the
sample have no trades, mostly the first morning of the feed. The trade-off: I did
*not* build a calendar spine to force a row for every hour. A no-trade hour simply
isn't in the data, and in the strategy that is identical to a no-change day (a
growth factor of 1.0), so it changes no answer; a spine would add real machinery
(a second model, carry-forward, a no-trade flag) for what is a presentation
concern. If you chart the equity curve over time and want a gapless axis, handle it
at the chart layer: most tools connect the line straight across a missing point,
and the cumulative value carries (it never resets to zero). If you truly need a row
per hour, forward-fill against a `dim_date` x 24-hour spine in the BI layer rather
than in these models.

**Daily trades (`int_bitcoin__strategy_daily_trades`).** Its own step so the
pricing logic is modular. Crypto runs 24/7, so an hour missing its start is missing
data, not a closed market: I carry the prior close forward as the entry and flag
how stale it is rather than hide the guess. Fees are a single variable, so
frictionless to realistic is one switch.

**Equity curve (`int_bitcoin__strategy_equity_curve`).** Its own step to keep the
compounding separate. I knew reinvesting compounds, each day multiplies your
balance by that day's gain or loss, so it's not a plain running total. I'd normally
lean on a data science or analytics teammate for the exact calculation, but a bit
of searching for how to multiply values down the rows in Postgres showed there's no
built-in running-multiply, and the standard workaround is `exp(sum(ln(...)))`, so
that's what I used.

### Marts

Two facts here, and the split between them is deliberate. `fct_bitcoin_hourly_bars`
is the self-serve OHLCV surface anything can read; `fct_strategy_by_hour` is the
strategy result, one row per hour of day.

I almost shipped the strategy as two separate models in the mart layer, one for the
return question and one for drawdown. I pulled them back into one. Both were the same
grain (one row per hour of day), both came off the same equity curve, and they'd
started duplicating columns (`trading_days`, the trade-date bounds). That's the tell:
return and risk aren't two business processes, they're two reads of the same one, so
they belong in one model at that grain. Splitting same-grain facts is the thing
you're told not to do, and it also makes the self-serve story worse, an analyst would
open one explore, not pick between two that share half their columns. So Q1 sorts by
`total_compounded_return` and Q2 by `maximum_drawdown`, both off the same 24 rows.

I kept the hourly bars mart separate though, because that one genuinely is a
different grain (~31k hourly rows, a time series) and a different thing (raw market
data, not strategy output). The rule I'm following is one fact per process per
grain, not "fewer files for its own sake". If the strategy later grew a measure
family with its own grain or source, I'd split that back out.

On actually answering the two questions, there are two analyses in `analyses/`, and
they answer slightly different versions of it. `answer_strategy_questions.sql` reads
the `fct_strategy_by_hour` mart: it treats the question as "across all the data we
have, which hour was best", one fixed answer with the compounding already done and
tested in the model. `answer_strategy_questions_windowed.sql` pushes that compounding
downstream into the query so the start date is editable, because the winning hour can
move depending on where you start (returns compound, so the window matters). The
answers I report use the first one (full history); the second is there for anyone who
wants to test a different window without touching the models.

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
(Kaggle dump covers 2021-02-23 to 2024-08-27).

## What I'd do next

- CI: sqlfluff lint + dbt unit tests on PRs against an ephemeral Postgres.
- Parameterized resample macro (minute / 4-hour / day bars).
- Incremental resample and drawdown for a live append-only feed.
- Day-of-week slicing via a `dim_date`. The feed is BTCUSDT only, so the models
  stay single-asset; if more symbols ever landed I'd add a `dim_symbol` and key the
  grain on it, but that's hypothetical against this dataset.
- Risk-adjusted ranking (e.g. deflated Sharpe for 24-hypothesis correction).
- dbt Fusion once its Postgres adapter ships.
