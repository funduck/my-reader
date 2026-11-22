// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, BookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BookFormat, String> format =
      GeneratedColumn<String>(
        'format',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<BookFormat>($BooksTable.$converterformat);
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> addedAt =
      GeneratedColumn<int>(
        'added_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($BooksTable.$converteraddedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    author,
    language,
    format,
    filePath,
    contentHash,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      format: $BooksTable.$converterformat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}format'],
        )!,
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      addedAt: $BooksTable.$converteraddedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}added_at'],
        )!,
      ),
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BookFormat, String, String> $converterformat =
      const EnumNameConverter<BookFormat>(BookFormat.values);
  static TypeConverter<DateTime, int> $converteraddedAt =
      const UtcDateTimeConverter();
}

class BookRow extends DataClass implements Insertable<BookRow> {
  /// `BookId.value`.
  final String id;

  /// Title of the book.
  final String title;

  /// Author, if known.
  final String? author;

  /// BCP 47 language tag, if known.
  final String? language;

  /// `BookFormat` name.
  final BookFormat format;

  /// Path of the book file.
  final String filePath;

  /// Content hash, used for the duplicate check.
  final String contentHash;

  /// When the book was added, microseconds since epoch (UTC).
  final DateTime addedAt;
  const BookRow({
    required this.id,
    required this.title,
    this.author,
    this.language,
    required this.format,
    required this.filePath,
    required this.contentHash,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    {
      map['format'] = Variable<String>(
        $BooksTable.$converterformat.toSql(format),
      );
    }
    map['file_path'] = Variable<String>(filePath);
    map['content_hash'] = Variable<String>(contentHash);
    {
      map['added_at'] = Variable<int>(
        $BooksTable.$converteraddedAt.toSql(addedAt),
      );
    }
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      format: Value(format),
      filePath: Value(filePath),
      contentHash: Value(contentHash),
      addedAt: Value(addedAt),
    );
  }

