"""Тесты порогов Zipf -> CEFR: границы, порядок, детерминизм подбора на фикстурах."""

from __future__ import annotations

from pathlib import Path

import pytest

from build.pack_en_levels import fit_report, fit_samples, merge_cefr, parse_cefr_csv
from build.schema import CEFR_VALUES
from build.zipf_thresholds import (
    ZIPF_THRESHOLDS,
    check_thresholds,
    estimate_cefr,
    evaluate,
    fit_thresholds,
    level_index,
    split_samples,
)

CEFR_DIR = Path(__file__).resolve().parent.parent / "fixtures" / "cefr"


def test_thresholds_strictly_ordered() -> None:
    check_thresholds(ZIPF_THRESHOLDS)
    assert len(ZIPF_THRESHOLDS) == 5
    assert all(a > b for a, b in zip(ZIPF_THRESHOLDS, ZIPF_THRESHOLDS[1:], strict=False))


def test_check_rejects_bad_thresholds() -> None:
    with pytest.raises(ValueError, match="нужно"):
        check_thresholds((5.0, 4.0))
    with pytest.raises(ValueError, match="строго"):
        check_thresholds((5.0, 4.0, 4.0, 3.0, 2.0))
    with pytest.raises(ValueError, match="строго"):
        check_thresholds((5.0, 4.0, 4.5, 3.0, 2.0))


def test_boundary_values() -> None:
    t = (5.0, 4.0, 3.5, 3.0, 2.0)
    assert estimate_cefr(5.0, t) == "a1"  # порог включается
    assert estimate_cefr(4.99, t) == "a2"
    assert estimate_cefr(4.0, t) == "a2"
    assert estimate_cefr(3.99, t) == "b1"
    assert estimate_cefr(3.5, t) == "b1"
    assert estimate_cefr(3.49, t) == "b2"
    assert estimate_cefr(3.0, t) == "b2"
    assert estimate_cefr(2.99, t) == "c1"
    assert estimate_cefr(2.0, t) == "c1"
    assert estimate_cefr(1.99, t) == "c2"
    assert estimate_cefr(0.01, t) == "c2"
    assert estimate_cefr(7.8, t) == "a1"
    assert estimate_cefr(None, t) is None


def test_config_thresholds_monotone_in_zipf() -> None:
    levels = [level_index(z / 100) for z in range(900, 0, -1)]
    assert levels == sorted(levels)
    assert levels[0] == 0
    assert levels[-1] == len(CEFR_VALUES) - 1


def test_fit_recovers_clean_separation() -> None:
    # уровни идеально разделены по Zipf: 6 групп по 5 слов
    samples = [(7.0 - lvl * 1.0 - k * 0.1, lvl) for lvl in range(6) for k in range(5)]
    fitted = fit_thresholds(samples)
    check_thresholds(fitted)
    assert evaluate(samples, fitted).exact == 1.0


def test_fit_is_deterministic_on_fixtures() -> None:
    merged = merge_cefr(
        parse_cefr_csv(CEFR_DIR / "cefrj-sample.csv"),
        parse_cefr_csv(CEFR_DIR / "octanove-sample.csv"),
    )
    samples = fit_samples(merged)
    assert len(samples) > 30
    pairs = [(z, i) for _, z, i in samples]
    first = fit_thresholds(pairs)
    assert fit_thresholds(list(reversed(pairs))) == first
    assert fit_thresholds(pairs) == first
    check_thresholds(first)
    assert fit_report(merged) == fit_report(merged)


def test_fit_samples_per_lemma_min_and_single_words() -> None:
    merged = {
        ("rich", "adj"): "a1",
        ("rich", "noun"): "c1",
        ("turn to", "verb"): "c1",
        ("mother-in-law", "noun"): "b1",
        ("dog", "noun"): "a1",
    }
    samples = fit_samples(merged, zipf=lambda w: None if w == "dog" else 4.0)
    assert samples == [("rich", 4.0, 0)]


def test_split_is_stable_and_disjoint() -> None:
    items = [(f"w{i}", 3.0 + i / 100, i % 6) for i in range(100)]
    train, test = split_samples(items)
    assert (train, test) == split_samples(list(reversed(items)))
    assert len(test) == 20
    assert not {w for w, _, _ in train} & {w for w, _, _ in test}
    assert split_samples(items, seed=1) != (train, test)


def test_evaluate() -> None:
    t = (5.0, 4.0, 3.0, 2.0, 1.0)
    acc = evaluate([(5.5, 0), (4.5, 0), (0.5, 0), (0.5, 5)], t)
    assert acc.n == 4
    assert acc.exact == 0.5
    assert acc.within_one == 0.75
    assert acc.mean_abs_error == (0 + 1 + 5 + 0) / 4
