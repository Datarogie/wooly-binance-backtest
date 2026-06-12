{{ config(materialized='table') }}

with seconds as (
    select * from {{ ref('stg_binance__bitcoin_prices') }}
),

deduped as (
    select
        event_at,
        open,
        high,
        low,
        close,
        volume,
        number_of_trades,
        row_number() over (partition by event_at order by volume desc) as row_priority

    from seconds
),

calendar as (
    select
        event_at,
        open,
        high,
        low,
        close,
        volume,
        number_of_trades,
        cast(event_at as date) as trade_date,
        cast(extract(hour from event_at) as int) as hour_of_day

    from deduped
    where row_priority = 1
),

final as (
    select
        trade_date,
        hour_of_day,
        date_trunc('hour', min(event_at)) as hour_start_at,
        (array_agg(open order by event_at asc))[1] as bar_open,
        max(high) as bar_high,
        min(low) as bar_low,
        (array_agg(close order by event_at desc))[1] as bar_close,
        sum(volume) as volume,
        min(event_at) as first_observed_second_at,
        max(event_at) as last_observed_second_at,
        cast(count(*) as int) as observed_seconds,
        cast(sum(number_of_trades) as int) as trade_count

    from calendar
    group by trade_date, hour_of_day
)

select * from final
