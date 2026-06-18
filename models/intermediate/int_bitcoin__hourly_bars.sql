{{ config(materialized='table') }}

with seconds as (
    select * from {{ ref('stg_binance__bitcoin_prices') }}
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
        event_at::date as trade_date,
        extract(hour from event_at)::int as hour_of_day

    from seconds
),

aggregated as (
    select
        {{ dbt_utils.generate_surrogate_key(['trade_date', 'hour_of_day']) }} as pk_hourly_bar_key,
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
        count(*)::int as observed_seconds,
        sum(number_of_trades)::int as trade_count

    from calendar
    group by trade_date, hour_of_day
),

final as (
    select
        aggregated.*,
        first_observed_second_at = hour_start_at as has_open_boundary,
        last_observed_second_at = hour_start_at + interval '59 minutes 59 seconds'
            as has_close_boundary

    from aggregated
)

select * from final
