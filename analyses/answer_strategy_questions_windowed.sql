-- Windowed strategy answers: same daily growth factors as fct_strategy_by_hour,
-- recompounded over an editable date window (the winning hour can move with the start
-- date). Edit the where filter below, compile, then run the compiled SQL.

with daily as (
    select
        hour_of_day,
        trade_date,
        growth_factor,
        daily_return

    from {{ ref('int_bitcoin__strategy_daily_trades') }}
    -- backtest window. defaults to all history (data starts 2021-02-23).
    -- raise this to backtest from a later start, e.g. trade_date >= '2023-01-01'.
    where trade_date >= '2021-01-01'
),

curve as (
    select
        hour_of_day,
        trade_date,
        daily_return,
        exp(sum(ln(growth_factor)) over (
            partition by hour_of_day
            order by trade_date
            rows between unbounded preceding and current row
        )) as cumulative_growth_factor

    from daily
),

with_drawdown as (
    select
        hour_of_day,
        trade_date,
        daily_return,
        cumulative_growth_factor,
        cumulative_growth_factor / max(cumulative_growth_factor) over (
            partition by hour_of_day
            order by trade_date
            rows between unbounded preceding and current row
        ) - 1 as drawdown

    from curve
),

by_hour as (
    select
        hour_of_day,
        count(*)::int as trading_days,
        (array_agg(cumulative_growth_factor order by trade_date desc))[1] - 1 as total_compounded_return,
        min(drawdown) as maximum_drawdown,
        min(daily_return) as worst_single_day_return,
        min(trade_date) as first_trade_date,
        max(trade_date) as last_trade_date

    from with_drawdown
    group by hour_of_day
),

final as (
    select
        hour_of_day,
        round(total_compounded_return::numeric, 4) as total_compounded_return,  -- Q1: sort desc
        round(maximum_drawdown::numeric, 4) as maximum_drawdown,                -- Q2: closest to zero
        round(worst_single_day_return::numeric, 4) as worst_single_day_return,
        trading_days,
        first_trade_date,
        last_trade_date

    from by_hour
    order by total_compounded_return desc
)

select * from final
