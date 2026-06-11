with seconds as (

    select * from {{ ref('stg_binance__bitcoin_prices') }}

),

resampled as (

    -- Canonical OHLCV resample over each clock hour: open = first by time,
    -- high = max, low = min, close = last by time, volume = sum. open and close
    -- are order-sensitive, so they are pulled with array_agg ordered by event_at
    -- rather than a plain aggregate, which would lose the time ordering.
    select
        trade_date,
        hour_of_day,
        cast(count(*) as int) as observed_seconds,
        cast(sum(number_of_trades) as int) as trade_count,
        (array_agg(open order by event_at asc))[1] as bar_open,
        max(high) as bar_high,
        min(low) as bar_low,
        (array_agg(close order by event_at desc))[1] as bar_close,
        sum(volume) as volume,
        date_trunc('hour', min(event_at)) as hour_start_at,
        min(event_at) as first_observed_second_at,
        max(event_at) as last_observed_second_at
    from seconds
    group by trade_date, hour_of_day

),

final as (

    select
        trade_date,
        hour_of_day,
        hour_start_at,
        bar_open,
        bar_high,
        bar_low,
        bar_close,
        volume,
        first_observed_second_at,
        last_observed_second_at,
        observed_seconds,
        trade_count
    from resampled

)

select * from final
