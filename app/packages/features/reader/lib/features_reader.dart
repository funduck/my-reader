/// Reader screen: shows a book with a `ReaderEngine`, table of contents,
/// restores and saves the reading position.
library;

export 'src/display_settings.dart' show readerSettingsFrom;
export 'src/locator_param.dart' show encodeLocatorParam, parseLocatorParam;
export 'src/providers.dart'
    show
        LookupPresenter,
        lookupPresenterProvider,
        openBookProvider,
        saveProgressProvider;
export 'src/reader_screen.dart'
    show ReaderScreen, displaySaveDebounce, saveDebounce;
export 'src/system_chrome.dart'
    show PlatformSystemChrome, SystemChromeGateway, systemChromeProvider;
