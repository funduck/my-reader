/// Tuning constants of the cheat sheet (M4, M9). Change them here only.
library;

/// Language of the terms that count as "already looked up".
const cheatSheetLanguage = 'en';

/// Lowest Zipf frequency that gets 5 bars (the most frequent words).
const zipfBars5 = 5.0;

/// Lowest Zipf frequency that gets 4 bars.
const zipfBars4 = 4.0;

/// Lowest Zipf frequency that gets 3 bars.
const zipfBars3 = 3.0;

/// Lowest Zipf frequency that gets 2 bars; below it a word gets 1 bar.
const zipfBars2 = 2.0;

/// Words on each side of the word in a short quote.
const shortQuoteWindow = 7;
