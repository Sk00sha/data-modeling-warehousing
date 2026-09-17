-- Deterministic-ish sample data so every learner sees roughly the same
-- warehouse. Volume is intentionally small (fast `docker compose up`) but
-- large enough to make grain/aggregation exercises meaningful.

select setseed(0.42);

-- 200 customers
insert into source.customers (first_name, last_name, email, city, country, segment, created_at, updated_at)
select
    'First' || i,
    'Last' || i,
    'customer' || i || '@example.com',
    (array['Prague','Berlin','Vienna','Warsaw','Amsterdam','Paris','Madrid','Rome'])[(1 + floor(random() * 8))::int],
    (array['Czechia','Germany','Austria','Poland','Netherlands','France','Spain','Italy'])[(1 + floor(random() * 8))::int],
    (array['consumer','consumer','consumer','small_business','enterprise'])[(1 + floor(random() * 5))::int],
    now() - (random() * 700 || ' days')::interval,
    now() - (random() * 30 || ' days')::interval
from generate_series(1, 200) as i;

-- A handful of address / segment changes per customer, for the SCD chapter.
insert into source.customer_address_history (customer_id, city, country, segment, valid_from, valid_to)
select
    c.customer_id,
    c.city,
    c.country,
    c.segment,
    c.created_at,
    c.created_at + (random() * 200 || ' days')::interval
from source.customers c
where c.customer_id % 3 = 0;

insert into source.customer_address_history (customer_id, city, country, segment, valid_from, valid_to)
select
    c.customer_id,
    (array['Prague','Berlin','Vienna','Warsaw','Amsterdam','Paris','Madrid','Rome'])[(1 + floor(random() * 8))::int],
    c.country,
    c.segment,
    c.created_at + (random() * 200 || ' days')::interval,
    null
from source.customers c
where c.customer_id % 3 = 0;

-- 12 employees across 4 regions
insert into source.employees (first_name, last_name, role, region)
select
    'Emp' || i,
    'Person' || i,
    (array['sales_rep','account_manager'])[(1 + floor(random() * 2))::int],
    (array['EMEA','AMER','APAC','LATAM'])[(1 + floor(random() * 4))::int]
from generate_series(1, 12) as i;

-- 60 products across a handful of categories
insert into source.products (sku, product_name, category, subcategory, unit_cost, unit_price, is_active, created_at, updated_at)
select
    'SKU-' || lpad(i::text, 5, '0'),
    'Product ' || i,
    (array['Electronics','Home & Kitchen','Office','Outdoors','Apparel'])[(1 + floor(random() * 5))::int],
    (array['Accessories','Core','Premium'])[(1 + floor(random() * 3))::int],
    round((5 + random() * 95)::numeric, 2),
    0, -- filled below with a markup over cost
    (random() > 0.05),
    now() - (random() * 700 || ' days')::interval,
    now() - (random() * 30 || ' days')::interval
from generate_series(1, 60) as i;

update source.products
set unit_price = round((unit_cost * (1.3 + random() * 0.9))::numeric, 2);

-- 3,000 orders spread over the last two years
insert into source.orders (customer_id, employee_id, order_status, order_date, ship_date, channel, created_at, updated_at)
select
    1 + floor(random() * 200)::int,
    case when random() < 0.9 then 1 + floor(random() * 12)::int else null end,
    (array['delivered','delivered','delivered','shipped','pending','cancelled','returned'])[(1 + floor(random() * 7))::int],
    d.order_date,
    d.order_date + (1 + floor(random() * 5) || ' days')::interval,
    (array['web','web','mobile','store','phone'])[(1 + floor(random() * 5))::int],
    d.order_date::timestamp,
    d.order_date::timestamp + (floor(random() * 5) || ' days')::interval
from (
    select (current_date - (floor(random() * 730))::int) as order_date
    from generate_series(1, 3000)
) d;

-- 1-3 line items per order (~6,000 rows)
-- Each line item's product is picked via a LATERAL "order by random() limit 1"
-- subquery, evaluated once per row, rather than a join predicate on
-- random() (which would be re-evaluated per candidate row and silently
-- drop or duplicate order items).
insert into source.order_items (order_id, product_id, quantity, unit_price, discount_pct)
select
    o.order_id,
    p.product_id,
    1 + floor(random() * 4)::int,
    p.unit_price,
    round((array[0, 0, 0, 5, 10, 15, 20])[(1 + floor(random() * 7))::int]::numeric, 2)
from source.orders o
cross join lateral generate_series(1, 1 + floor(random() * 3)::int) as item_no
cross join lateral (
    select product_id, unit_price
    from source.products
    order by random()
    limit 1
) p;

-- One payment per non-cancelled order
insert into source.payments (order_id, payment_method, amount, paid_at)
select
    o.order_id,
    (array['credit_card','credit_card','paypal','gift_card','bank_transfer'])[(1 + floor(random() * 5))::int],
    coalesce((
        select round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0))::numeric, 2)
        from source.order_items oi
        where oi.order_id = o.order_id
    ), 0),
    o.order_date::timestamp + (floor(random() * 3) || ' days')::interval
from source.orders o
where o.order_status <> 'cancelled';
