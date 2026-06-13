with strategy as (
    select * from {{ ref('fct_strategy_by_hour') }}
),

best_return as (
    select
        'Q1: biggest compounded return' as question,
        hour_of_day,
        total_compounded_return as headline_metric,
        trading_days,
        first_trade_date,
        last_trade_date

    from strategy
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

    from strategy
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
