.PHONY: up down load build answers lint format

up:
	docker compose up -d

down:
	docker compose down

load:
	bash scripts/load_data.sh

build:
	uv run dbt build

answers:
	uv run dbt build --select answer_strategy_questions

lint:
	@if [ -z "$$(find models macros analyses -name '*.sql' 2>/dev/null)" ]; then \
		echo "no sql to lint yet; skipping"; \
	else \
		uv run sqlfluff lint models macros analyses; \
	fi

format:
	@if [ -z "$$(find models macros analyses -name '*.sql' 2>/dev/null)" ]; then \
		echo "no sql to format yet; skipping"; \
	else \
		uv run sqlfluff fix models macros analyses; \
	fi
