.PHONY: up down reset logs psql dbt-build dbt-test dbt-docs

## Start Postgres + pgAdmin (seeds the OLTP source schema on first boot).
up:
	docker compose up -d postgres pgadmin

## Stop containers, keep data volumes.
down:
	docker compose down

## Stop containers and wipe all data (re-seeds from scratch on next `make up`).
reset:
	docker compose down -v

logs:
	docker compose logs -f postgres

## Open a psql shell inside the warehouse database.
psql:
	docker compose exec postgres psql -U $${POSTGRES_USER:-warehouse} -d $${POSTGRES_DB:-warehouse}

## Full dbt lifecycle in dependency order: seeds, SCD2 snapshot, models, tests.
dbt-build:
	docker compose run --rm dbt build

dbt-test:
	docker compose run --rm dbt test

## Generate + serve dbt docs (lineage graph, column docs) at http://localhost:8080
dbt-docs:
	docker compose run --rm dbt docs generate
	docker compose run --rm -p 8080:8080 dbt docs serve --host 0.0.0.0
