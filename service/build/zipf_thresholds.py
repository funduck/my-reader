"""Пороги Zipf -> CEFR для слов вне списков CEFR-J и Octanove.

``ZIPF_THRESHOLDS`` — конфиг: нижние границы Zipf для уровней A1…C1, строго по убыванию.
``Zipf >= t`` -> этот уровень (или проще), ниже последнего порога -> C2. Значения подобраны
командой ``uv run python -m build.pack_en_levels fit`` (см. README и docs/Data-sources.md,
раздел 4); при смене данных пересчитайте и обновите константу и документацию.

Модуль чистый: без чтения файлов и wordfreq, на вход — пары ``(zipf, индекс уровня)``.
"""

from __future__ import annotations

import random
from collections import defaultdict
from collections.abc import Sequence
from dataclasses import dataclass

from build.schema import CEFR_VALUES

#: Уровни, для которых задан нижний порог. Всё ниже последнего порога — C2.
THRESHOLD_LEVELS = CEFR_VALUES[:-1]

#: Нижние границы Zipf для a1, a2, b1, b2, c1 (подобраны на обучающей выборке, seed 35).
ZIPF_THRESHOLDS: tuple[float, ...] = (5.17, 4.35, 3.89, 3.42, 2.62)

#: Зерно разбиения на обучающую и отложенную выборки.
SPLIT_SEED = 35
#: Доля отложенной выборки.
HELD_OUT_FRACTION = 0.2


def check_thresholds(thresholds: Sequence[float]) -> None:
    """Бросает ``ValueError``, если порогов не 5 или они не строго убывают."""
    if len(thresholds) != len(THRESHOLD_LEVELS):
        raise ValueError(f"нужно {len(THRESHOLD_LEVELS)} порогов, получено {len(thresholds)}")
    for hi, lo in zip(thresholds, thresholds[1:], strict=False):
        if not hi > lo:
            raise ValueError(f"пороги должны строго убывать: {tuple(thresholds)}")


def level_index(zipf: float, thresholds: Sequence[float] = ZIPF_THRESHOLDS) -> int:
    """Индекс уровня в ``CEFR_VALUES``: первый порог, который ``zipf`` достигает (``>=``)."""
    for i, t in enumerate(thresholds):
        if zipf >= t:
            return i
    return len(thresholds)


def estimate_cefr(zipf: float | None, thresholds: Sequence[float] = ZIPF_THRESHOLDS) -> str | None:
    """Оценка уровня по Zipf; ``None``, если Zipf неизвестен."""
    if zipf is None:
        return None
    return CEFR_VALUES[level_index(zipf, thresholds)]


def fit_thresholds(
    samples: Sequence[tuple[float, int]], balanced: bool = True
) -> tuple[float, ...]:
    """Подбирает пороги, минимизируя сумму ``|предсказанный - настоящий|`` по уровням.

    ``balanced`` — вес каждого слова обратно пропорционален размеру его уровня: иначе
    самый большой уровень (B2) «съедает» крайние, и C2 почти не выдаётся. Для разминки
    важно различать трудные слова, поэтому по умолчанию включено.

    Точное динамическое программирование по отсортированным различным значениям Zipf:
    порядковая ошибка (A1 вместо C2 хуже, чем B2 вместо C2) устойчивее к выбросам,
    чем доля точных попаданий. Результат детерминирован. Порог — наименьший Zipf
    группы, которая получает этот уровень.
    """
    n_levels = len(CEFR_VALUES)
    by_zipf: dict[float, list[int]] = defaultdict(lambda: [0] * n_levels)
    for z, lvl in samples:
        by_zipf[z][lvl] += 1
    totals = [sum(c[lvl] for c in by_zipf.values()) for lvl in range(n_levels)]
    weight = [1.0 / t if balanced and t else 1.0 for t in totals]
    zs = sorted(by_zipf, reverse=True)  # от частых к редким
    m = len(zs)
    if m < n_levels:
        raise ValueError("слишком мало различных значений Zipf для подбора")

    # cost[l][j] — ошибка, если первые j групп получат уровень l
    cost = [[0.0] * (m + 1) for _ in range(n_levels)]
    for lvl in range(n_levels):
        for j, z in enumerate(zs):
            c = sum(weight[true] * cnt * abs(lvl - true) for true, cnt in enumerate(by_zipf[z]))
            cost[lvl][j + 1] = cost[lvl][j] + c

    inf = float("inf")
    # best[l][j]: минимум ошибки для первых j групп, уровни не больше l, неубывающие
    best = [[inf] * (m + 1) for _ in range(n_levels)]
    cut = [[0] * (m + 1) for _ in range(n_levels)]
    for j in range(m + 1):
        best[0][j] = cost[0][j]
    for lvl in range(1, n_levels):
        for j in range(m + 1):
            # группы [i, j) получают уровень lvl; сдвиг i от 0 до j
            # (при равенстве берём больший i: уровень lvl занимает меньше групп,
            # результат детерминирован)
            bi, bv = 0, inf
            for i in range(j + 1):
                v = best[lvl - 1][i] + cost[lvl][j] - cost[lvl][i]
                if v <= bv:
                    bi, bv = i, v
            best[lvl][j], cut[lvl][j] = bv, bi

    # восстановление границ: starts[l] — индекс первой группы уровня l
    bounds: list[int] = []
    j = m
    for lvl in range(n_levels - 1, 0, -1):
        i = cut[lvl][j]
        bounds.append(i)
        j = i
    bounds.reverse()  # bounds[k] — где кончается уровень k и начинается k+1
    thresholds: list[float] = []
    for k, b in enumerate(bounds):
        # порог уровня k — наименьший Zipf группы, которой он присвоен; если уровень пуст,
        # порог совпадает с предыдущим и ниже сдвигается на минимальный шаг
        prev_end = bounds[k - 1] if k else 0
        if b > prev_end:
            thresholds.append(zs[b - 1])
        else:
            thresholds.append(thresholds[-1] - 0.01 if thresholds else zs[0] + 0.01)
    return tuple(round(t, 2) for t in thresholds)


def split_samples(
    items: Sequence[tuple[str, float, int]],
    seed: int = SPLIT_SEED,
    held_out_fraction: float = HELD_OUT_FRACTION,
) -> tuple[list[tuple[str, float, int]], list[tuple[str, float, int]]]:
    """Делит ``(лемма, zipf, уровень)`` на обучающую и отложенную части (по seed)."""
    ordered = sorted(items)
    random.Random(seed).shuffle(ordered)
    n_test = round(len(ordered) * held_out_fraction)
    return ordered[n_test:], ordered[:n_test]


@dataclass(frozen=True)
class Accuracy:
    n: int
    exact: float
    within_one: float
    mean_abs_error: float


def evaluate(
    samples: Sequence[tuple[float, int]], thresholds: Sequence[float] = ZIPF_THRESHOLDS
) -> Accuracy:
    """Точность оценки: доля точных попаданий, попаданий в ±1 уровень, средняя ошибка."""
    if not samples:
        return Accuracy(0, 0.0, 0.0, 0.0)
    diffs = [abs(level_index(z, thresholds) - lvl) for z, lvl in samples]
    n = len(diffs)
    return Accuracy(
        n,
        sum(d == 0 for d in diffs) / n,
        sum(d <= 1 for d in diffs) / n,
        sum(diffs) / n,
    )
