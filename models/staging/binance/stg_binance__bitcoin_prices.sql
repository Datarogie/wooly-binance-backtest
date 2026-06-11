with source as (

    select * from {{ source('binance', 'bitcoin_prices') }}
    -- Trust gate: only bars with all four prices present and positive. A zero or
    -- negative price is corrupt and would poison every downstream growth factor.
    where
        open_time is not null
        and open is not null and open > 0
        and high is not null and high > 0
        and low is not null and low > 0
        and close is not null and close > 0

),

deduped as (

    -- Grain is one row per second. If the source ever double-prints a second,
    -- keep the highest-volume copy so the survivor is the most complete bar.
    select
        *,
        row_number() over (
            partition by open_time
            order by volume desc
        ) as row_priority
    from source

),

final as (

    select
        open_time as event_at,
        cast(open as numeric) as open,
        cast(high as numeric) as high,
        cast(low as numeric) as low,
        cast(close as numeric) as close,
        cast(volume as numeric) as volume,
        number_of_trades,
        cast(open_time as date) as trade_date,
        cast(extract(hour from open_time) as int) as hour_of_day,
        cast(extract(isodow from open_time) as int) as day_of_week
    from deduped
    where row_priority = 1

)

select * from final
