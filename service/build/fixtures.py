"""Тестовые мини-пакеты для тестов приложения.

Данные написаны вручную (не из дампа), поэтому мини-пакеты воспроизводимы:
``uv run python -m build.fixtures`` пересоздаёт ``fixtures/`` целиком.
Приложение может раздавать эту папку как корень сервиса (``manifest.json`` + ``packs/``).
"""

from __future__ import annotations

import sys
from pathlib import Path

from build.packdb import (
    EntryRow,
    FormRow,
    LevelRow,
    PackMeta,
    SenseRow,
    manifest_entry,
    write_en_en,
    write_en_forms,
    write_en_levels,
    write_manifest,
)

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"

VERSION = "20260101.1"
GENERATED_AT = "2026-01-01T00:00:00Z"
LICENSE = "CC BY-SA 4.0"


def _s(gloss: str, *examples: str, tags: tuple[str, ...] = (), ru: tuple[str, ...] = ()):
    return SenseRow(gloss=gloss, tags=tags, examples=examples, ru=ru)


def _e(lemma, pos, ipa, senses, ru=()):
    return EntryRow(lemma=lemma, pos=pos, ipa=ipa, senses=tuple(senses), ru=tuple(ru))


EN_EN: tuple[EntryRow, ...] = (
    _e(
        "go",
        "verb",
        "/ɡoʊ/",
        [
            _s(
                "To move or travel from one place to another.",
                "I go to work by bus.",
                ru=("идти", "ехать"),
            ),
            _s("To leave a place.", "It is late, I must go.", ru=("уходить",)),
            _s("To function correctly.", "The old clock still goes."),
        ],
        ru=("ходить",),
    ),
    _e("go", "noun", "/ɡoʊ/", [_s("An attempt or try.", "Have a go at it.", tags=("informal",))]),
    _e(
        "child",
        "noun",
        "/tʃaɪld/",
        [
            _s("A young human being.", "The child laughed.", ru=("ребёнок", "дитя")),
            _s("A son or daughter of any age.", "Their children live abroad."),
        ],
    ),
    _e(
        "good",
        "adj",
        "/ɡʊd/",
        [
            _s("Having positive qualities.", "This is a good book.", ru=("хороший",)),
            _s("Morally right.", "She is a good person."),
        ],
    ),
    _e("good", "noun", "/ɡʊd/", [_s("Something beneficial.", "It is for the common good.")]),
    _e(
        "well",
        "adv",
        "/wɛl/",
        [_s("In a good or satisfactory way.", "She sings well.", ru=("хорошо",))],
    ),
    _e(
        "well",
        "noun",
        "/wɛl/",
        [_s("A deep hole dug to reach water.", "They drew water from the well.", ru=("колодец",))],
    ),
    _e(
        "leave",
        "verb",
        "/liːv/",
        [
            _s("To go away from a place.", "Please leave the room.", ru=("покидать", "уходить")),
            _s("To cause to remain.", "He left a note on the table."),
        ],
    ),
    _e(
        "left",
        "adj",
        "/lɛft/",
        [_s("On the side of the body that is toward the west when facing north.", "Turn left.")],
        ru=("левый",),
    ),
    _e(
        "run",
        "verb",
        "/ɹʌn/",
        [_s("To move quickly on foot.", "She runs every morning.", ru=("бежать",))],
    ),
    _e("run", "noun", "/ɹʌn/", [_s("An act of running.", "He went for a run.")]),
    _e(
        "book",
        "noun",
        "/bʊk/",
        [_s("A written or printed work bound together.", "I read a book.", ru=("книга",))],
    ),
    _e("book", "verb", "/bʊk/", [_s("To reserve in advance.", "We booked a table.")]),
    _e(
        "read",
        "verb",
        "/ɹiːd/",
        [_s("To look at and understand written words.", "Read the text aloud.", ru=("читать",))],
    ),
    _e(
        "bank",
        "noun",
        "/bæŋk/",
        [
            _s("An institution that holds money.", "She works at a bank.", ru=("банк",)),
            _s("The land alongside a river.", "They sat on the river bank.", ru=("берег",)),
        ],
    ),
    _e(
        "light",
        "noun",
        "/laɪt/",
        [
            _s(
                "Electromagnetic radiation that makes things visible.",
                "Turn on the light.",
                ru=("свет",),
            )
        ],
    ),
    _e("light", "adj", "/laɪt/", [_s("Not heavy.", "A light bag.", ru=("лёгкий",))]),
    _e(
        "happy",
        "adj",
        "/ˈhæpi/",
        [_s("Feeling pleasure or contentment.", "I am happy to help.", ru=("счастливый",))],
    ),
    _e("quick", "adj", "/kwɪk/", [_s("Done with speed.", "A quick reply.", ru=("быстрый",))]),
    _e(
        "serendipity",
        "noun",
        "/ˌsɛɹənˈdɪpɪti/",
        [
            _s(
                "The occurrence of fortunate events by chance.",
                "Finding the book was pure serendipity.",
            )
        ],
    ),
    _e(
        "ubiquitous",
        "adj",
        "/juːˈbɪkwɪtəs/",
        [_s("Present everywhere.", "Smartphones are ubiquitous.", tags=("formal",))],
    ),
    _e(
        "ephemeral",
        "adj",
        "/ɪˈfɛm(ə)ɹəl/",
        [_s("Lasting for a very short time.", "Fame can be ephemeral.", tags=("literary",))],
    ),
    _e(
        "lamp",
        "noun",
        "/læmp/",
        [_s("A device that produces light.", "A desk lamp.", ru=("лампа",))],
    ),
    _e(
        "cat",
        "noun",
        "/kæt/",
        [_s("A small domesticated feline.", "The cat sat on the mat.", ru=("кошка", "кот"))],
    ),
    _e("dog", "noun", "/dɒɡ/", [_s("A domesticated canine.", "The dog barked.", ru=("собака",))]),
    _e(
        "ask",
        "verb",
        "/ɑːsk/",
        [_s("To put a question to someone.", "Ask him why.", ru=("спрашивать", "просить"))],
    ),
    _e(
        "take off",
        "phrase",
        None,
        [
            _s("To remove clothing.", "Take off your coat."),
            _s("To leave the ground, of an aircraft.", "The plane took off."),
        ],
    ),
    _e("Paris", "name", "/ˈpæɹɪs/", [_s("The capital city of France.", "We flew to Paris.")]),
    _e("Polish", "adj", "/ˈpoʊlɪʃ/", [_s("Of or relating to Poland.", "Polish cuisine.")]),
    _e(
        "polish",
        "verb",
        "/ˈpɒlɪʃ/",
        [_s("To make smooth and shiny by rubbing.", "Polish the silver.")],
    ),
    _e(
        "mother-in-law",
        "noun",
        "/ˈmʌðəɹɪnlɔː/",
        [_s("The mother of one's spouse.", "Her mother-in-law visited.")],
    ),
    _e("can't", "other", "/kɑːnt/", [_s("Contraction of cannot.", "I can't see it.")]),
)

