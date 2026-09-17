-- Simulated OLTP "source system" for a small e-commerce business.
-- This is intentionally normalized (3NF-ish) so the curriculum can walk
-- through denormalizing it into a dimensional model later.

create schema if not exists source;

create table source.customers (
    customer_id     serial primary key,
    first_name      text not null,
    last_name       text not null,
    email           text not null unique,
    city            text,
    country         text,
    segment         text not null default 'consumer' check (segment in ('consumer', 'small_business', 'enterprise')),
    created_at      timestamp not null default now(),
    updated_at      timestamp not null default now()
);

create table source.products (
    product_id      serial primary key,
    sku             text not null unique,
    product_name    text not null,
    category        text not null,
    subcategory     text,
    unit_cost       numeric(10, 2) not null check (unit_cost >= 0),
    unit_price      numeric(10, 2) not null check (unit_price >= 0),
    is_active       boolean not null default true,
    created_at      timestamp not null default now(),
    updated_at      timestamp not null default now()
);

create table source.employees (
    employee_id     serial primary key,
    first_name      text not null,
    last_name       text not null,
    role            text not null,
    region          text not null
);

create table source.orders (
    order_id        serial primary key,
    customer_id     integer not null references source.customers (customer_id),
    employee_id     integer references source.employees (employee_id),
    order_status    text not null check (order_status in ('pending', 'shipped', 'delivered', 'cancelled', 'returned')),
    order_date      date not null,
    ship_date       date,
    channel         text not null default 'web' check (channel in ('web', 'mobile', 'store', 'phone')),
    created_at      timestamp not null default now(),
    updated_at      timestamp not null default now()
);

create table source.order_items (
    order_item_id   serial primary key,
    order_id        integer not null references source.orders (order_id),
    product_id      integer not null references source.products (product_id),
    quantity        integer not null check (quantity > 0),
    unit_price      numeric(10, 2) not null check (unit_price >= 0),
    discount_pct    numeric(5, 2) not null default 0 check (discount_pct between 0 and 100)
);

create table source.payments (
    payment_id      serial primary key,
    order_id        integer not null references source.orders (order_id),
    payment_method  text not null check (payment_method in ('credit_card', 'paypal', 'gift_card', 'bank_transfer')),
    amount          numeric(10, 2) not null check (amount >= 0),
    paid_at         timestamp not null
);

-- History table used in the Slowly Changing Dimension chapter: every time a
-- customer's address/segment changes, the app writes a row here instead of
-- (or in addition to) updating `customers` in place.
create table source.customer_address_history (
    history_id      serial primary key,
    customer_id     integer not null references source.customers (customer_id),
    city            text,
    country         text,
    segment         text not null,
    valid_from      timestamp not null default now(),
    valid_to        timestamp
);

create index idx_orders_customer_id on source.orders (customer_id);
create index idx_orders_order_date on source.orders (order_date);
create index idx_order_items_order_id on source.order_items (order_id);
create index idx_order_items_product_id on source.order_items (product_id);
create index idx_payments_order_id on source.payments (order_id);
