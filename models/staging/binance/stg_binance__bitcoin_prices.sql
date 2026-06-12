with source as (
    select * from {{ source('binance', 'bitcoin_prices') }}
),

deduped as (
    -- raw CSV has exact-duplicate 252 records removed
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