#: (форма, лемма, часть речи, ранг). Ранг 0 — предпочтительная лемма для формы.
_FORMS_RAW: tuple[tuple[str, str, str, int], ...] = (
    ("went", "go", "verb", 0),
    ("gone", "go", "verb", 0),
    ("going", "go", "verb", 0),
    ("goes", "go", "verb", 0),
    ("children", "child", "noun", 0),
    ("better", "good", "adj", 0),
    ("better", "well", "adv", 1),
    ("best", "good", "adj", 0),
    ("best", "well", "adv", 1),
    ("left", "leave", "verb", 0),
    ("left", "left", "adj", 1),
    ("leaves", "leave", "verb", 0),
    ("leaving", "leave", "verb", 0),
    ("ran", "run", "verb", 0),
    ("running", "run", "verb", 0),
    ("runs", "run", "verb", 0),
    ("runs", "run", "noun", 1),
    ("books", "book", "noun", 0),
    ("booked", "book", "verb", 0),
    ("reads", "read", "verb", 0),
    ("happier", "happy", "adj", 0),
    ("happiest", "happy", "adj", 0),
    ("quicker", "quick", "adj", 0),
    ("quickest", "quick", "adj", 0),
    ("lights", "light", "noun", 0),
    ("lit", "light", "verb", 0),
    ("asked", "ask", "verb", 0),
    ("asking", "ask", "verb", 0),
    ("asks", "ask", "verb", 0),
    ("took", "take", "verb", 0),
    ("taken", "take", "verb", 0),
    ("takes", "take", "verb", 0),
    ("mice", "mouse", "noun", 0),
    ("dogs", "dog", "noun", 0),
    ("cats", "cat", "noun", 0),
    ("lamps", "lamp", "noun", 0),
    ("banks", "bank", "noun", 0),
    ("mothers-in-law", "mother-in-law", "noun", 0),
)

