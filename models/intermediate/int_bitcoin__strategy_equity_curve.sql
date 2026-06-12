with daily_trades as (
    select * from {{ ref('int_bitcoin__strategy_daily_trades') }}
),

final as (
    select
        trade_date,
        hour_of_day,
        growth_factor,
        daily_return,
        round(exp(sum(ln(growth_factor)) over (
            partition by hour_of_day
            order by trade_date
            rows between unbounded preceding and current row
        )), 15) as cumulative_growth_factor,
        round(exp(sum(ln(growth_factor)) over (
            partition by hour_of_day
            order by trade_date
            rows between unbounded preceding and current row
        )), 15) - 1 as cumulative_return

    from daily_trades
)

select * from final
