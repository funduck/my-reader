import 'dart:convert';
import 'dart:typed_data';

int _fold(int byte) => byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte;

/// Compares `a[aStart, aEnd)` with `b` the way StarDict sorts `.idx` words
/// (`stardict_strcmp`).
///
/// First an ASCII case-insensitive comparison (only `A`-`Z` are folded; all
/// other bytes, including every non-ASCII one, compare as is). If it finds
/// no difference, a plain byte comparison breaks the tie. Returns a negative
/// number, zero or a positive number.
int stardictCompareSlice(Uint8List a, int aStart, int aEnd, Uint8List b) {
  final aLen = aEnd - aStart;
  final common = aLen < b.length ? aLen : b.length;
  for (var i = 0; i < common; i++) {
    final d = _fold(a[aStart + i]) - _fold(b[i]);
    if (d != 0) return d;
  }
  if (aLen != b.length) return aLen - b.length;
  for (var i = 0; i < common; i++) {
    final d = a[aStart + i] - b[i];
    if (d != 0) return d;
  }
  return 0;
}

/// Compares two UTF-8 byte strings as StarDict does, see
/// [stardictCompareSlice].
int stardictCompareBytes(Uint8List a, Uint8List b) =>
    stardictCompareSlice(a, 0, a.length, b);

/// Compares two words as StarDict does, on their UTF-8 encoding.
///
/// Use it to sort the words of an `.idx` file you generate.
int stardictCompare(String a, String b) => stardictCompareBytes(
  Uint8List.fromList(utf8.encode(a)),
  Uint8List.fromList(utf8.encode(b)),
);
