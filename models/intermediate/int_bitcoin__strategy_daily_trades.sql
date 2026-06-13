with hourly_bars as (
    select * from {{ ref('int_bitcoin__hourly_bars') }}
),

carried as (
    select
        pk_hourly_bar_key,
        trade_date,
        hour_of_day,
        hour_start_at,
        first_observed_second_at,
        bar_open,
        bar_close,
        lag(bar_close) over (order by hour_start_at) as prior_bar_close,
        lag(last_observed_second_at) over (order by hour_start_at)
            as prior_last_observed_second_at

    from hourly_bars
),

priced as (
    select
        pk_hourly_bar_key,
        trade_date,
        hour_of_day,
        bar_close as exit_price,
        case
            when first_observed_second_at = hour_start_at then bar_open
            else prior_bar_close
        end as entry_price,
        case
            when first_observed_second_at = hour_start_at then 0
            else extract(epoch from (hour_start_at - prior_last_observed_second_at))::int
        end as carried_price_staleness_seconds

    from carried
),

returns as (
    select
        pk_hourly_bar_key,
        trade_date,
        hour_of_day,
        entry_price,
        exit_price,
        carried_price_staleness_seconds,
        round(
            (exit_price / entry_price)
            * (1 - {{ var('fee_basis_points') }} / 10000.0), 15
        ) as growth_factor

    from priced
    where entry_price is not null and entry_price > 0
),

final as (
    select
        pk_hourly_bar_key,
        trade_date,
        hour_of_day,
        entry_price,
        exit_price,
        carried_price_staleness_seconds,
        growth_factor,
        growth_factor - 1 as daily_return

    from returns
)

select * from final
