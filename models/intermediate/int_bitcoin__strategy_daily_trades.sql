with hourly_bars as (
    select * from {{ ref('int_bitcoin__hourly_bars') }}
),

tradeable as (
    select
        pk_hourly_bar_key,
        trade_date,
        hour_of_day,
        bar_open as entry_price,
        bar_close as exit_price,
        round(
            (bar_close / bar_open)
            * (1 - {{ var('fee_basis_points') }} / 10000.0),
            {{ var('report_decimals') }}
        ) as growth_factor

    from hourly_bars
    where has_open_boundary
        and has_close_boundary
        -- guarantee exit_price / entry_price can never divide by zero
        and bar_open > 0
),

final as (
    select
        pk_hourly_bar_key,
        trade_date,
        hour_of_day,
        entry_price,
        exit_price,
        growth_factor,
        growth_factor - 1 as daily_return

    from tradeable
)

select * from final
