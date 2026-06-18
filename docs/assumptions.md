# Assumptions

Deliberate decisions made where the assignment is ambiguous. They are surfaced
here rather than buried in code.

## Dataset

- **Source layout.** A Binance kline dump for BTCUSDT, one row per one-second
  bar: `open_time, open, high, low, close, volume, close_time,
  quote_asset_volume, number_of_trades, taker_buy_base_asset_volume,
  taker_buy_quote_asset_volume, ignore`. The loader probes the CSV header before
  loading to confirm this layout.
- **Duplicate source rows.** The dump repeats some seconds verbatim (exact
  duplicate rows). Staging drops them with `select distinct`, which only removes
  fully identical rows, so two genuinely different prints in the same second are
  preserved. In a real pipeline this would be fixed upstream in ingestion.
- **Timestamps are real datetimes, not epochs.** In this dump `open_time` and
  `close_time` are `YYYY-MM-DD HH:MM:SS` strings, so staging casts them directly
  with no division. The loader asserts this on the first data row; if a future
  export ships epoch integers instead, the loader fails loudly rather than
  loading garbage.
- **UTC throughout.** "Hour of day" is meaningless without a fixed timezone, so
  all analysis is defined in UTC, the timezone the source is stamped in.
- **Single symbol.** BTCUSDT only; the dump has no symbol column, so no filter is
  needed. Multi-asset support is future work via a `dim_symbol`.
- **Partial slice.** The Kaggle dataset is a partial export (2021-02-23 to
  2024-08-27), so the answers are sample-period-dependent. A different slice can
  change which hour wins.

## Typing

- **Prices are `numeric`, never float.** Compounding across thousands of days
  accumulates floating-point error; `numeric` keeps it exact. Staging casts are
  explicit and bounded: prices `numeric(18,8)`, volume `numeric(28,8)`. Scale 8
  matches Binance asset precision, so no source decimals are dropped (a singular
  test using `scale()` fails the build if a source value carries more). Raw stays
  permissive; typing happens at staging.
- **Reported values round to 4 decimals.** Per guidance that 4 dp is enough,
  growth factors, the compounded curve, returns, and drawdowns all round to 4 dp.
  Rounding the daily growth factor quantizes daily returns to ~1 bp; that is a
  deliberate readability tradeoff over carrying more precision into the compound.

## Strategy

- **Buy and sell prices.** Buy is the open of the hour's first second bar (the
  first trade at `HH:00:00`); sell is the close of the hour's last second bar
  (the last trade before `HH+1:00:00`). Matches buying at `:00:00` and selling
  at `:59:59` exactly.
- **Boundary completeness.** The strategy trades an hour only when a real bar
  exists at both boundary seconds: the entry at `HH:00:00` and the exit at
  `HH:59:59`. Hours missing either are dropped, never back-filled: a price at
  `:50` does not imply the price at `:59`, so carrying it forward would invent an
  entry or exit that never traded. The flags `has_open_boundary` and
  `has_close_boundary` on the hourly bars drive the filter; the OHLCV bars fact
  keeps every hour so general queries still see them.
- **Reinvestment and compounding.** All proceeds are reinvested into the next
  day's buy, so daily growth factors multiply. "Biggest returns" is the
  geometric (compounded) return, read at the **last** trade date, never the peak
  ever reached, so a peak-then-decline hour is not flattered.
- **Maximum losses.** Tracked three ways so the answer holds regardless of how
  "maximum losses" is read: the maximum drawdown against the running peak (the primary
  reading used in the answer query), the worst loss below starting capital, and
  the worst single-day return. The answer query labels the chosen one; switching
  is a label change, no rebuild.
- **Fees.** The backtest is frictionless by default but parameterized: the
  `fee_basis_points` variable (default 0) applies as a round-trip haircut on each
  day's growth factor. Fees are not in the price data; they are an injected
  assumption.

## Coverage

- **Coverage signal, no hard floor.** Each hour exposes `observed_seconds` (how
  many of its 3600 seconds carried a bar) as a data-quality signal. It is not
  gated by a test, so thin hours surface through the column rather than failing
  the build. A couple of hours in this slice are thin from exchange downtime
  (2021-04-25).

## Source trust

- **Validate the source, flag don't block.** Singular tests reconcile the raw feed
  against itself: taker volume within total, implied VWAP inside the bar's
  `[low, high]`, `close_time` after `open_time`. These run at warn severity, so a
  suspect row surfaces as a flag rather than failing the build on data we do not
  own. Staging invariants we do control (OHLC ordering, prices `> 0`, surrogate
  uniqueness) and the `scale()` no-truncation guard stay at error severity.
- **Outlier surfacing.** `number_of_trades` carries a warn-level upper bound, so a
  second reporting an implausible trade count (the classic "a million trades"
  row) flags without blocking.

## Engine

- **Postgres in Docker.** The assignment names Postgres or MySQL explicitly.
  Postgres in Docker Compose keeps the only host prerequisites to Docker and uv,
  identical on macOS and Windows / WSL2. DuckDB would be a spec deviation and is
  noted only as an unconstrained alternative.
- **dbt Core 1.x, pinned.** `dbt-postgres==1.10.0` (brings dbt-core 1.11.x), not
  dbt Fusion / Core 2.0, whose Postgres adapter is not yet supported.

## Orchestration

- **Shell for glue, SQL for transforms, Python for the chart.** `run.sh` and the
  `scripts/` helpers only chain CLIs: `docker compose`, `psql`, `dbt`. The one
  data step is streaming the multi-GB CSV into Postgres via `psql \copy`, a single
  streamed COPY that is faster and lower-memory than a row-by-row Python loader.
  All transformation lives in dbt SQL where it is tested and documented; Python is
  used where it fits, for the answer charts (`make_charts.py`). The split is by
  job, not by preference.
