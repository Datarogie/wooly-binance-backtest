with equity_curve as (

    select * from {{ ref('int_bitcoin__strategy_equity_curve') }}

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
        -- Drawdown measures against the running peak, not the prior value, so a
        -- partial recovery before a deeper fall is not mistaken for safety.
        -- Rounded to 15 decimals so the division scale does not leak out.
        round(cumulative_growth_factor / running_peak - 1, 15) as drawdown
    from with_running_peak

),

final as (

    select
        hour_of_day,
        cast(count(*) as int) as trading_days,
        min(drawdown) as maximum_drawdown,
        -- Worst loss below the starting unit of capital, floored at zero: an hour
        -- that was never underwater shows no loss rather than a negative number.
        greatest(0, -min(cumulative_return)) as maximum_loss_from_start,
        min(daily_return) as worst_single_day_return,
        min(trade_date) as first_trade_date,
        max(trade_date) as last_trade_date
    from with_drawdown
    group by hour_of_day

)

select * from final
