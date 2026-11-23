import 'dart:convert';

import 'package:core/domain_lookup.dart';
import 'package:test/test.dart';

Map<String, Object?> _roundTrip(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('CheatSheetScope', () {
    test('pages round-trips', () {
      const scope = CheatSheetPages(3);
      final back = CheatSheetScope.fromJson(_roundTrip(scope.toJson()));
      expect(back, scope);
      expect((back as CheatSheetPages).pages, 3);
    });

    test('chapter round-trips', () {
      const scope = CheatSheetChapter();
      expect(CheatSheetScope.fromJson(_roundTrip(scope.toJson())), scope);
    });

    test('default is pages(10)', () {
      expect(CheatSheetScope.defaultScope, const CheatSheetPages(10));
    });

    test('missing or invalid JSON gives the default', () {
      const d = CheatSheetScope.defaultScope;
      expect(CheatSheetScope.fromJson(null), d);
      expect(CheatSheetScope.fromJson(const <String, Object?>{}), d);
      expect(CheatSheetScope.fromJson(const {'type': 'pages'}), d);
      expect(CheatSheetScope.fromJson(const {'type': 'pages', 'pages': 0}), d);
      expect(
        CheatSheetScope.fromJson(const {'type': 'pages', 'pages': 'x'}),
        d,
      );
      expect(CheatSheetScope.fromJson(const {'type': 'bogus'}), d);
    });
  });

  group('UserProfile', () {
    test('defaults: enEn, b2, pages(10), no providers, no service', () {
      const profile = UserProfile();
      expect(profile.mode, LookupMode.enEn);
      expect(profile.level, CefrLevel.b2);
      expect(profile.scope, const CheatSheetPages(10));
      expect(profile.providerOrder, isEmpty);
      expect(profile.serviceUrl, isNull);
      expect(profile.cheatSheetLimit, 20);
    });

    test('empty JSON gives defaults', () {
      expect(UserProfile.fromJson(const {}), const UserProfile());
    });

    test('full profile round-trips through JSON text', () {
      const profile = UserProfile(
        mode: LookupMode.enRu,
        level: CefrLevel.c1,
        scope: CheatSheetChapter(),
        cheatSheetLimit: 50,
        providerOrder: [
          ProviderId('stardict.freedict-eng-rus'),
          ProviderId('wiktionary.en'),
        ],
        serviceUrl: 'http://192.168.1.5:8080',
      );
      final back = UserProfile.fromJson(_roundTrip(profile.toJson()));
      expect(back, profile);
      expect(back.hashCode, profile.hashCode);
    });

    test('invalid fields fall back to defaults field by field', () {
      final profile = UserProfile.fromJson(const {
        'mode': 'nope',
        'level': 'unknown',
        'scope': 7,
        'providerOrder': ['a', 1, 'b'],
        'serviceUrl': '',
      });
      expect(profile.mode, LookupMode.enEn);
      expect(profile.level, CefrLevel.b2);
      expect(profile.scope, CheatSheetScope.defaultScope);
      expect(profile.providerOrder, [
        const ProviderId('a'),
        const ProviderId('b'),
      ]);
      expect(profile.serviceUrl, isNull);
    });

    test('partial JSON keeps given fields and defaults the rest', () {
      final profile = UserProfile.fromJson(const {'level': 'c2'});
      expect(profile.level, CefrLevel.c2);
      expect(profile.mode, LookupMode.enEn);
      expect(profile.scope, CheatSheetScope.defaultScope);
    });

    test('old profile without cheatSheetLimit reads 20', () {
      final profile = UserProfile.fromJson(const {'level': 'c1'});
      expect(profile.cheatSheetLimit, 20);
    });

    test('cheatSheetLimit: 20, 50 and null round-trip; others read 20', () {
      for (final limit in <int?>[20, 50, null]) {
        final profile = UserProfile(cheatSheetLimit: limit);
        final back = UserProfile.fromJson(_roundTrip(profile.toJson()));
        expect(back.cheatSheetLimit, limit);
        expect(back, profile);
      }
      for (final bad in <Object?>[0, 30, -1, '50', 1.5, true]) {
        expect(
          UserProfile.fromJson({'cheatSheetLimit': bad}).cheatSheetLimit,
          20,
        );
      }
    });

    test('copyWith can set cheatSheetLimit to null (all)', () {
      const profile = UserProfile();
      expect(
        profile.copyWith(cheatSheetLimit: () => null).cheatSheetLimit,
        isNull,
      );
      expect(profile.copyWith(level: CefrLevel.a1).cheatSheetLimit, 20);
    });

    test('copyWith replaces and can clear serviceUrl', () {
      const profile = UserProfile(serviceUrl: 'http://x');
      expect(profile.copyWith(level: CefrLevel.a1).serviceUrl, 'http://x');
      expect(profile.copyWith(serviceUrl: () => null).serviceUrl, isNull);
      expect(profile.copyWith(mode: LookupMode.enRu).mode, LookupMode.enRu);
    });
  });
}
