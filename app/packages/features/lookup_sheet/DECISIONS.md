# Решения: features/lookup_sheet

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../../docs/tasks/AGENT.md#принятые-решения).

- Модалка (T-046): `showLookupSheet(context, query, {onOpenSettings})` из `package:lookup_sheet/lookup_sheet.dart`; про go_router не знает — вызывающий передаёт `() => context.go(Routes.settings)`. `lookupSelectionProvider` собирается в фиче из портов `features_common`, в bootstrap подключаются только порты. Переключатель EN→RU/EN→EN в шапке — только для открытого окна, в профиль не пишется. Любой `LookupUnanswered` с `!isNotFound` — «нет словаря» с кнопкой в настройки. Тексты без l10n.
- Уровень в модалке (T-051): `LookupOutcome.wordLevel` (`WordLevel`, обязательное поле обоих подтипов) — уровень из текущего `LevelDictionary` по тому же ключу, что `Term.normalized`, без `pos`; `outcome.level` = `wordLevel.level`, на запомненный `Term.level` не откатывается. Бейдж — `LevelBadge`: `C1`, оценка по частоте — `≈B2`, `unknown` — ничего.
