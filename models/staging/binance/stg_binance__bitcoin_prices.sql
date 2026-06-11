with source as (

    select * from {{ source('binance', 'bitcoin_prices') }}
    -- With a real ingestion this would ideally sit upstream. kept here as basic source-cleansing filter.
    where
        open_time is not null
        and open > 0
        and high > 0
        and low > 0
        and close > 0

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
