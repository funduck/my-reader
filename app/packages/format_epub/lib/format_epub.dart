/// EPUB 2/3 adapter of `BookFormatAdapter`: container, OPF, metadata, spine.
library;

export 'src/chapters.dart' show ChapterPlan;
export 'src/content/xhtml_to_content.dart' show ChapterContent, convertXhtml;
export 'src/epub_archive.dart' show EpubArchive, parseXml;
export 'src/epub_format_adapter.dart' show EpubBook, EpubFormatAdapter;
export 'src/epub_package.dart' show EpubPackage, ManifestItem;
export 'src/epub_path.dart' show normalizeEntryPath, resolveEntryPath;
