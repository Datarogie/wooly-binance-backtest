-- Fail if a source value carries more decimals than the staging numeric scale (8)
-- keeps, which would silently drop precision on cast.
select open_time
from {{ source('binance', 'bitcoin_prices') }}
where scale(open) > 8
    or scale(high) > 8
    or scale(low) > 8
    or scale(close) > 8
    or scale(volume) > 8
