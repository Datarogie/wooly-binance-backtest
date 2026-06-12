with source as (

    select * from {{ source('binance', 'bitcoin_prices') }}
    -- sole source-cleansing gate; real ingestion would push this upstream
    where
        open_time is not null
        and open > 0
        and high > 0
        and low > 0
        and close > 0

),

deduped as (

    -- raw CSV has exact-duplicate second-bars at ~7 timestamps (export overlap)
    select distinct on (open_time) *
    from source
    order by open_time

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['open_time']) }} as bitcoin_price_id,
        open_time as event_at,
        cast(open as numeric) as open,
        cast(high as numeric) as high,
        cast(low as numeric) as low,
        cast(close as numeric) as close,
        cast(volume as numeric) as volume,
        number_of_trades
    from deduped

)

select * from final
