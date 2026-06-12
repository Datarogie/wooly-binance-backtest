with source as (
    select * from {{ source('binance', 'bitcoin_prices') }}
),

final as (
    select
        open_time as event_at,
        cast(open as numeric) as open,
        cast(high as numeric) as high,
        cast(low as numeric) as low,
        cast(close as numeric) as close,
        cast(volume as numeric) as volume,
        number_of_trades

    from source
)

select * from final
