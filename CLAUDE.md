# My reader

A mobile reader for learning English: tap-to-translate, query history with context, and a pre-reading "warm-up" for the next chunk of text. Flutter app (`app/`) plus a thin service (`service/`). The code does not exist yet; work goes through the tasks in `docs/tasks/`.

Docs are in Russian. Read only what your task needs.

## Docs

@docs/Requirements.md describes the requirements of the application.

@docs/Architecture.md describes the top-level architecture: what runs in the app and what runs on the service.

| File | What it covers |
|---|---|
| docs/Architecture-app.md | App architecture: packages in `app/`, layers, storage |
| docs/Architecture-service.md | Service architecture: batch markup, data packages |
| docs/Data-sources.md | Dictionaries, CEFR levels, phrasal verbs and idioms, licenses |
| docs/MVP-plan.md | MVP scope, milestones, Gantt chart |
| docs/tasks/README.md | How agents and the orchestrator work, accepted tech decisions, task waves |
| docs/tasks/T-*.md | One task each: status, dependencies, allowed paths ("Где"), what to read, done criteria |
| docs/tasks/U-*.md | Human checkpoints on the Mac |
| docs/Liseur-fork-plan.md | Assessment of forking chmouel/liseur (Android, Kotlin) as an alternative base |
| docs/References.md | Similar products, for ideas only |

## Working on a task

- Read the task file and the sections it lists under "Прочитать".
- Change only the paths listed under "Где". If you need more, stop and report.
- Tests are required. Before handing off, run `app/scripts/check.sh` (app) or `uv run pytest` in `service/`.
- A task is done only when `dart format`, `dart analyze --fatal-infos` and the tests are all green. Don't silence lints with `// ignore:` or by editing `app/analysis_options.yaml`. If a rule is wrong for the project, stop and report.
- Hooks in `.claude/settings.json` enforce this. After every `.dart` edit they format the file and analyze it. Before you stop, they run `app/scripts/check.sh` if any `.dart` file under `app/` changed. Fix what they report, don't work around it.
- Don't re-decide what `docs/tasks/README.md` already fixes under "Принятые решения".
- `app/README.md` and `service/README.md` (once they exist) describe how to build and run each part.
