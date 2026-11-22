import 'package:meta/meta.dart';

/// Parsed `.ifo` file of a StarDict dictionary.
@immutable
class StarDictInfo {
  /// Creates the info; `parse` is the usual way to get one.
  const new({
    required this.version,
    required this.bookName,
    required this.wordCount,
    required this.idxFileSize,
    this.idxOffsetBits = 32,
    this.synWordCount,
    this.sameTypeSequence,
    this.author,
    this.email,
    this.website,
    this.description,
    this.date,
    this.dictType,
  });

  /// Parses the text of an `.ifo` file.
  ///
  /// The first line must be `StarDict's dict ifo file`, the rest are
  /// `key=value` lines. `version`, `bookname`, `wordcount` and `idxfilesize`
  /// are required; `idxoffsetbits` is 32 (default) or 64. Unknown keys are
  /// ignored. Throws [FormatException] on anything else.
  factory parse(String text) {
    final lines = text.replaceFirst('﻿', '').split(RegExp(r'\r\n|\n|\r'));
    if (lines.first.trim() != _magic) {
      throw const FormatException('Not a StarDict .ifo file: bad first line');
    }
    final fields = <String, String>{};
    for (final raw in lines.skip(1)) {
      if (raw.trim().isEmpty) continue;
      final eq = raw.indexOf('=');
      if (eq <= 0) {
        throw FormatException('Malformed .ifo line', raw);
      }
      fields[raw.substring(0, eq).trim()] = raw.substring(eq + 1).trim();
    }

    String required(String key) {
      final v = fields[key];
      if (v == null || v.isEmpty) {
        throw FormatException('Missing "$key" in .ifo');
      }
      return v;
    }

    int number(String key, String value) {
      final n = int.tryParse(value);
      if (n == null || n < 0) {
        throw FormatException('Bad "$key" in .ifo', value);
      }
      return n;
    }

    final bitsText = fields['idxoffsetbits'];
    final bits = bitsText == null ? 32 : number('idxoffsetbits', bitsText);
    if (bits != 32 && bits != 64) {
      throw FormatException('Unsupported idxoffsetbits', bitsText);
    }
    final syn = fields['synwordcount'];
    return StarDictInfo(
      version: required('version'),
      bookName: required('bookname'),
      wordCount: number('wordcount', required('wordcount')),
      idxFileSize: number('idxfilesize', required('idxfilesize')),
      idxOffsetBits: bits,
      synWordCount: syn == null ? null : number('synwordcount', syn),
      sameTypeSequence: fields['sametypesequence'],
      author: fields['author'],
      email: fields['email'],
      website: fields['website'],
      description: fields['description'],
      date: fields['date'],
      dictType: fields['dicttype'],
    );
  }

  static const _magic = "StarDict's dict ifo file";

  /// Format version, e.g. `2.4.2` or `3.0.0`.
  final String version;

  /// Dictionary title (`bookname`).
  final String bookName;

  /// Number of entries in the `.idx` file.
  final int wordCount;

  /// Size of the `.idx` file in bytes.
  final int idxFileSize;

  /// Width of the article offset in `.idx`: 32 or 64.
  final int idxOffsetBits;

  /// Number of entries in the `.syn` file, if there is one.
  final int? synWordCount;

  /// Article type letters shared by all entries (`m`, `h`, `x`, ...), or null
  /// when every article carries its own type.
  final String? sameTypeSequence;

  /// `author`, if given.
  final String? author;

  /// `email`, if given.
  final String? email;

  /// `website`, if given.
  final String? website;

  /// `description`, if given.
  final String? description;

  /// `date`, if given (free text).
  final String? date;

  /// `dicttype`, if given.
  final String? dictType;

  /// Size in bytes of the offset field of an `.idx` entry.
  int get offsetBytes => idxOffsetBits ~/ 8;

  @override
  bool operator ==(Object other) =>
      other is StarDictInfo &&
      other.version == version &&
      other.bookName == bookName &&
      other.wordCount == wordCount &&
      other.idxFileSize == idxFileSize &&
      other.idxOffsetBits == idxOffsetBits &&
      other.synWordCount == synWordCount &&
      other.sameTypeSequence == sameTypeSequence &&
      other.author == author &&
      other.email == email &&
      other.website == website &&
      other.description == description &&
      other.date == date &&
      other.dictType == dictType;

  @override
  int get hashCode => Object.hash(
    version,
    bookName,
    wordCount,
    idxFileSize,
    idxOffsetBits,
    synWordCount,
    sameTypeSequence,
    author,
    email,
    website,
    description,
    date,
    dictType,
  );
}
