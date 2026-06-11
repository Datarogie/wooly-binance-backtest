-- Runs once on first container init (mounted into /docker-entrypoint-initdb.d),
-- and is re-applied idempotently by scripts/load_data.sh. Creates the schemas
-- dbt routes models into, plus the raw landing table for the dataset.

create schema if not exists raw;
create schema if not exists staging;
create schema if not exists intermediate;
create schema if not exists marts;

-- Raw Binance 1-second klines, loaded verbatim from the project-root CSV.
-- Column order matches the CSV exactly so COPY maps fields by position.
-- Open Time / Close Time are datetime strings in this dataset (not unix epochs),
-- so they land as timestamp and staging can cast them directly.
-- Unlogged: this table is reproducible from the CSV, so we skip WAL for a faster
-- bulk load and just reload if it is ever emptied.
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
