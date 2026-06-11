-- Schemas dbt routes models into, plus the raw landing table. Created on
-- container init and re-applied idempotently by load_data.sh.

create schema if not exists raw;
create schema if not exists staging;
create schema if not exists intermediate;
create schema if not exists marts;

-- Raw Binance 1-second bars. Column order matches the CSV so COPY maps by
-- position. Unlogged: rebuilt from the CSV, so we skip WAL for a faster load.
create unlogged table if not exists raw.bitcoin_prices (
    open_time                     timestamp,
    open                          numeric,
    high                          numeric,
    low                           numeric,
    close                         numeric,
    volume                        numeric,
    close_time                    timestamp,
    quote_asset_volume            numeric,
    number_of_trades              integer,
    taker_buy_base_asset_volume   numeric,
    taker_buy_quote_asset_volume  numeric,
    ignore                        numeric
);
