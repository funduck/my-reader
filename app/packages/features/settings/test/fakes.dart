import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';

/// In-memory [DictionaryLibrary]; records calls and can fail imports.
class FakeDictionaryLibrary implements DictionaryLibrary {
  new([List<ImportedDictionary> initial = const []])
    : dictionaries = [...initial];

  final List<ImportedDictionary> dictionaries;
  final List<(List<String>, LookupMode)> imports = [];
  final List<String> removed = [];

  /// Thrown by the next [import] when set.
  Exception? importFailure;

  /// Called after every change, like the app rebuilds its providers.
  void Function()? onChanged;

  @override
  Future<List<ImportedDictionary>> list() async => [...dictionaries];

  @override
  Future<ImportedDictionary> import(List<String> files, LookupMode mode) async {
    final failure = importFailure;
    if (failure != null) throw failure;
    imports.add((files, mode));
    final dictionary = fakeDictionary('imported-${imports.length}', mode: mode);
    dictionaries.add(dictionary);
    onChanged?.call();
    return dictionary;
  }

  @override
  Future<bool> remove(String id) async {
    removed.add(id);
    final before = dictionaries.length;
    dictionaries.removeWhere((d) => d.id == id);
    onChanged?.call();
    return dictionaries.length != before;
  }
}

/// Description of a dictionary with the id [id].
ImportedDictionary fakeDictionary(
  String id, {
  LookupMode mode = LookupMode.enRu,
}) => ImportedDictionary(
  id: id,
  name: 'Dictionary $id',
  mode: mode,
  wordCount: 100,
  providerId: ProviderId('stardict.$id'),
);

/// Provider with a name and no behavior.
class FakeProvider implements LookupProvider {
  new(String id, String name, {Set<LookupMode>? modes})
    : id = ProviderId(id),
      info = ProviderInfo(
        name: name,
        isOnline: false,
        modes: modes ?? {LookupMode.enRu},
      );

  @override
  final ProviderId id;

  @override
  final ProviderInfo info;

  @override
  bool supports(LookupMode mode) => info.modes.contains(mode);

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) =>
      throw UnimplementedError();
}
