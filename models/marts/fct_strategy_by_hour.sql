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

with_running_peak as (
    select
        hour_of_day,
        trade_date,
        daily_return,
        cumulative_growth_factor,
        cumulative_return,
        max(cumulative_growth_factor) over (
            partition by hour_of_day
            order by trade_date
            rows between unbounded preceding and current row
        ) as running_peak

    from equity_curve
),

with_drawdown as (
    select
        hour_of_day,
        trade_date,
        daily_return,
        cumulative_return,
        round(cumulative_growth_factor / running_peak - 1, 15) as drawdown

    from with_running_peak
),

per_hour as (
    select
        hour_of_day,
        count(*)::int as trading_days,
        avg(daily_return) as average_daily_return,
        stddev_samp(daily_return) as daily_return_standard_deviation,
        min(drawdown) as maximum_drawdown,
        greatest(0, -min(cumulative_return)) as maximum_loss_from_start,
        min(daily_return) as worst_single_day_return,
        min(trade_date) as first_trade_date,
        max(trade_date) as last_trade_date

    from with_drawdown
    group by hour_of_day
),

final as (
    select
        per_hour.hour_of_day,
        last_day.total_compounded_return,
        per_hour.average_daily_return,
        per_hour.daily_return_standard_deviation,
        per_hour.maximum_drawdown,
        per_hour.maximum_loss_from_start,
        per_hour.worst_single_day_return,
        per_hour.trading_days,
        per_hour.first_trade_date,
        per_hour.last_trade_date

    from per_hour
    inner join last_day
        on per_hour.hour_of_day = last_day.hour_of_day
)

select * from final
