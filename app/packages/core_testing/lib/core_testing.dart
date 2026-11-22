/// Fakes of core ports and contract test suites for adapters.
///
/// Fakes are in-memory and deterministic. Every adapter of a port runs the
/// matching `*Contract` suite, and the fakes here pass the same suites.
library;

export 'src/contracts/book_repository_contract.dart';
export 'src/contracts/format_adapter_contract.dart';
export 'src/contracts/lookup_journal_contract.dart';
export 'src/contracts/lookup_provider_contract.dart';
export 'src/contracts/profile_repository_contract.dart';
export 'src/contracts/progress_repository_contract.dart';
export 'src/contracts/term_repository_contract.dart';
export 'src/fakes/fake_book_format_adapter.dart';
export 'src/fakes/fake_book_repository.dart';
export 'src/fakes/fake_clock.dart';
export 'src/fakes/fake_lookup_journal.dart';
export 'src/fakes/fake_lookup_provider.dart';
export 'src/fakes/fake_opened_book.dart';
export 'src/fakes/fake_pack_store.dart';
export 'src/fakes/fake_profile_repository.dart';
export 'src/fakes/fake_progress_repository.dart';
export 'src/fakes/fake_term_repository.dart';
export 'src/fakes/seq_id_generator.dart';
