with equity_curve as (

    select * from {{ ref('int_bitcoin__strategy_equity_curve') }}

),

last_day as (

    select distinct on (hour_of_day)
        hour_of_day,
        cumulative_return as total_compounded_return
    from equity_curve
    order by hour_of_day asc, trade_date desc

),

per_hour as (

    select
        hour_of_day,
        cast(count(*) as int) as trading_days,
        avg(daily_return) as average_daily_return,
        stddev_samp(daily_return) as daily_return_standard_deviation,
        min(trade_date) as first_trade_date,
        max(trade_date) as last_trade_date
    from equity_curve
    group by hour_of_day

),

final as (

    select
        per_hour.hour_of_day,
        last_day.total_compounded_return,
        per_hour.trading_days,
        per_hour.average_daily_return,
        per_hour.daily_return_standard_deviation,
        per_hour.first_trade_date,
        per_hour.last_trade_date
    from per_hour
    inner join last_day
        on per_hour.hour_of_day = last_day.hour_of_day

)

select * from final
