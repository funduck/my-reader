# service

Сборка и раздача пакетов данных для приложения. Архитектура и схемы пакетов — в [../docs/Architecture-service.md](../docs/Architecture-service.md), раздел «Схемы пакетов».

## Требования

- [uv](https://docs.astral.sh/uv/). Python 3.12 uv подтянет сам (версия записана в `.python-version`).

## Установка и проверки

```sh
cd service
uv sync                      # создаёт .venv и ставит pytest, ruff
uv run pytest                # тесты
uv run ruff check            # линтер
uv run ruff format --check   # формат (без --check — переформатировать)
```

## Структура

```
build/      сборка пакетов: schema.py (DDL и нормализация), packdb.py (запись SQLite и manifest), fixtures.py
serve/      HTTP-раздача (появится в T-036)
data/       дампы и собранные пакеты, не в git
fixtures/   мини-пакеты для тестов приложения: manifest.json + packs/*.sqlite
tests/
```

## Тестовые мини-пакеты

`fixtures/` собирается из данных, написанных вручную в `build/fixtures.py` (20–50 слов на пакет). После правки данных или схемы пересоберите и закоммитьте результат:

```sh
uv run python -m build.fixtures
```

Тесты проверяют, что файлы в `fixtures/` соответствуют схеме из документации, что `manifest.json` совпадает с файлами (размер, sha256) и что скрипт воспроизводит содержимое.

Папку `fixtures/` можно раздавать как корень сервиса (`python -m http.server -d fixtures 8080`): в ней есть `manifest.json` и `packs/`.