  factory BookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      language: serializer.fromJson<String?>(json['language']),
      format: $BooksTable.$converterformat.fromJson(
        serializer.fromJson<String>(json['format']),
      ),
      filePath: serializer.fromJson<String>(json['filePath']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'language': serializer.toJson<String?>(language),
      'format': serializer.toJson<String>(
        $BooksTable.$converterformat.toJson(format),
      ),
      'filePath': serializer.toJson<String>(filePath),
      'contentHash': serializer.toJson<String>(contentHash),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  BookRow copyWith({
    String? id,
    String? title,
    Value<String?> author = const Value.absent(),
    Value<String?> language = const Value.absent(),
    BookFormat? format,
    String? filePath,
    String? contentHash,
    DateTime? addedAt,
  }) => BookRow(
    id: id ?? this.id,
    title: title ?? this.title,
    author: author.present ? author.value : this.author,
    language: language.present ? language.value : this.language,
    format: format ?? this.format,
    filePath: filePath ?? this.filePath,
    contentHash: contentHash ?? this.contentHash,
    addedAt: addedAt ?? this.addedAt,
  );
  BookRow copyWithCompanion(BooksCompanion data) {
    return BookRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      language: data.language.present ? data.language.value : this.language,
      format: data.format.present ? data.format.value : this.format,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('language: $language, ')
          ..write('format: $format, ')
          ..write('filePath: $filePath, ')
          ..write('contentHash: $contentHash, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    author,
    language,
    format,
    filePath,
    contentHash,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.author == this.author &&
          other.language == this.language &&
          other.format == this.format &&
          other.filePath == this.filePath &&
          other.contentHash == this.contentHash &&
          other.addedAt == this.addedAt);
}

class BooksCompanion extends UpdateCompanion<BookRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> author;
  final Value<String?> language;
  final Value<BookFormat> format;
  final Value<String> filePath;
  final Value<String> contentHash;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.language = const Value.absent(),
    this.format = const Value.absent(),
    this.filePath = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    required String title,
    this.author = const Value.absent(),
    this.language = const Value.absent(),
    required BookFormat format,
    required String filePath,
    required String contentHash,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       format = Value(format),
       filePath = Value(filePath),
       contentHash = Value(contentHash),
       addedAt = Value(addedAt);
  static Insertable<BookRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? language,
    Expression<String>? format,
    Expression<String>? filePath,
    Expression<String>? contentHash,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (language != null) 'language': language,
      if (format != null) 'format': format,
      if (filePath != null) 'file_path': filePath,
      if (contentHash != null) 'content_hash': contentHash,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? author,
    Value<String?>? language,
    Value<BookFormat>? format,
    Value<String>? filePath,
    Value<String>? contentHash,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      language: language ?? this.language,
      format: format ?? this.format,
      filePath: filePath ?? this.filePath,
      contentHash: contentHash ?? this.contentHash,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(
        $BooksTable.$converterformat.toSql(format.value),
      );
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(
        $BooksTable.$converteraddedAt.toSql(addedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('language: $language, ')
          ..write('format: $format, ')
          ..write('filePath: $filePath, ')
          ..write('contentHash: $contentHash, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingProgressTableTable extends ReadingProgressTable
    with TableInfo<$ReadingProgressTableTable, ProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Locator, String> locator =
      GeneratedColumn<String>(
        'locator',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Locator>($ReadingProgressTableTable.$converterlocator);
  static const VerificationMeta _percentMeta = const VerificationMeta(
    'percent',
  );
  @override
  late final GeneratedColumn<double> percent = GeneratedColumn<double>(
    'percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($ReadingProgressTableTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [bookId, locator, percent, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('percent')) {
      context.handle(
        _percentMeta,
        percent.isAcceptableOrUnknown(data['percent']!, _percentMeta),
      );
    } else if (isInserting) {
      context.missing(_percentMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  ProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressRow(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      locator: $ReadingProgressTableTable.$converterlocator.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}locator'],
        )!,
      ),
      percent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}percent'],
      )!,
      updatedAt: $ReadingProgressTableTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $ReadingProgressTableTable createAlias(String alias) {
    return $ReadingProgressTableTable(attachedDatabase, alias);
  }

  static TypeConverter<Locator, String> $converterlocator =
      const LocatorConverter();
  static TypeConverter<DateTime, int> $converterupdatedAt =
      const UtcDateTimeConverter();
}

class ProgressRow extends DataClass implements Insertable<ProgressRow> {
  /// `BookId.value`.
  final String bookId;

  /// `Locator` as JSON.
  final Locator locator;

  /// Fraction of the whole book read, 0..1.
  final double percent;

  /// When the position was saved, microseconds since epoch (UTC).
  final DateTime updatedAt;
  const ProgressRow({
    required this.bookId,
    required this.locator,
    required this.percent,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    {
      map['locator'] = Variable<String>(
        $ReadingProgressTableTable.$converterlocator.toSql(locator),
      );
    }
    map['percent'] = Variable<double>(percent);
    {
      map['updated_at'] = Variable<int>(
        $ReadingProgressTableTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  ReadingProgressTableCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressTableCompanion(
      bookId: Value(bookId),
      locator: Value(locator),
      percent: Value(percent),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressRow(
      bookId: serializer.fromJson<String>(json['bookId']),
      locator: serializer.fromJson<Locator>(json['locator']),
      percent: serializer.fromJson<double>(json['percent']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'locator': serializer.toJson<Locator>(locator),
      'percent': serializer.toJson<double>(percent),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProgressRow copyWith({
    String? bookId,
    Locator? locator,
    double? percent,
    DateTime? updatedAt,
  }) => ProgressRow(
    bookId: bookId ?? this.bookId,
    locator: locator ?? this.locator,
    percent: percent ?? this.percent,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProgressRow copyWithCompanion(ReadingProgressTableCompanion data) {
    return ProgressRow(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locator: data.locator.present ? data.locator.value : this.locator,
      percent: data.percent.present ? data.percent.value : this.percent,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressRow(')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('percent: $percent, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, locator, percent, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressRow &&
          other.bookId == this.bookId &&
          other.locator == this.locator &&
          other.percent == this.percent &&
          other.updatedAt == this.updatedAt);
}

class ReadingProgressTableCompanion extends UpdateCompanion<ProgressRow> {
  final Value<String> bookId;
  final Value<Locator> locator;
  final Value<double> percent;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReadingProgressTableCompanion({
    this.bookId = const Value.absent(),
    this.locator = const Value.absent(),
    this.percent = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressTableCompanion.insert({
    required String bookId,
    required Locator locator,
    required double percent,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       locator = Value(locator),
       percent = Value(percent),
       updatedAt = Value(updatedAt);
  static Insertable<ProgressRow> custom({
    Expression<String>? bookId,
    Expression<String>? locator,
    Expression<double>? percent,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (locator != null) 'locator': locator,
      if (percent != null) 'percent': percent,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressTableCompanion copyWith({
    Value<String>? bookId,
    Value<Locator>? locator,
    Value<double>? percent,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReadingProgressTableCompanion(
      bookId: bookId ?? this.bookId,
      locator: locator ?? this.locator,
      percent: percent ?? this.percent,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (locator.present) {
      map['locator'] = Variable<String>(
        $ReadingProgressTableTable.$converterlocator.toSql(locator.value),
      );
    }
    if (percent.present) {
      map['percent'] = Variable<double>(percent.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $ReadingProgressTableTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressTableCompanion(')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('percent: $percent, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfileTableTable extends ProfileTable
    with TableInfo<$ProfileTableTable, ProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<UserProfile, String> data =
      GeneratedColumn<String>(
        'data',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<UserProfile>($ProfileTableTable.$converterdata);
  @override
  List<GeneratedColumn> get $columns => [id, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      data: $ProfileTableTable.$converterdata.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}data'],
        )!,
      ),
    );
  }

  @override
  $ProfileTableTable createAlias(String alias) {
    return $ProfileTableTable(attachedDatabase, alias);
  }

  static TypeConverter<UserProfile, String> $converterdata =
      const UserProfileConverter();
}

class ProfileRow extends DataClass implements Insertable<ProfileRow> {
  /// Always [singleRowId].
  final int id;

  /// `UserProfile` as JSON.
  final UserProfile data;
  const ProfileRow({required this.id, required this.data});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['data'] = Variable<String>(
        $ProfileTableTable.$converterdata.toSql(data),
      );
    }
    return map;
  }

  ProfileTableCompanion toCompanion(bool nullToAbsent) {
    return ProfileTableCompanion(id: Value(id), data: Value(data));
  }

  factory ProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileRow(
      id: serializer.fromJson<int>(json['id']),
      data: serializer.fromJson<UserProfile>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'data': serializer.toJson<UserProfile>(data),
    };
  }

  ProfileRow copyWith({int? id, UserProfile? data}) =>
      ProfileRow(id: id ?? this.id, data: data ?? this.data);
  ProfileRow copyWithCompanion(ProfileTableCompanion data) {
    return ProfileRow(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileRow(')
          ..write('id: $id, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileRow && other.id == this.id && other.data == this.data);
}

class ProfileTableCompanion extends UpdateCompanion<ProfileRow> {
  final Value<int> id;
  final Value<UserProfile> data;
  const ProfileTableCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
  });
  ProfileTableCompanion.insert({
    this.id = const Value.absent(),
    required UserProfile data,
  }) : data = Value(data);
  static Insertable<ProfileRow> custom({
    Expression<int>? id,
    Expression<String>? data,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
    });
  }

  ProfileTableCompanion copyWith({Value<int>? id, Value<UserProfile>? data}) {
    return ProfileTableCompanion(id: id ?? this.id, data: data ?? this.data);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(
        $ProfileTableTable.$converterdata.toSql(data.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileTableCompanion(')
          ..write('id: $id, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }
}

class $LookupEventsTable extends LookupEvents
    with TableInfo<$LookupEventsTable, LookupEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LookupEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> at =
      GeneratedColumn<int>(
        'at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($LookupEventsTable.$converterat);
  static const VerificationMeta _queryTextMeta = const VerificationMeta(
    'queryText',
  );
  @override
  late final GeneratedColumn<String> queryText = GeneratedColumn<String>(
    'query_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LookupMode, String> mode =
      GeneratedColumn<String>(
        'mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LookupMode>($LookupEventsTable.$convertermode);
  static const VerificationMeta _sentenceMeta = const VerificationMeta(
    'sentence',
  );
  @override
  late final GeneratedColumn<String> sentence = GeneratedColumn<String>(
    'sentence',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Locator?, String> locator =
      GeneratedColumn<String>(
        'locator',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Locator?>($LookupEventsTable.$converterlocatorn);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterHrefMeta = const VerificationMeta(
    'chapterHref',
  );
  @override
  late final GeneratedColumn<String> chapterHref = GeneratedColumn<String>(
    'chapter_href',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transcriptionMeta = const VerificationMeta(
    'transcription',
  );
  @override
  late final GeneratedColumn<String> transcription = GeneratedColumn<String>(
    'transcription',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<Sense>, String> senses =
      GeneratedColumn<String>(
        'senses',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<Sense>>($LookupEventsTable.$convertersenses);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    at,
    queryText,
    mode,
    sentence,
    locator,
    bookId,
    chapterHref,
    chapterIndex,
    provider,
    transcription,
    senses,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lookup_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<LookupEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('query_text')) {
      context.handle(
        _queryTextMeta,
        queryText.isAcceptableOrUnknown(data['query_text']!, _queryTextMeta),
      );
    } else if (isInserting) {
      context.missing(_queryTextMeta);
    }
    if (data.containsKey('sentence')) {
      context.handle(
        _sentenceMeta,
        sentence.isAcceptableOrUnknown(data['sentence']!, _sentenceMeta),
      );
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    }
    if (data.containsKey('chapter_href')) {
      context.handle(
        _chapterHrefMeta,
        chapterHref.isAcceptableOrUnknown(
          data['chapter_href']!,
          _chapterHrefMeta,
        ),
      );
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('transcription')) {
      context.handle(
        _transcriptionMeta,
        transcription.isAcceptableOrUnknown(
          data['transcription']!,
          _transcriptionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LookupEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LookupEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      at: $LookupEventsTable.$converterat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}at'],
        )!,
      ),
      queryText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query_text'],
      )!,
      mode: $LookupEventsTable.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mode'],
        )!,
      ),
      sentence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sentence'],
      ),
      locator: $LookupEventsTable.$converterlocatorn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}locator'],
        ),
      ),
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      ),
      chapterHref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_href'],
      ),
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      ),
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      transcription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transcription'],
      ),
      senses: $LookupEventsTable.$convertersenses.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}senses'],
        )!,
      ),
    );
  }

  @override
  $LookupEventsTable createAlias(String alias) {
    return $LookupEventsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterat =
      const UtcDateTimeConverter();
  static JsonTypeConverter2<LookupMode, String, String> $convertermode =
      const EnumNameConverter<LookupMode>(LookupMode.values);
  static TypeConverter<Locator, String> $converterlocator =
      const LocatorConverter();
  static TypeConverter<Locator?, String?> $converterlocatorn =
      NullAwareTypeConverter.wrap($converterlocator);
  static TypeConverter<List<Sense>, String> $convertersenses =
      const SensesConverter();
}

class LookupEventRow extends DataClass implements Insertable<LookupEventRow> {
  /// `LookupEventId.value`.
  final String id;

  /// When the lookup happened, microseconds since epoch (UTC).
  final DateTime at;

  /// Selected text.
  final String queryText;

  /// `LookupMode` name.
  final LookupMode mode;

  /// Context sentence, if known.
  final String? sentence;

  /// `Locator` as JSON, null if the query did not come from reading.
  final Locator? locator;

  /// `Locator.book`, copied for filtering.
  final String? bookId;

  /// `Locator.chapter.href`, copied for filtering.
  final String? chapterHref;

  /// `Locator.chapter.index`, copied for filtering.
  final int? chapterIndex;

  /// `ProviderId.value` of the answer.
  final String provider;

  /// IPA transcription of the answer, if known.
  final String? transcription;

  /// List of `Sense` as JSON.
  final List<Sense> senses;
  const LookupEventRow({
    required this.id,
    required this.at,
    required this.queryText,
    required this.mode,
    this.sentence,
    this.locator,
    this.bookId,
    this.chapterHref,
    this.chapterIndex,
    required this.provider,
    this.transcription,
    required this.senses,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['at'] = Variable<int>($LookupEventsTable.$converterat.toSql(at));
    }
    map['query_text'] = Variable<String>(queryText);
    {
      map['mode'] = Variable<String>(
        $LookupEventsTable.$convertermode.toSql(mode),
      );
    }
    if (!nullToAbsent || sentence != null) {
      map['sentence'] = Variable<String>(sentence);
    }
    if (!nullToAbsent || locator != null) {
      map['locator'] = Variable<String>(
        $LookupEventsTable.$converterlocatorn.toSql(locator),
      );
    }
    if (!nullToAbsent || bookId != null) {
      map['book_id'] = Variable<String>(bookId);
    }
    if (!nullToAbsent || chapterHref != null) {
      map['chapter_href'] = Variable<String>(chapterHref);
    }
    if (!nullToAbsent || chapterIndex != null) {
      map['chapter_index'] = Variable<int>(chapterIndex);
    }
    map['provider'] = Variable<String>(provider);
    if (!nullToAbsent || transcription != null) {
      map['transcription'] = Variable<String>(transcription);
    }
    {
      map['senses'] = Variable<String>(
        $LookupEventsTable.$convertersenses.toSql(senses),
      );
    }
    return map;
  }

  LookupEventsCompanion toCompanion(bool nullToAbsent) {
    return LookupEventsCompanion(
      id: Value(id),
      at: Value(at),
      queryText: Value(queryText),
      mode: Value(mode),
      sentence: sentence == null && nullToAbsent
          ? const Value.absent()
          : Value(sentence),
      locator: locator == null && nullToAbsent
          ? const Value.absent()
          : Value(locator),
      bookId: bookId == null && nullToAbsent
          ? const Value.absent()
          : Value(bookId),
      chapterHref: chapterHref == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterHref),
      chapterIndex: chapterIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterIndex),
      provider: Value(provider),
      transcription: transcription == null && nullToAbsent
          ? const Value.absent()
          : Value(transcription),
      senses: Value(senses),
    );
  }

  factory LookupEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LookupEventRow(
      id: serializer.fromJson<String>(json['id']),
      at: serializer.fromJson<DateTime>(json['at']),
      queryText: serializer.fromJson<String>(json['queryText']),
      mode: $LookupEventsTable.$convertermode.fromJson(
        serializer.fromJson<String>(json['mode']),
      ),
      sentence: serializer.fromJson<String?>(json['sentence']),
      locator: serializer.fromJson<Locator?>(json['locator']),
      bookId: serializer.fromJson<String?>(json['bookId']),
      chapterHref: serializer.fromJson<String?>(json['chapterHref']),
      chapterIndex: serializer.fromJson<int?>(json['chapterIndex']),
      provider: serializer.fromJson<String>(json['provider']),
      transcription: serializer.fromJson<String?>(json['transcription']),
      senses: serializer.fromJson<List<Sense>>(json['senses']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'at': serializer.toJson<DateTime>(at),
      'queryText': serializer.toJson<String>(queryText),
      'mode': serializer.toJson<String>(
        $LookupEventsTable.$convertermode.toJson(mode),
      ),
      'sentence': serializer.toJson<String?>(sentence),
      'locator': serializer.toJson<Locator?>(locator),
      'bookId': serializer.toJson<String?>(bookId),
      'chapterHref': serializer.toJson<String?>(chapterHref),
      'chapterIndex': serializer.toJson<int?>(chapterIndex),
      'provider': serializer.toJson<String>(provider),
      'transcription': serializer.toJson<String?>(transcription),
      'senses': serializer.toJson<List<Sense>>(senses),
    };
  }

  LookupEventRow copyWith({
    String? id,
    DateTime? at,
    String? queryText,
    LookupMode? mode,
    Value<String?> sentence = const Value.absent(),
    Value<Locator?> locator = const Value.absent(),
    Value<String?> bookId = const Value.absent(),
    Value<String?> chapterHref = const Value.absent(),
    Value<int?> chapterIndex = const Value.absent(),
    String? provider,
    Value<String?> transcription = const Value.absent(),
    List<Sense>? senses,
  }) => LookupEventRow(
    id: id ?? this.id,
    at: at ?? this.at,
    queryText: queryText ?? this.queryText,
    mode: mode ?? this.mode,
    sentence: sentence.present ? sentence.value : this.sentence,
    locator: locator.present ? locator.value : this.locator,
    bookId: bookId.present ? bookId.value : this.bookId,
    chapterHref: chapterHref.present ? chapterHref.value : this.chapterHref,
    chapterIndex: chapterIndex.present ? chapterIndex.value : this.chapterIndex,
    provider: provider ?? this.provider,
    transcription: transcription.present
        ? transcription.value
        : this.transcription,
    senses: senses ?? this.senses,
  );
  LookupEventRow copyWithCompanion(LookupEventsCompanion data) {
    return LookupEventRow(
      id: data.id.present ? data.id.value : this.id,
      at: data.at.present ? data.at.value : this.at,
      queryText: data.queryText.present ? data.queryText.value : this.queryText,
      mode: data.mode.present ? data.mode.value : this.mode,
      sentence: data.sentence.present ? data.sentence.value : this.sentence,
      locator: data.locator.present ? data.locator.value : this.locator,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      chapterHref: data.chapterHref.present
          ? data.chapterHref.value
          : this.chapterHref,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      provider: data.provider.present ? data.provider.value : this.provider,
      transcription: data.transcription.present
          ? data.transcription.value
          : this.transcription,
      senses: data.senses.present ? data.senses.value : this.senses,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LookupEventRow(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('queryText: $queryText, ')
          ..write('mode: $mode, ')
          ..write('sentence: $sentence, ')
          ..write('locator: $locator, ')
          ..write('bookId: $bookId, ')
          ..write('chapterHref: $chapterHref, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('provider: $provider, ')
          ..write('transcription: $transcription, ')
          ..write('senses: $senses')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    at,
    queryText,
    mode,
    sentence,
    locator,
    bookId,
    chapterHref,
    chapterIndex,
    provider,
    transcription,
    senses,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LookupEventRow &&
          other.id == this.id &&
          other.at == this.at &&
          other.queryText == this.queryText &&
          other.mode == this.mode &&
          other.sentence == this.sentence &&
          other.locator == this.locator &&
          other.bookId == this.bookId &&
          other.chapterHref == this.chapterHref &&
          other.chapterIndex == this.chapterIndex &&
          other.provider == this.provider &&
          other.transcription == this.transcription &&
          other.senses == this.senses);
}

class LookupEventsCompanion extends UpdateCompanion<LookupEventRow> {
  final Value<String> id;
  final Value<DateTime> at;
  final Value<String> queryText;
  final Value<LookupMode> mode;
  final Value<String?> sentence;
  final Value<Locator?> locator;
  final Value<String?> bookId;
  final Value<String?> chapterHref;
  final Value<int?> chapterIndex;
  final Value<String> provider;
  final Value<String?> transcription;
  final Value<List<Sense>> senses;
  final Value<int> rowid;
  const LookupEventsCompanion({
    this.id = const Value.absent(),
    this.at = const Value.absent(),
    this.queryText = const Value.absent(),
    this.mode = const Value.absent(),
    this.sentence = const Value.absent(),
    this.locator = const Value.absent(),
    this.bookId = const Value.absent(),
    this.chapterHref = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.provider = const Value.absent(),
    this.transcription = const Value.absent(),
    this.senses = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LookupEventsCompanion.insert({
    required String id,
    required DateTime at,
    required String queryText,
    required LookupMode mode,
    this.sentence = const Value.absent(),
    this.locator = const Value.absent(),
    this.bookId = const Value.absent(),
    this.chapterHref = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    required String provider,
    this.transcription = const Value.absent(),
    required List<Sense> senses,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       at = Value(at),
       queryText = Value(queryText),
       mode = Value(mode),
       provider = Value(provider),
       senses = Value(senses);
  static Insertable<LookupEventRow> custom({
    Expression<String>? id,
    Expression<int>? at,
    Expression<String>? queryText,
    Expression<String>? mode,
    Expression<String>? sentence,
    Expression<String>? locator,
    Expression<String>? bookId,
    Expression<String>? chapterHref,
    Expression<int>? chapterIndex,
    Expression<String>? provider,
    Expression<String>? transcription,
    Expression<String>? senses,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (at != null) 'at': at,
      if (queryText != null) 'query_text': queryText,
      if (mode != null) 'mode': mode,
      if (sentence != null) 'sentence': sentence,
      if (locator != null) 'locator': locator,
      if (bookId != null) 'book_id': bookId,
      if (chapterHref != null) 'chapter_href': chapterHref,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (provider != null) 'provider': provider,
      if (transcription != null) 'transcription': transcription,
      if (senses != null) 'senses': senses,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LookupEventsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? at,
    Value<String>? queryText,
    Value<LookupMode>? mode,
    Value<String?>? sentence,
    Value<Locator?>? locator,
    Value<String?>? bookId,
    Value<String?>? chapterHref,
    Value<int?>? chapterIndex,
    Value<String>? provider,
    Value<String?>? transcription,
    Value<List<Sense>>? senses,
    Value<int>? rowid,
  }) {
    return LookupEventsCompanion(
      id: id ?? this.id,
      at: at ?? this.at,
      queryText: queryText ?? this.queryText,
      mode: mode ?? this.mode,
      sentence: sentence ?? this.sentence,
      locator: locator ?? this.locator,
      bookId: bookId ?? this.bookId,
      chapterHref: chapterHref ?? this.chapterHref,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      provider: provider ?? this.provider,
      transcription: transcription ?? this.transcription,
      senses: senses ?? this.senses,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(
        $LookupEventsTable.$converterat.toSql(at.value),
      );
    }
    if (queryText.present) {
      map['query_text'] = Variable<String>(queryText.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(
        $LookupEventsTable.$convertermode.toSql(mode.value),
      );
    }
    if (sentence.present) {
      map['sentence'] = Variable<String>(sentence.value);
    }
    if (locator.present) {
      map['locator'] = Variable<String>(
        $LookupEventsTable.$converterlocatorn.toSql(locator.value),
      );
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (chapterHref.present) {
      map['chapter_href'] = Variable<String>(chapterHref.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (transcription.present) {
      map['transcription'] = Variable<String>(transcription.value);
    }
    if (senses.present) {
      map['senses'] = Variable<String>(
        $LookupEventsTable.$convertersenses.toSql(senses.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LookupEventsCompanion(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('queryText: $queryText, ')
          ..write('mode: $mode, ')
          ..write('sentence: $sentence, ')
          ..write('locator: $locator, ')
          ..write('bookId: $bookId, ')
          ..write('chapterHref: $chapterHref, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('provider: $provider, ')
          ..write('transcription: $transcription, ')
          ..write('senses: $senses, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TermsTable extends Terms with TableInfo<$TermsTable, TermRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TermsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedMeta = const VerificationMeta(
    'normalized',
  );
  @override
  late final GeneratedColumn<String> normalized = GeneratedColumn<String>(
    'normalized',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lookupCountMeta = const VerificationMeta(
    'lookupCount',
  );
  @override
  late final GeneratedColumn<int> lookupCount = GeneratedColumn<int>(
    'lookup_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TermStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TermStatus>($TermsTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<CefrLevel, String> level =
      GeneratedColumn<String>(
        'level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CefrLevel>($TermsTable.$converterlevel);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    normalized,
    language,
    lookupCount,
    status,
    level,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'terms';
  @override
  VerificationContext validateIntegrity(
    Insertable<TermRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('normalized')) {
      context.handle(
        _normalizedMeta,
        normalized.isAcceptableOrUnknown(data['normalized']!, _normalizedMeta),
      );
    } else if (isInserting) {
      context.missing(_normalizedMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    } else if (isInserting) {
      context.missing(_languageMeta);
    }
    if (data.containsKey('lookup_count')) {
      context.handle(
        _lookupCountMeta,
        lookupCount.isAcceptableOrUnknown(
          data['lookup_count']!,
          _lookupCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lookupCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TermRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TermRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      normalized: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      lookupCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lookup_count'],
      )!,
      status: $TermsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      level: $TermsTable.$converterlevel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}level'],
        )!,
      ),
    );
  }

  @override
  $TermsTable createAlias(String alias) {
    return $TermsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TermStatus, String, String> $converterstatus =
      const EnumNameConverter<TermStatus>(TermStatus.values);
  static JsonTypeConverter2<CefrLevel, String, String> $converterlevel =
      const EnumNameConverter<CefrLevel>(CefrLevel.values);
}

class TermRow extends DataClass implements Insertable<TermRow> {
  /// `TermId.value`.
  final String id;

  /// Normalized form (lemma).
  final String normalized;

  /// Language code, for example `en`.
  final String language;

  /// How many times the term was looked up.
  final int lookupCount;

  /// `TermStatus` name.
  final TermStatus status;

  /// `CefrLevel` name.
  final CefrLevel level;
  const TermRow({
    required this.id,
    required this.normalized,
    required this.language,
    required this.lookupCount,
    required this.status,
    required this.level,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['normalized'] = Variable<String>(normalized);
    map['language'] = Variable<String>(language);
    map['lookup_count'] = Variable<int>(lookupCount);
    {
      map['status'] = Variable<String>(
        $TermsTable.$converterstatus.toSql(status),
      );
    }
    {
      map['level'] = Variable<String>($TermsTable.$converterlevel.toSql(level));
    }
    return map;
  }

  TermsCompanion toCompanion(bool nullToAbsent) {
    return TermsCompanion(
      id: Value(id),
      normalized: Value(normalized),
      language: Value(language),
      lookupCount: Value(lookupCount),
      status: Value(status),
      level: Value(level),
    );
  }

  factory TermRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TermRow(
      id: serializer.fromJson<String>(json['id']),
      normalized: serializer.fromJson<String>(json['normalized']),
      language: serializer.fromJson<String>(json['language']),
      lookupCount: serializer.fromJson<int>(json['lookupCount']),
      status: $TermsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      level: $TermsTable.$converterlevel.fromJson(
        serializer.fromJson<String>(json['level']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'normalized': serializer.toJson<String>(normalized),
      'language': serializer.toJson<String>(language),
      'lookupCount': serializer.toJson<int>(lookupCount),
      'status': serializer.toJson<String>(
        $TermsTable.$converterstatus.toJson(status),
      ),
      'level': serializer.toJson<String>(
        $TermsTable.$converterlevel.toJson(level),
      ),
    };
  }

  TermRow copyWith({
    String? id,
    String? normalized,
    String? language,
    int? lookupCount,
    TermStatus? status,
    CefrLevel? level,
  }) => TermRow(
    id: id ?? this.id,
    normalized: normalized ?? this.normalized,
    language: language ?? this.language,
    lookupCount: lookupCount ?? this.lookupCount,
    status: status ?? this.status,
    level: level ?? this.level,
  );
  TermRow copyWithCompanion(TermsCompanion data) {
    return TermRow(
      id: data.id.present ? data.id.value : this.id,
      normalized: data.normalized.present
          ? data.normalized.value
          : this.normalized,
      language: data.language.present ? data.language.value : this.language,
      lookupCount: data.lookupCount.present
          ? data.lookupCount.value
          : this.lookupCount,
      status: data.status.present ? data.status.value : this.status,
      level: data.level.present ? data.level.value : this.level,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TermRow(')
          ..write('id: $id, ')
          ..write('normalized: $normalized, ')
          ..write('language: $language, ')
          ..write('lookupCount: $lookupCount, ')
          ..write('status: $status, ')
          ..write('level: $level')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, normalized, language, lookupCount, status, level);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TermRow &&
          other.id == this.id &&
          other.normalized == this.normalized &&
          other.language == this.language &&
          other.lookupCount == this.lookupCount &&
          other.status == this.status &&
          other.level == this.level);
}

class TermsCompanion extends UpdateCompanion<TermRow> {
  final Value<String> id;
  final Value<String> normalized;
  final Value<String> language;
  final Value<int> lookupCount;
  final Value<TermStatus> status;
  final Value<CefrLevel> level;
  final Value<int> rowid;
  const TermsCompanion({
    this.id = const Value.absent(),
    this.normalized = const Value.absent(),
    this.language = const Value.absent(),
    this.lookupCount = const Value.absent(),
    this.status = const Value.absent(),
    this.level = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TermsCompanion.insert({
    required String id,
    required String normalized,
    required String language,
    required int lookupCount,
    required TermStatus status,
    required CefrLevel level,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       normalized = Value(normalized),
       language = Value(language),
       lookupCount = Value(lookupCount),
       status = Value(status),
       level = Value(level);
  static Insertable<TermRow> custom({
    Expression<String>? id,
    Expression<String>? normalized,
    Expression<String>? language,
    Expression<int>? lookupCount,
    Expression<String>? status,
    Expression<String>? level,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (normalized != null) 'normalized': normalized,
      if (language != null) 'language': language,
      if (lookupCount != null) 'lookup_count': lookupCount,
      if (status != null) 'status': status,
      if (level != null) 'level': level,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TermsCompanion copyWith({
    Value<String>? id,
    Value<String>? normalized,
    Value<String>? language,
    Value<int>? lookupCount,
    Value<TermStatus>? status,
    Value<CefrLevel>? level,
    Value<int>? rowid,
  }) {
    return TermsCompanion(
      id: id ?? this.id,
      normalized: normalized ?? this.normalized,
      language: language ?? this.language,
      lookupCount: lookupCount ?? this.lookupCount,
      status: status ?? this.status,
      level: level ?? this.level,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (normalized.present) {
      map['normalized'] = Variable<String>(normalized.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (lookupCount.present) {
      map['lookup_count'] = Variable<int>(lookupCount.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $TermsTable.$converterstatus.toSql(status.value),
      );
    }
    if (level.present) {
      map['level'] = Variable<String>(
        $TermsTable.$converterlevel.toSql(level.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TermsCompanion(')
          ..write('id: $id, ')
          ..write('normalized: $normalized, ')
          ..write('language: $language, ')
          ..write('lookupCount: $lookupCount, ')
          ..write('status: $status, ')
          ..write('level: $level, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TermEventsTable extends TermEvents
    with TableInfo<$TermEventsTable, TermEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TermEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _termIdMeta = const VerificationMeta('termId');
  @override
  late final GeneratedColumn<String> termId = GeneratedColumn<String>(
    'term_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [termId, eventId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'term_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<TermEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('term_id')) {
      context.handle(
        _termIdMeta,
        termId.isAcceptableOrUnknown(data['term_id']!, _termIdMeta),
      );
    } else if (isInserting) {
      context.missing(_termIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {termId, eventId};
  @override
  TermEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TermEventRow(
      termId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}term_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $TermEventsTable createAlias(String alias) {
    return $TermEventsTable(attachedDatabase, alias);
  }
}

class TermEventRow extends DataClass implements Insertable<TermEventRow> {
  /// `TermId.value`.
  final String termId;

  /// `LookupEventId.value`.
  final String eventId;

  /// Order of the event inside `Term.eventIds`, from 0.
  final int position;
  const TermEventRow({
    required this.termId,
    required this.eventId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['term_id'] = Variable<String>(termId);
    map['event_id'] = Variable<String>(eventId);
    map['position'] = Variable<int>(position);
    return map;
  }

  TermEventsCompanion toCompanion(bool nullToAbsent) {
    return TermEventsCompanion(
      termId: Value(termId),
      eventId: Value(eventId),
      position: Value(position),
    );
  }

  factory TermEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TermEventRow(
      termId: serializer.fromJson<String>(json['termId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'termId': serializer.toJson<String>(termId),
      'eventId': serializer.toJson<String>(eventId),
      'position': serializer.toJson<int>(position),
    };
  }

  TermEventRow copyWith({String? termId, String? eventId, int? position}) =>
      TermEventRow(
        termId: termId ?? this.termId,
        eventId: eventId ?? this.eventId,
        position: position ?? this.position,
      );
  TermEventRow copyWithCompanion(TermEventsCompanion data) {
    return TermEventRow(
      termId: data.termId.present ? data.termId.value : this.termId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TermEventRow(')
          ..write('termId: $termId, ')
          ..write('eventId: $eventId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(termId, eventId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TermEventRow &&
          other.termId == this.termId &&
          other.eventId == this.eventId &&
          other.position == this.position);
}

class TermEventsCompanion extends UpdateCompanion<TermEventRow> {
  final Value<String> termId;
  final Value<String> eventId;
  final Value<int> position;
  final Value<int> rowid;
  const TermEventsCompanion({
    this.termId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TermEventsCompanion.insert({
    required String termId,
    required String eventId,
    required int position,
    this.rowid = const Value.absent(),
  }) : termId = Value(termId),
       eventId = Value(eventId),
       position = Value(position);
  static Insertable<TermEventRow> custom({
    Expression<String>? termId,
    Expression<String>? eventId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (termId != null) 'term_id': termId,
      if (eventId != null) 'event_id': eventId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TermEventsCompanion copyWith({
    Value<String>? termId,
    Value<String>? eventId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return TermEventsCompanion(
      termId: termId ?? this.termId,
      eventId: eventId ?? this.eventId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (termId.present) {
      map['term_id'] = Variable<String>(termId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TermEventsCompanion(')
          ..write('termId: $termId, ')
          ..write('eventId: $eventId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ReadingProgressTableTable readingProgressTable =
      $ReadingProgressTableTable(this);
  late final $ProfileTableTable profileTable = $ProfileTableTable(this);
  late final $LookupEventsTable lookupEvents = $LookupEventsTable(this);
  late final $TermsTable terms = $TermsTable(this);
  late final $TermEventsTable termEvents = $TermEventsTable(this);
  late final Index booksContentHash = Index(
    'books_content_hash',
    'CREATE INDEX books_content_hash ON books (content_hash)',
  );
  late final Index lookupEventsAt = Index(
    'lookup_events_at',
    'CREATE INDEX lookup_events_at ON lookup_events (at)',
  );
  late final Index lookupEventsBook = Index(
    'lookup_events_book',
    'CREATE INDEX lookup_events_book ON lookup_events (book_id, chapter_index)',
  );
  late final Index termsLemma = Index(
    'terms_lemma',
    'CREATE UNIQUE INDEX terms_lemma ON terms (normalized, language)',
  );
  late final Index termEventsEvent = Index(
    'term_events_event',
    'CREATE INDEX term_events_event ON term_events (event_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    readingProgressTable,
    profileTable,
    lookupEvents,
    terms,
    termEvents,
    booksContentHash,
    lookupEventsAt,
    lookupEventsBook,
    termsLemma,
    termEventsEvent,
  ];
}

typedef $$BooksTableCreateCompanionBuilder = BooksCompanion Function({
  required String id,
  required String title,
  Value<String?> author,
  Value<String?> language,
  required BookFormat format,
  required String filePath,
  required String contentHash,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$BooksTableUpdateCompanionBuilder = BooksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String?> author,
  Value<String?> language,
  Value<BookFormat> format,
  Value<String> filePath,
  Value<String> contentHash,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BookFormat, BookFormat, String> get format =>
      $composableBuilder(
        column: $table.format,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get addedAt =>
      $composableBuilder(
        column: $table.addedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BookFormat, String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          BookRow,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (BookRow, BaseReferences<_$AppDatabase, $BooksTable, BookRow>),
          BookRow,
          PrefetchHooks Function()
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<BookFormat> format = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                author: author,
                language: language,
                format: format,
                filePath: filePath,
                contentHash: contentHash,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> author = const Value.absent(),
                Value<String?> language = const Value.absent(),
                required BookFormat format,
                required String filePath,
                required String contentHash,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                author: author,
                language: language,
                format: format,
                filePath: filePath,
                contentHash: contentHash,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BooksTable, BookRow>(table),
                  BaseReferences<_$AppDatabase, $BooksTable, BookRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      BookRow,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (BookRow, BaseReferences<_$AppDatabase, $BooksTable, BookRow>),
      BookRow,
      PrefetchHooks Function()
    >;
typedef $$ReadingProgressTableTableCreateCompanionBuilder =
    ReadingProgressTableCompanion Function({
      required String bookId,
      required Locator locator,
      required double percent,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReadingProgressTableTableUpdateCompanionBuilder =
    ReadingProgressTableCompanion Function({
      Value<String> bookId,
      Value<Locator> locator,
      Value<double> percent,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ReadingProgressTableTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressTableTable> {
  $$ReadingProgressTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Locator, Locator, String> get locator =>
      $composableBuilder(
        column: $table.locator,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$ReadingProgressTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressTableTable> {
  $$ReadingProgressTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadingProgressTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressTableTable> {
  $$ReadingProgressTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Locator, String> get locator =>
      $composableBuilder(column: $table.locator, builder: (column) => column);

  GeneratedColumn<double> get percent =>
      $composableBuilder(column: $table.percent, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReadingProgressTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressTableTable,
          ProgressRow,
          $$ReadingProgressTableTableFilterComposer,
          $$ReadingProgressTableTableOrderingComposer,
          $$ReadingProgressTableTableAnnotationComposer,
          $$ReadingProgressTableTableCreateCompanionBuilder,
          $$ReadingProgressTableTableUpdateCompanionBuilder,
          (
            ProgressRow,
            BaseReferences<
              _$AppDatabase,
              $ReadingProgressTableTable,
              ProgressRow
            >,
          ),
          ProgressRow,
          PrefetchHooks Function()
        > {
  $$ReadingProgressTableTableTableManager(
    _$AppDatabase db,
    $ReadingProgressTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingProgressTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReadingProgressTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<Locator> locator = const Value.absent(),
                Value<double> percent = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressTableCompanion(
                bookId: bookId,
                locator: locator,
                percent: percent,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required Locator locator,
                required double percent,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressTableCompanion.insert(
                bookId: bookId,
                locator: locator,
                percent: percent,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReadingProgressTableTable, ProgressRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReadingProgressTableTable,
                    ProgressRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadingProgressTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressTableTable,
      ProgressRow,
      $$ReadingProgressTableTableFilterComposer,
      $$ReadingProgressTableTableOrderingComposer,
      $$ReadingProgressTableTableAnnotationComposer,
      $$ReadingProgressTableTableCreateCompanionBuilder,
      $$ReadingProgressTableTableUpdateCompanionBuilder,
      (
        ProgressRow,
        BaseReferences<_$AppDatabase, $ReadingProgressTableTable, ProgressRow>,
      ),
      ProgressRow,
      PrefetchHooks Function()
    >;
typedef $$ProfileTableTableCreateCompanionBuilder =
    ProfileTableCompanion Function({Value<int> id, required UserProfile data});
typedef $$ProfileTableTableUpdateCompanionBuilder =
    ProfileTableCompanion Function({Value<int> id, Value<UserProfile> data});

class $$ProfileTableTableFilterComposer
    extends Composer<_$AppDatabase, $ProfileTableTable> {
  $$ProfileTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<UserProfile, UserProfile, String> get data =>
      $composableBuilder(
        column: $table.data,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$ProfileTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfileTableTable> {
  $$ProfileTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfileTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfileTableTable> {
  $$ProfileTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<UserProfile, String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$ProfileTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfileTableTable,
          ProfileRow,
          $$ProfileTableTableFilterComposer,
          $$ProfileTableTableOrderingComposer,
          $$ProfileTableTableAnnotationComposer,
          $$ProfileTableTableCreateCompanionBuilder,
          $$ProfileTableTableUpdateCompanionBuilder,
          (
            ProfileRow,
            BaseReferences<_$AppDatabase, $ProfileTableTable, ProfileRow>,
          ),
          ProfileRow,
          PrefetchHooks Function()
        > {
  $$ProfileTableTableTableManager(_$AppDatabase db, $ProfileTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfileTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfileTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<UserProfile> data = const Value.absent(),
          }) => ProfileTableCompanion(id: id, data: data),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required UserProfile data,
          }) => ProfileTableCompanion.insert(id: id, data: data),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfileTableTable, ProfileRow>(table),
                  BaseReferences<_$AppDatabase, $ProfileTableTable, ProfileRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfileTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfileTableTable,
      ProfileRow,
      $$ProfileTableTableFilterComposer,
      $$ProfileTableTableOrderingComposer,
      $$ProfileTableTableAnnotationComposer,
      $$ProfileTableTableCreateCompanionBuilder,
      $$ProfileTableTableUpdateCompanionBuilder,
      (
        ProfileRow,
        BaseReferences<_$AppDatabase, $ProfileTableTable, ProfileRow>,
      ),
      ProfileRow,
      PrefetchHooks Function()
    >;
typedef $$LookupEventsTableCreateCompanionBuilder =
    LookupEventsCompanion Function({
      required String id,
      required DateTime at,
      required String queryText,
      required LookupMode mode,
      Value<String?> sentence,
      Value<Locator?> locator,
      Value<String?> bookId,
      Value<String?> chapterHref,
      Value<int?> chapterIndex,
      required String provider,
      Value<String?> transcription,
      required List<Sense> senses,
      Value<int> rowid,
    });
typedef $$LookupEventsTableUpdateCompanionBuilder =
    LookupEventsCompanion Function({
      Value<String> id,
      Value<DateTime> at,
      Value<String> queryText,
      Value<LookupMode> mode,
      Value<String?> sentence,
      Value<Locator?> locator,
      Value<String?> bookId,
      Value<String?> chapterHref,
      Value<int?> chapterIndex,
      Value<String> provider,
      Value<String?> transcription,
      Value<List<Sense>> senses,
      Value<int> rowid,
    });

class $$LookupEventsTableFilterComposer
    extends Composer<_$AppDatabase, $LookupEventsTable> {
  $$LookupEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get at =>
      $composableBuilder(
        column: $table.at,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get queryText => $composableBuilder(
    column: $table.queryText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LookupMode, LookupMode, String> get mode =>
      $composableBuilder(
        column: $table.mode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get sentence => $composableBuilder(
    column: $table.sentence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Locator?, Locator, String> get locator =>
      $composableBuilder(
        column: $table.locator,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterHref => $composableBuilder(
    column: $table.chapterHref,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transcription => $composableBuilder(
    column: $table.transcription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<Sense>, List<Sense>, String> get senses =>
      $composableBuilder(
        column: $table.senses,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$LookupEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $LookupEventsTable> {
  $$LookupEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queryText => $composableBuilder(
    column: $table.queryText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sentence => $composableBuilder(
    column: $table.sentence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterHref => $composableBuilder(
    column: $table.chapterHref,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transcription => $composableBuilder(
    column: $table.transcription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senses => $composableBuilder(
    column: $table.senses,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LookupEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LookupEventsTable> {
  $$LookupEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<String> get queryText =>
      $composableBuilder(column: $table.queryText, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LookupMode, String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get sentence =>
      $composableBuilder(column: $table.sentence, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Locator?, String> get locator =>
      $composableBuilder(column: $table.locator, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get chapterHref => $composableBuilder(
    column: $table.chapterHref,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get transcription => $composableBuilder(
    column: $table.transcription,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<Sense>, String> get senses =>
      $composableBuilder(column: $table.senses, builder: (column) => column);
}

class $$LookupEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LookupEventsTable,
          LookupEventRow,
          $$LookupEventsTableFilterComposer,
          $$LookupEventsTableOrderingComposer,
          $$LookupEventsTableAnnotationComposer,
          $$LookupEventsTableCreateCompanionBuilder,
          $$LookupEventsTableUpdateCompanionBuilder,
          (
            LookupEventRow,
            BaseReferences<_$AppDatabase, $LookupEventsTable, LookupEventRow>,
          ),
          LookupEventRow,
          PrefetchHooks Function()
        > {
  $$LookupEventsTableTableManager(_$AppDatabase db, $LookupEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LookupEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LookupEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LookupEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<String> queryText = const Value.absent(),
                Value<LookupMode> mode = const Value.absent(),
                Value<String?> sentence = const Value.absent(),
                Value<Locator?> locator = const Value.absent(),
                Value<String?> bookId = const Value.absent(),
                Value<String?> chapterHref = const Value.absent(),
                Value<int?> chapterIndex = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String?> transcription = const Value.absent(),
                Value<List<Sense>> senses = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LookupEventsCompanion(
                id: id,
                at: at,
                queryText: queryText,
                mode: mode,
                sentence: sentence,
                locator: locator,
                bookId: bookId,
                chapterHref: chapterHref,
                chapterIndex: chapterIndex,
                provider: provider,
                transcription: transcription,
                senses: senses,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime at,
                required String queryText,
                required LookupMode mode,
                Value<String?> sentence = const Value.absent(),
                Value<Locator?> locator = const Value.absent(),
                Value<String?> bookId = const Value.absent(),
                Value<String?> chapterHref = const Value.absent(),
                Value<int?> chapterIndex = const Value.absent(),
                required String provider,
                Value<String?> transcription = const Value.absent(),
                required List<Sense> senses,
                Value<int> rowid = const Value.absent(),
              }) => LookupEventsCompanion.insert(
                id: id,
                at: at,
                queryText: queryText,
                mode: mode,
                sentence: sentence,
                locator: locator,
                bookId: bookId,
                chapterHref: chapterHref,
                chapterIndex: chapterIndex,
                provider: provider,
                transcription: transcription,
                senses: senses,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LookupEventsTable, LookupEventRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LookupEventsTable,
                    LookupEventRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LookupEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LookupEventsTable,
      LookupEventRow,
      $$LookupEventsTableFilterComposer,
      $$LookupEventsTableOrderingComposer,
      $$LookupEventsTableAnnotationComposer,
      $$LookupEventsTableCreateCompanionBuilder,
      $$LookupEventsTableUpdateCompanionBuilder,
      (
        LookupEventRow,
        BaseReferences<_$AppDatabase, $LookupEventsTable, LookupEventRow>,
      ),
      LookupEventRow,
      PrefetchHooks Function()
    >;
typedef $$TermsTableCreateCompanionBuilder = TermsCompanion Function({
  required String id,
  required String normalized,
  required String language,
  required int lookupCount,
  required TermStatus status,
  required CefrLevel level,
  Value<int> rowid,
});
typedef $$TermsTableUpdateCompanionBuilder = TermsCompanion Function({
  Value<String> id,
  Value<String> normalized,
  Value<String> language,
  Value<int> lookupCount,
  Value<TermStatus> status,
  Value<CefrLevel> level,
  Value<int> rowid,
});

class $$TermsTableFilterComposer extends Composer<_$AppDatabase, $TermsTable> {
  $$TermsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalized => $composableBuilder(
    column: $table.normalized,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lookupCount => $composableBuilder(
    column: $table.lookupCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TermStatus, TermStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<CefrLevel, CefrLevel, String> get level =>
      $composableBuilder(
        column: $table.level,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$TermsTableOrderingComposer
    extends Composer<_$AppDatabase, $TermsTable> {
  $$TermsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalized => $composableBuilder(
    column: $table.normalized,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lookupCount => $composableBuilder(
    column: $table.lookupCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TermsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TermsTable> {
  $$TermsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get normalized => $composableBuilder(
    column: $table.normalized,
    builder: (column) => column,
  );

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<int> get lookupCount => $composableBuilder(
    column: $table.lookupCount,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TermStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<CefrLevel, String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);
}

class $$TermsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TermsTable,
          TermRow,
          $$TermsTableFilterComposer,
          $$TermsTableOrderingComposer,
          $$TermsTableAnnotationComposer,
          $$TermsTableCreateCompanionBuilder,
          $$TermsTableUpdateCompanionBuilder,
          (TermRow, BaseReferences<_$AppDatabase, $TermsTable, TermRow>),
          TermRow,
          PrefetchHooks Function()
        > {
  $$TermsTableTableManager(_$AppDatabase db, $TermsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TermsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TermsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TermsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> normalized = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<int> lookupCount = const Value.absent(),
                Value<TermStatus> status = const Value.absent(),
                Value<CefrLevel> level = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TermsCompanion(
                id: id,
                normalized: normalized,
                language: language,
                lookupCount: lookupCount,
                status: status,
                level: level,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String normalized,
                required String language,
                required int lookupCount,
                required TermStatus status,
                required CefrLevel level,
                Value<int> rowid = const Value.absent(),
              }) => TermsCompanion.insert(
                id: id,
                normalized: normalized,
                language: language,
                lookupCount: lookupCount,
                status: status,
                level: level,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TermsTable, TermRow>(table),
                  BaseReferences<_$AppDatabase, $TermsTable, TermRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TermsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TermsTable,
      TermRow,
      $$TermsTableFilterComposer,
      $$TermsTableOrderingComposer,
      $$TermsTableAnnotationComposer,
      $$TermsTableCreateCompanionBuilder,
      $$TermsTableUpdateCompanionBuilder,
      (TermRow, BaseReferences<_$AppDatabase, $TermsTable, TermRow>),
      TermRow,
      PrefetchHooks Function()
    >;
typedef $$TermEventsTableCreateCompanionBuilder = TermEventsCompanion Function({
  required String termId,
  required String eventId,
  required int position,
  Value<int> rowid,
});
typedef $$TermEventsTableUpdateCompanionBuilder = TermEventsCompanion Function({
  Value<String> termId,
  Value<String> eventId,
  Value<int> position,
  Value<int> rowid,
});

class $$TermEventsTableFilterComposer
    extends Composer<_$AppDatabase, $TermEventsTable> {
  $$TermEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get termId => $composableBuilder(
    column: $table.termId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TermEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $TermEventsTable> {
  $$TermEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get termId => $composableBuilder(
    column: $table.termId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TermEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TermEventsTable> {
  $$TermEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get termId =>
      $composableBuilder(column: $table.termId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$TermEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TermEventsTable,
          TermEventRow,
          $$TermEventsTableFilterComposer,
          $$TermEventsTableOrderingComposer,
          $$TermEventsTableAnnotationComposer,
          $$TermEventsTableCreateCompanionBuilder,
          $$TermEventsTableUpdateCompanionBuilder,
          (
            TermEventRow,
            BaseReferences<_$AppDatabase, $TermEventsTable, TermEventRow>,
          ),
          TermEventRow,
          PrefetchHooks Function()
        > {
  $$TermEventsTableTableManager(_$AppDatabase db, $TermEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TermEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TermEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TermEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> termId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TermEventsCompanion(
                termId: termId,
                eventId: eventId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String termId,
                required String eventId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => TermEventsCompanion.insert(
                termId: termId,
                eventId: eventId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TermEventsTable, TermEventRow>(table),
                  BaseReferences<_$AppDatabase, $TermEventsTable, TermEventRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TermEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TermEventsTable,
      TermEventRow,
      $$TermEventsTableFilterComposer,
      $$TermEventsTableOrderingComposer,
      $$TermEventsTableAnnotationComposer,
      $$TermEventsTableCreateCompanionBuilder,
      $$TermEventsTableUpdateCompanionBuilder,
      (
        TermEventRow,
        BaseReferences<_$AppDatabase, $TermEventsTable, TermEventRow>,
      ),
      TermEventRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ReadingProgressTableTableTableManager get readingProgressTable =>
      $$ReadingProgressTableTableTableManager(_db, _db.readingProgressTable);
  $$ProfileTableTableTableManager get profileTable =>
      $$ProfileTableTableTableManager(_db, _db.profileTable);
  $$LookupEventsTableTableManager get lookupEvents =>
      $$LookupEventsTableTableManager(_db, _db.lookupEvents);
  $$TermsTableTableManager get terms =>
      $$TermsTableTableManager(_db, _db.terms);
  $$TermEventsTableTableManager get termEvents =>
      $$TermEventsTableTableManager(_db, _db.termEvents);
}
