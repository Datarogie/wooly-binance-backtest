# Bitcoin Backtesting Engine

A reproducible backtesting engine for a single intraday Bitcoin trading strategy,
built as a dbt project on Postgres and runnable end to end with one bash script.

The strategy under test: buy at the first second of a chosen hour, sell at the
last second of that same hour, every day, reinvesting all proceeds so returns
compound. It answers two questions: which hour of the day had the biggest
compounded returns, and which had the lowest maximum losses.

> Status: scaffolding in place (Phase 1). Models, data load, and the answer
> query land in subsequent phases. Sections below are placeholders to be filled
> in as the project is built (see the issue tracker).

## Prerequisites

- [uv](https://docs.astral.sh/uv/) for Python and dbt
- A Docker-compatible engine (Docker Desktop, Colima, or Rancher Desktop)

## Setup

1. Clone the repository.
2. Place the Binance 1-second CSV in the project root. The dataset is never
   committed; the run script assumes it is present here. (Kaggle:
   `binance-bitcoin-dataset-1s-timeframe-p2`.)
3. Run the pipeline:

   ```bash
   bash run.sh
   ```

`run.sh` starts the database, loads the data, builds and tests the dbt models,
and prints the answers. See the `Makefile` for the individual steps
(`make up`, `make load`, `make build`, `make answers`, `make lint`).

## How it works

_TODO (Phase 9): layering overview (staging, intermediate, marts), the
general-vs-strategy split, and materialization choices._

## Buy / sell rationale

_TODO (Phase 9): buy = open of the hour's first second; sell = close of the last
second; why this is faithful to buying at `:00:00` and selling at `:59:59`; and
the carry-forward handling for gappy boundaries._

## Assumptions

_TODO (Phase 9): summary and link to `docs/assumptions.md`._

## What I'd do next

_TODO (Phase 9): documented-only future work (CI, incremental resample,
timeframe-parameterized macro, multi-asset, seasonality, Lightdash)._
