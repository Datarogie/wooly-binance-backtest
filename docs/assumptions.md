# Assumptions

Deliberate decisions made where the assignment is ambiguous. They are surfaced
here rather than buried in code.

## Dataset

- **Source layout.** A Binance kline dump for BTCUSDT, one row per one-second
  bar: `open_time, open, high, low, close, volume, close_time,
  quote_asset_volume, number_of_trades, taker_buy_base_asset_volume,
  taker_buy_quote_asset_volume, ignore`. The loader probes the CSV header before
  loading to confirm this layout.
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
  accumulates floating-point error; `numeric` keeps it exact. The log-space
  cumulative product (`exp(sum(ln(growth_factor)))`) also stays high-precision in
  Postgres `numeric`. Cumulative and growth values are rounded to 15 decimals to
  shed sub-1e-15 residue, far below any financially meaningful scale, so results
  are deterministic.

## Strategy

- **Buy and sell prices.** Buy is the open of the hour's first second bar (the
  first trade at `HH:00:00`); sell is the close of the hour's last second bar
  (the last trade before `HH+1:00:00`). Symmetric at the two edges and faithful
  to buying at `:00:00` and selling at `:59:59`.
- **Carry-forward.** When the hour's first second has no bar, the entry carries
  forward the prior hourly bar's close via a lag over hourly bars ordered by
  time, which skips empty hours automatically and so handles multi-hour gaps.
  Staleness is flagged in `carried_price_staleness_seconds`. An hour with no data
  at all is a no-trade day, not carried forward. Crypto trades 24/7, so any gap
  is missing data or exchange downtime, not a market session boundary.
- **Reinvestment and compounding.** All proceeds are reinvested into the next
  day's buy, so daily growth factors multiply. "Biggest returns" is the
  geometric (compounded) return, read at the **last** trade date, never the peak
  ever reached, so a peak-then-decline hour is not flattered.
- **Maximum losses.** Exposed three ways so the second question is answerable
  under any reading: the maximum drawdown against the running peak (the primary
  reading used in the answer query), the worst loss below starting capital, and
  the worst single-day return. The answer query labels the chosen one; switching
  is a label change, no rebuild.
- **Fees.** The backtest is frictionless by default but parameterized: the
  `fee_basis_points` variable (default 0) applies as a round-trip haircut on each
  day's growth factor. Fees are not in the price data; they are an injected
  assumption.

## Coverage

- **Trust floor.** An hour's `observed_seconds` (how many of its 3600 seconds
  actually have a bar) is a data-trust measure. Hours below a documented floor
  (`hourly_coverage_floor_seconds`, default 1800) raise a WARN, not an error, so
  thin hours surface without failing the build. Two such hours exist in this
  slice (exchange downtime on 2021-04-25).

## Engine

- **Postgres in Docker.** The assignment names Postgres or MySQL explicitly.
  Postgres in Docker Compose keeps the only host prerequisites to Docker and uv,
  identical on macOS and Windows / WSL2. DuckDB would be a spec deviation and is
  noted only as an unconstrained alternative.
- **dbt Core 1.x, pinned.** `dbt-postgres==1.10.0` (brings dbt-core 1.11.x), not
  dbt Fusion / Core 2.0, whose Postgres adapter is not yet supported.
