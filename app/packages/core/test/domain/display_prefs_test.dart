import 'dart:convert';

import 'package:core/domain_lookup.dart';
import 'package:test/test.dart';

Map<String, Object?> _roundTrip(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('DisplayPrefs', () {
    test('defaults', () {
      const d = DisplayPrefs();
      expect(d.fontSize, 18);
      expect(d.lineHeight, 1.5);
      expect(d.mode, DisplayMode.day);
      expect(d.day, const Palette(text: 0xFF212121, background: 0xFFFFFBF5));
      expect(d.night, const Palette(text: 0xFFE0E0E0, background: 0xFF121212));
      expect(d.texture, const NoTexture());
      expect(d.textureOpacity, 0.5);
      expect(d.dim, 0);
      expect(d.edgeTaps, isTrue);
      expect(d.palette, d.day);
    });

    test('round-trips through JSON for every texture kind', () {
      for (final texture in const <BackgroundTexture>[
        NoTexture(),
        BuiltInTexture('paper'),
        FileTexture('/data/tex.png'),
      ]) {
        final prefs = DisplayPrefs(
          fontSize: 24,
          lineHeight: 1.8,
          mode: DisplayMode.night,
          day: const Palette(text: 0xFF000000, background: 0xFFEEEEEE),
          night: const Palette(text: 0xFFCCCCCC, background: 0xFF000000),
          texture: texture,
          textureOpacity: 0.25,
          dim: 0.4,
          edgeTaps: false,
        );
        final back = DisplayPrefs.fromJson(_roundTrip(prefs.toJson()));
        expect(back, prefs);
        expect(back.hashCode, prefs.hashCode);
        expect(back.palette, prefs.night);
      }
    });

    test('missing or invalid JSON gives defaults', () {
      const d = DisplayPrefs();
      expect(DisplayPrefs.fromJson(null), d);
      expect(DisplayPrefs.fromJson('x'), d);
      expect(DisplayPrefs.fromJson(const <String, Object?>{}), d);
      expect(
        DisplayPrefs.fromJson(const {
          'fontSize': 'big',
          'lineHeight': null,
          'mode': 3,
          'day': 'red',
          'night': {'text': 'x'},
          'texture': {'type': 'builtIn'},
          'textureOpacity': true,
          'dim': double.nan,
          'edgeTaps': 'yes',
        }),
        d,
      );
      expect(
        DisplayPrefs.fromJson(const {
          'texture': {'type': 'file', 'path': ''},
        }).texture,
        const NoTexture(),
      );
    });

    test('valid fields are kept next to invalid ones', () {
      final p = DisplayPrefs.fromJson(const {
        'fontSize': 22,
        'day': {'text': 0xFF111111},
        'edgeTaps': false,
      });
      expect(p.fontSize, 22);
      expect(p.day.text, 0xFF111111);
      expect(p.day.background, DisplayPrefs.defaultDay.background);
      expect(p.edgeTaps, isFalse);
    });

    test('out-of-range values are clamped', () {
      final low = DisplayPrefs.fromJson(const {
        'fontSize': 1,
        'lineHeight': 0.2,
        'textureOpacity': -1,
        'dim': -0.5,
      });
      expect(low.fontSize, 12);
      expect(low.lineHeight, 1.0);
      expect(low.textureOpacity, 0);
      expect(low.dim, 0);

      final high = DisplayPrefs.fromJson(const {
        'fontSize': 99,
        'lineHeight': 9,
        'textureOpacity': 3,
        'dim': 1,
      });
      expect(high.fontSize, 40);
      expect(high.lineHeight, 2.5);
      expect(high.textureOpacity, 1);
      expect(high.dim, 0.8);

      const ctor = DisplayPrefs(fontSize: 100, lineHeight: 0, dim: 5);
      expect(ctor.fontSize, 40);
      expect(ctor.lineHeight, 1.0);
      expect(ctor.dim, 0.8);
      expect(const DisplayPrefs().copyWith(fontSize: 5).fontSize, 12);
    });

    test('copyWith replaces only given fields', () {
      const d = DisplayPrefs();
      final c = d.copyWith(mode: DisplayMode.night, edgeTaps: false);
      expect(c.mode, DisplayMode.night);
      expect(c.edgeTaps, isFalse);
      expect(c.fontSize, d.fontSize);
      expect(c, isNot(d));
    });
  });

  group('DisplayPrefs.font', () {
    test('JSON without the font fields reads as the system font', () {
      final json = _roundTrip(const DisplayPrefs().toJson())
        ..remove('font')
        ..remove('fontFolder');
      final prefs = DisplayPrefs.fromJson(json);
      expect(prefs.font, isNull);
      expect(prefs.fontFolder, isNull);
      expect(prefs, const DisplayPrefs());
    });

    test('round-trips and can be cleared', () {
      const font = FontChoice(path: '/fonts/a.ttf', family: 'Lora Regular');
      final prefs = const DisplayPrefs().copyWith(
        font: () => font,
        fontFolder: () => '/home/fonts',
      );
      final back = DisplayPrefs.fromJson(_roundTrip(prefs.toJson()));
      expect(back, prefs);
      expect(back.font, font);
      expect(back.fontFolder, '/home/fonts');
      expect(back.copyWith(font: () => null).font, isNull);
      expect(back.copyWith(fontSize: 20).font, font);
    });

    test('a malformed font gives the system font', () {
      for (final bad in <Object?>[
        5,
        {'path': '', 'family': 'x'},
        {'path': '/a.ttf'},
        {'path': '/a.ttf', 'family': ''},
      ]) {
        expect(DisplayPrefs.fromJson({'font': bad}).font, isNull);
      }
    });
  });

  group('UserProfile.display', () {
    test('defaults and a profile without display', () {
      expect(const UserProfile().display, const DisplayPrefs());
      final json = const UserProfile().toJson()..remove('display');
      expect(UserProfile.fromJson(json).display, const DisplayPrefs());
    });

    test('round-trips and takes part in equality', () {
      const profile = UserProfile(
        display: DisplayPrefs(fontSize: 30, texture: BuiltInTexture('paper')),
      );
      final back = UserProfile.fromJson(_roundTrip(profile.toJson()));
      expect(back, profile);
      expect(back.hashCode, profile.hashCode);
      expect(back, isNot(const UserProfile()));
      expect(
        const UserProfile().copyWith(display: profile.display).display,
        profile.display,
      );
    });

    test('a broken display block gives defaults, other fields stay', () {
      final p = UserProfile.fromJson(const {'level': 'c2', 'display': 5});
      expect(p.display, const DisplayPrefs());
      expect(p.level, CefrLevel.c2);
    });
  });
}
