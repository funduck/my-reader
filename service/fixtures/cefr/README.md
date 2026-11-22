# Образцы CEFR-списков для тестов en-levels

`cefrj-sample.csv` и `octanove-sample.csv` — выборки строк (без правок, только отбор) из
https://github.com/openlanguageprofiles/olp-en-cefrj :

- `cefrj-vocabulary-profile-1.5.csv` (CEFR-J Wordlist, A1–B2);
- `octanove-vocabulary-profile-c1c2-1.0.csv` (Octanove Vocabulary Profile, C1–C2).

Лицензия оригиналов: CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/);
авторы: Tono Yukio и коллеги (CEFR-J), Octanove Labs. Выборки распространяются на тех же условиях.

В выборку включены «трудные» строки: варианты написания через `/`, поле в кавычках с запятой,
пустая часть речи, опечатка `vern`, хвостовой пробел в заголовке, `modal auxiliary`,
`infinitive-to`, слова из обоих списков с разным уровнем (`curriculum`, `circuit`, `rich`).

Полные CSV в git не кладём: `uv run python -m build.pack_en_levels fetch` скачивает их в `data/cefr/`.
