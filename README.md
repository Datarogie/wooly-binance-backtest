# Bitcoin Backtesting Engine

A reproducible backtesting engine for a single intraday Bitcoin trading strategy,
built as a dbt project on Postgres and runnable end to end with one bash script.

The strategy under test: buy at the first second of a chosen hour, sell at the
last second of that same hour, every day, reinvesting all proceeds so returns
compound. It answers two questions: which hour of the day had the biggest
compounded returns, and which had the lowest maximum losses.

> Work in progress: the deeper sections below are placeholders and get filled in
> as the models land.

## Quick start

You need [uv](https://docs.astral.sh/uv/), a running Docker engine (Docker
Desktop, Colima, or Rancher Desktop), and the dataset.

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

The `Makefile` covers the steps that bundle multiple or non-dbt commands:

| command | does |
| --- | --- |
| `make up` / `make down` | start / stop Postgres |
| `make load` | load the dataset |
| `make lint` / `make format` | sqlfluff lint / fix |

dbt itself you run directly, e.g. `dbt build` or
`dbt build --select answer_strategy_questions`.

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

_TODO: layering overview (staging, intermediate, marts), the
general-vs-strategy split, and materialization choices._

## Buy / sell rationale

_TODO: buy = open of the hour's first second; sell = close of the last second;
why this is faithful to buying at `:00:00` and selling at `:59:59`; and the
carry-forward handling for gappy boundaries._

## Assumptions

_TODO: summary and link to `docs/assumptions.md`._

## What I'd do next

_TODO: documented-only future work (CI, incremental resample,
timeframe-parameterized macro, multi-asset, seasonality, Lightdash)._
