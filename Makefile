.PHONY: up down load lint format

up:
	docker compose up -d --wait

down:
	docker compose down

load:
	bash scripts/load_data.sh

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