EN_FORMS: tuple[FormRow, ...] = tuple(FormRow(*row) for row in _FORMS_RAW)

#: (лемма, часть речи, cefr, zipf, оценка по частотности).
_LEVELS_RAW: tuple[tuple[str, str, str | None, float | None, bool], ...] = (
    ("go", "verb", "a1", 6.1, False),
    ("go", "noun", "b1", 6.1, False),
    ("child", "noun", "a1", 5.5, False),
    ("good", "adj", "a1", 6.2, False),
    ("good", "noun", "b1", 6.2, False),
    ("well", "adv", "a1", 5.9, False),
    ("well", "noun", "b2", 5.9, False),
    ("leave", "verb", "a2", 5.4, False),
    ("left", "adj", "a2", 5.3, False),
    ("run", "verb", "a1", 5.2, False),
    ("run", "noun", "b1", 5.2, False),
    ("book", "noun", "a1", 5.4, False),
    ("book", "verb", "b1", 5.4, False),
    ("read", "verb", "a1", 5.3, False),
    ("bank", "noun", "a2", 5.0, False),
    ("light", "noun", "a2", 5.2, False),
    ("light", "adj", "b1", 5.2, False),
    ("happy", "adj", "a1", 5.2, False),
    ("quick", "adj", "a2", 4.8, False),
    ("lamp", "noun", "b1", 4.1, False),
    ("cat", "noun", "a1", 4.9, False),
    ("dog", "noun", "a1", 4.9, False),
    ("ask", "verb", "a1", 5.4, False),
    ("take", "verb", "a1", 6.0, False),
    ("mouse", "noun", "a2", 4.2, False),
    ("polish", "verb", "c1", 3.5, False),
    ("ephemeral", "adj", "c2", 2.6, False),
    ("mother-in-law", "noun", "b1", None, False),
    ("serendipity", "any", None, 2.7, False),
    ("ubiquitous", "any", "c1", 3.0, True),
    ("paris", "name", None, 4.6, False),
    ("table", "noun", "a1", 5.2, False),
    ("river", "noun", "a2", 4.7, False),
    ("water", "noun", "a1", 5.4, False),
    ("morning", "noun", "a1", 5.2, False),
    ("pure", "adj", "b2", 4.5, False),
    ("fortunate", "adj", "c1", 3.6, False),
    ("shiny", "adj", "c1", 3.4, False),
    ("whisper", "verb", None, 3.8, False),
    ("lantern", "noun", None, 3.2, False),
)

EN_LEVELS: tuple[LevelRow, ...] = tuple(LevelRow(*row) for row in _LEVELS_RAW)

SOURCES = {
    "en-en": "fixture (hand-written)",
    "en-forms": "fixture (hand-written)",
    "en-levels": "fixture (hand-written)",
}


def pack_meta(pack_id: str) -> PackMeta:
    return PackMeta(pack_id=pack_id, version=VERSION, source=SOURCES[pack_id], license=LICENSE)


def pack_path(out_dir: Path, pack_id: str) -> Path:
    return out_dir / "packs" / f"{pack_id}-{VERSION}.sqlite"


def build_fixtures(out_dir: Path = FIXTURES_DIR) -> None:
    """Пересоздаёт три мини-пакета и manifest.json в `out_dir`."""
    write_en_en(pack_path(out_dir, "en-en"), pack_meta("en-en"), EN_EN)
    write_en_forms(pack_path(out_dir, "en-forms"), pack_meta("en-forms"), EN_FORMS)
    write_en_levels(pack_path(out_dir, "en-levels"), pack_meta("en-levels"), EN_LEVELS)
    entries = [
        manifest_entry(pack_path(out_dir, pid), pack_meta(pid))
        for pid in ("en-en", "en-forms", "en-levels")
    ]
    write_manifest(out_dir / "manifest.json", entries, GENERATED_AT)


if __name__ == "__main__":
    build_fixtures(Path(sys.argv[1]) if len(sys.argv) > 1 else FIXTURES_DIR)
    print("fixtures written")
