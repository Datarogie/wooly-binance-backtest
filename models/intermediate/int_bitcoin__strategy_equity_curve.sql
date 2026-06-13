with daily_trades as (
    select * from {{ ref('int_bitcoin__strategy_daily_trades') }}
),

compounded as (
    select
        pk_hourly_bar_key,
        trade_date,
        hour_of_day,
        growth_factor,
        daily_return,
        round(exp(sum(ln(growth_factor)) over (
            partition by hour_of_day
            order by trade_date
            rows between unbounded preceding and current row
        )), 15) as cumulative_growth_factor

    from daily_trades
),

final as (
    select
        pk_hourly_bar_key,
        trade_date,
        hour_of_day,
        growth_factor,
        daily_return,
        cumulative_growth_factor,
        cumulative_growth_factor - 1 as cumulative_return

    from compounded
)

select * from final
