# My reader

A mobile reader for learning English: tap-to-translate, query history with context, and a pre-reading "warm-up" for the next chunk of text. Flutter app (`app/`) plus a thin service (`service/`). The code does not exist yet; work goes through the tasks in `docs/tasks/`.

Docs are in Russian. Read only what your task needs.

## Docs

| File | What it covers |
|---|---|
| docs/Requirements.md | Requirements of the application |
| docs/Architecture.md | Top-level architecture: what runs in the app and what runs on the service |
| docs/Architecture-app.md | App architecture: packages in `app/`, layers, storage |
| docs/Architecture-service.md | Service architecture: batch markup, data packages |
| docs/Data-sources.md | Dictionaries, CEFR levels, phrasal verbs and idioms, licenses |
| docs/MVP-plan.md | MVP scope, milestones, Gantt chart |
| docs/tasks/AGENT.md | Rules for a task agent, the sandbox, general tech decisions |
| docs/tasks/README.md | How the orchestrator works, checkpoints, task waves, all tasks |
| app/**/DECISIONS.md | Per-package contracts and conventions from finished tasks |
| docs/tasks/T-*.md | One task each: status, dependencies, allowed paths ("Где"), what to read, done criteria |
| docs/tasks/U-*.md | Human checkpoints on the Mac |
| docs/backlog/B-*.md | Open questions and research tasks, not scheduled yet |
| docs/Liseur-fork-plan.md | Assessment of forking chmouel/liseur (Android, Kotlin) as an alternative base |
| docs/References.md | Similar products, for ideas only |

## Working on a task

- Read `docs/tasks/AGENT.md`, the task file and the sections it lists under "Прочитать".
- Package contracts and conventions are in `app/packages/<pkg>/DECISIONS.md` (`app/app/DECISIONS.md` for wiring). Read the ones for the packages you change or call, not all of them.
- Change only the paths listed under "Где". If you need more, stop and report.
- Tests are required. While working, run `app/scripts/check.sh --package <dir>` for your package. Before handing off, run the full `app/scripts/check.sh` (app) or `uv run pytest` in `service/`.
- A task is done only when `dart format`, `dart analyze --fatal-infos` and the tests are all green. Don't silence lints with `// ignore:` or by editing `app/analysis_options.yaml`. If a rule is wrong for the project, stop and report.
- Don't re-decide what `docs/tasks/AGENT.md` already fixes under "Принятые решения".
- `app/README.md` and `service/README.md` (once they exist) describe how to build and run each part.
