import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

class _Progress implements ProgressRepository {
  final List<ReadingProgress> saved = [];
  @override
  Future<ReadingProgress?> get(BookId book) async => null;
  @override
  Stream<ReadingProgress?> watch(BookId book) => const Stream.empty();
  @override
  Future<void> save(ReadingProgress progress) async => saved.add(progress);
}

class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2024, 5, 6);
}

void main() {
  Locator at(int chapter, double progression) => Locator(
    book: const BookId('b'),
    chapter: ChapterRef(href: 'c$chapter.xhtml', index: chapter),
    progression: progression,
  );

  late _Progress repo;
  late SaveProgress save;
  setUp(() {
    repo = _Progress();
    save = SaveProgress(progress: repo, clock: _Clock());
  });

  test('saves the locator with percent and time', () async {
    await save(at(1, 0.5), chapterCount: 4);
    expect(repo.saved.single.locator, at(1, 0.5));
    expect(repo.saved.single.percent, 0.375);
    expect(repo.saved.single.updatedAt, DateTime.utc(2024, 5, 6));
  });

  test('with chapter lengths saves the fraction by text length', () async {
    await save(at(1, 0.5), chapterCount: 3, chapterLengths: [100, 700, 200]);
    expect(repo.saved.single.percent, closeTo(0.45, 1e-9));
  });

  test('percent is clamped and safe for an empty spine', () async {
    await save(at(3, 1), chapterCount: 4);
    await save(at(0, 0.2), chapterCount: 0);
    expect(repo.saved[0].percent, 1);
    expect(repo.saved[1].percent, 0);
  });
}
