/// Fakes of core ports only, without the contract suites.
///
/// For code outside tests (the demo app): the suites in `core_testing.dart`
/// pull in `package:test`.
library;

export 'src/fakes/fake_book_format_adapter.dart';
export 'src/fakes/fake_book_repository.dart';
export 'src/fakes/fake_clock.dart';
export 'src/fakes/fake_lookup_journal.dart';
export 'src/fakes/fake_lookup_provider.dart';
export 'src/fakes/fake_opened_book.dart';
export 'src/fakes/fake_pack_store.dart';
export 'src/fakes/fake_phrase_journal.dart';
export 'src/fakes/fake_profile_repository.dart';
export 'src/fakes/fake_progress_repository.dart';
export 'src/fakes/fake_secret_store.dart';
export 'src/fakes/fake_term_repository.dart';
export 'src/fakes/seq_id_generator.dart';
