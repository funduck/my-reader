import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';

/// Id of the demo book.
const demoBookId = BookId('demo-book');

/// Path the demo format adapter opens as the demo book.
const demoBookPath = '/demo/the-lighthouse-keeper.epub';

/// Title of the demo book.
const demoBookTitle = 'The Lighthouse Keeper';

/// Texts of the demo book chapters; paragraphs are split at blank lines.
///
/// Written for the demo (no licence questions). Words with demo answers and
/// levels: lantern, reluctant, threshold, gale, weary, mischievous; harbour
/// has a level but no answer. The phrase [demoPhrase] has a translation.
const demoChapters = [
  '''
Old Tobias lit the lantern every evening, long before the sun touched the sea. He climbed the hundred steps slowly, because his knees were weary, but he never missed a night.

The village children thought the lighthouse was haunted. Only Mira, the baker's mischievous daughter, dared to cross its threshold. She brought him bread and stories, and he kept an eye on her while she explored the dusty rooms.

"Why do you stay here alone?" she asked one evening. Tobias was reluctant to answer. He looked at the harbour, where the fishing boats rocked on the dark water.

"Because someone has to," he said at last.''',
  '''
The gale arrived on a Tuesday. By noon the waves were taller than the harbour wall, and the boats had not returned.

Mira ran up the hundred steps with her heart pounding. Tobias was already there, cleaning the glass so that the lantern would shine as far as possible.

"Will they see it?" she whispered.

"They always do," said Tobias, and for the first time she noticed that he was not weary at all. He was waiting, the way the lighthouse waited, patient and bright.''',
];

/// A phrase from the demo book that the demo phrase translator knows.
const demoPhrase = 'kept an eye on';

/// Russian translation of [demoPhrase].
const demoPhraseTranslation = 'присматривал за';

/// Provider of the EN → EN demo answers.
const demoEnEnProvider = ProviderId('demo-en-en');

/// Provider of the EN → RU demo answers.
const demoEnRuProvider = ProviderId('demo-en-ru');

/// Provider of the demo phrase translations.
const demoPhraseProvider = ProviderId('demo-phrases');

/// Explanations in English: long, several senses with examples.
const Map<String, LookupResult> demoEnEnAnswers = {
  'lantern': LookupResult(
    provider: demoEnEnProvider,
    transcription: '/ˈlæntən/',
    senses: [
      Sense(
        partOfSpeech: 'noun',
        text:
            'A lamp with a transparent case protecting the flame or '
            'electric bulb, and typically having a handle by which it can be '
            'carried or hung.',
        examples: [
          'He held the lantern high to light the path.',
          'Paper lanterns hung above the street.',
        ],
      ),
      Sense(
        partOfSpeech: 'noun',
        text:
            'The light chamber at the top of a lighthouse, where the lamp '
            'and its lenses are kept.',
        examples: ['The keeper polished the glass of the lantern.'],
      ),
      Sense(
        partOfSpeech: 'noun',
        text:
            'A raised structure on the top of a dome or a roof, with glazed '
            'or open sides, admitting light or air.',
      ),
    ],
  ),
  'reluctant': LookupResult(
    provider: demoEnEnProvider,
    transcription: '/rɪˈlʌktənt/',
    senses: [
      Sense(
        partOfSpeech: 'adjective',
        text: 'Unwilling and hesitant; disinclined to do something.',
        examples: [
          'She was reluctant to leave the party early.',
          'Reluctant agreement is still agreement.',
        ],
      ),
    ],
  ),
  'threshold': LookupResult(
    provider: demoEnEnProvider,
    transcription: '/ˈθrɛʃhəʊld/',
    senses: [
      Sense(
        partOfSpeech: 'noun',
        text:
            'A strip of wood or stone forming the bottom of a doorway and '
            'crossed in entering a house or room.',
        examples: ['He paused on the threshold.'],
      ),
      Sense(
        partOfSpeech: 'noun',
        text:
            'The magnitude or intensity that must be exceeded for a certain '
            'reaction, phenomenon, result, or condition to occur.',
        examples: ['The pain threshold differs from person to person.'],
      ),
    ],
  ),
  'gale': LookupResult(
    provider: demoEnEnProvider,
    transcription: '/ɡeɪl/',
    senses: [
      Sense(
        partOfSpeech: 'noun',
        text: 'A very strong wind.',
        examples: ['The gale tore the sails to pieces.'],
      ),
      Sense(
        partOfSpeech: 'noun',
        text: 'An outburst of laughter.',
        examples: ['The room dissolved into gales of laughter.'],
      ),
    ],
  ),
  'weary': LookupResult(
    provider: demoEnEnProvider,
    transcription: '/ˈwɪəri/',
    senses: [
      Sense(
        partOfSpeech: 'adjective',
        text:
            'Feeling or showing extreme tiredness, especially as a result '
            'of excessive exertion or lack of sleep.',
        examples: ['He gave a weary sigh.'],
      ),
      Sense(
        partOfSpeech: 'adjective',
        text: 'Reluctant to see or experience any more of; tired of.',
        examples: ['She was weary of the constant noise.'],
      ),
    ],
  ),
  'mischievous': LookupResult(
    provider: demoEnEnProvider,
    transcription: '/ˈmɪstʃɪvəs/',
    senses: [
      Sense(
        partOfSpeech: 'adjective',
        text:
            'Causing or showing a fondness for causing trouble in a playful '
            'way.',
        examples: ['A mischievous grin spread across her face.'],
      ),
    ],
  ),
};

/// Translations into Russian: short, one or two lines.
const Map<String, LookupResult> demoEnRuAnswers = {
  'lantern': LookupResult(
    provider: demoEnRuProvider,
    transcription: '/ˈlæntən/',
    senses: [Sense(partOfSpeech: 'noun', text: 'фонарь')],
  ),
  'reluctant': LookupResult(
    provider: demoEnRuProvider,
    senses: [Sense(partOfSpeech: 'adjective', text: 'неохотный')],
  ),
  'threshold': LookupResult(
    provider: demoEnRuProvider,
    senses: [Sense(partOfSpeech: 'noun', text: 'порог')],
  ),
  'gale': LookupResult(
    provider: demoEnRuProvider,
    senses: [Sense(partOfSpeech: 'noun', text: 'шторм, сильный ветер')],
  ),
  'weary': LookupResult(
    provider: demoEnRuProvider,
    senses: [Sense(partOfSpeech: 'adjective', text: 'усталый')],
  ),
  'mischievous': LookupResult(
    provider: demoEnRuProvider,
    senses: [Sense(partOfSpeech: 'adjective', text: 'озорной')],
  ),
};

/// CEFR levels of demo words by lemma; other words are unknown.
const Map<String, CefrLevel> demoLevels = {
  'harbour': CefrLevel.b1,
  'lantern': CefrLevel.b2,
  'reluctant': CefrLevel.b2,
  'threshold': CefrLevel.c1,
  'gale': CefrLevel.c1,
  'weary': CefrLevel.c1,
  'mischievous': CefrLevel.c2,
};
