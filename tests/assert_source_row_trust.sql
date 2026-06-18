{{ config(severity = 'warn') }}

-- Source-trust flags, one pass over the raw feed. Warn not error: the source is
-- not ours to fix, so a bad row should surface without failing the build.
select open_time
from {{ source('binance', 'bitcoin_prices') }}
-- a taker buy cannot exceed the bar's whole volume
where taker_buy_base_asset_volume > volume
    or taker_buy_quote_asset_volume > quote_asset_volume
    -- a bar must advance in time
    or close_time <= open_time
    -- the average fill (quote / base volume) must sit inside the bar's range;
    -- volume > 0 avoids dividing by zero on a no-trade bar, 1e-6 absorbs the
    -- source's own aggregation rounding
    or (
        volume > 0
        and quote_asset_volume / volume not between low * (1 - 1e-6) and high * (1 + 1e-6)
    )
