/// Generates a long English chapter locally (no download): the sandbox only
/// reaches pub.dev, so the text is synthetic prose assembled from a fixed
/// vocabulary with a deterministic PRNG. It is not a real public-domain book,
/// but has realistic word/sentence/paragraph length statistics for layout.
List<String> generateChapter({int words = 15000, int seed = 42}) {
  var state = seed;
  int next(int n) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return (state >> 8) % n;
  }

  const subjects = [
    'the old doctor',
    'her younger sister',
    'a stranger from the village',
    'the captain',
    'our neighbour',
    'the girl with the lantern',
    'my uncle',
    'the housekeeper',
    'a weary traveller',
    'the schoolmaster',
  ];
  const verbs = [
    'considered',
    'remembered',
    'observed',
    'abandoned',
    'whispered about',
    'hesitated before',
    'carefully examined',
    'could not forget',
    'wandered toward',
    'suddenly noticed',
  ];
  const objects = [
    'the crooked staircase',
    'an unexpected letter',
    'the distant harbour',
    'a heavy iron key',
    'the half-finished portrait',
    'the silent orchard',
    'a faded photograph',
    "the stranger's peculiar manner",
    'the narrow lane',
    'those mysterious footprints',
  ];
  const tails = [
    'while the rain kept falling',
    'long before the morning came',
    'as if nothing had ever happened',
    'with a certain reluctance',
    'in spite of every warning',
    'though it hardly mattered then',
    "because it wasn't his to keep",
    'until the lamps were lit',
  ];

  String sentence() {
    final s =
        '${subjects[next(subjects.length)]} '
        '${verbs[next(verbs.length)]} '
        '${objects[next(objects.length)]}'
        '${next(3) == 0 ? ' ${tails[next(tails.length)]}' : ''}';
    final cap = s[0].toUpperCase() + s.substring(1);
    return switch (next(8)) {
      0 => '$cap; yet nobody answered.',
      1 => '$cap, and "that," he said, "was that."',
      _ => '$cap.',
    };
  }

  final paragraphs = <String>[];
  var count = 0;
  while (count < words) {
    final n = 3 + next(6);
    final p = List.generate(n, (_) => sentence()).join(' ');
    paragraphs.add(p);
    count += p.split(RegExp(r'\s+')).length;
  }
  return paragraphs;
}
