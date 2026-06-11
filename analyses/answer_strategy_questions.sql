-- The two questions, answered. This is an ad-hoc ranking query, not a model:
-- it reads the conformed per-hour marts and reduces each to a single labeled
-- winner. Selection is intentionally lossy and lives here, never in a core
-- model, so the marts stay reusable for any other ranking.
--
-- Q1: which hour of the day had the biggest compounded return.
-- Q2: which hour of the day had the lowest maximum losses. "Maximum losses" is
--     read as the maximum drawdown (deepest peak-to-trough on the reinvested
--     equity curve); the hour whose worst drawdown is shallowest wins. The
--     worst loss below starting capital is carried alongside for context.

with performance as (

    select * from {{ ref('fct_strategy_performance_by_hour') }}

),

drawdown as (

    select * from {{ ref('fct_strategy_drawdown_by_hour') }}

),

best_return as (

    select
        'Q1: biggest compounded return' as question,
        hour_of_day,
        total_compounded_return as headline_metric,
        trading_days,
        first_trade_date,
        last_trade_date
    from performance
    order by total_compounded_return desc
    limit 1

),

lowest_max_loss as (

    select
        'Q2: lowest maximum losses (shallowest max drawdown)' as question,
        hour_of_day,
        maximum_drawdown as headline_metric,
        trading_days,
        first_trade_date,
        last_trade_date
    from drawdown
    order by maximum_drawdown desc
    limit 1

),

final as (

    select
        question,
        hour_of_day,
        headline_metric,
        trading_days,
        first_trade_date,
        last_trade_date
    from best_return

    union all

    select
        question,
        hour_of_day,
        headline_metric,
        trading_days,
        first_trade_date,
        last_trade_date
    from lowest_max_loss

)

select * from final
