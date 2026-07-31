import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';

void main() {
  group('PairedDesktop JSON', () {
    const base = PairedDesktop(
      id: 'd1',
      name: 'Studio',
      wsUrls: ['ws://192.168.1.5:5555/pair/ws'],
      hostPublicKeyB64: 'pk',
      deviceToken: 't',
    );

    test('lastConnectedAt survives a round-trip', () {
      final stamped = base.copyWith(
        lastConnectedAt: DateTime.fromMillisecondsSinceEpoch(1730000000000),
      );
      final restored = PairedDesktop.fromJson(stamped.toJson());
      expect(
        restored!.lastConnectedAt,
        DateTime.fromMillisecondsSinceEpoch(1730000000000),
      );
      expect(restored.id, 'd1');
      expect(restored.wsUrls, base.wsUrls);
    });

    test('a desktop paired before the field existed reads back as null', () {
      final legacy = base.toJson()..remove('lastConnectedAt');
      expect(PairedDesktop.fromJson(legacy)!.lastConnectedAt, isNull);
    });

    test('an ISO string is accepted and junk degrades to null', () {
      final iso = base.toJson()..['lastConnectedAt'] = '2026-07-31T10:00:00Z';
      expect(
        PairedDesktop.fromJson(iso)!.lastConnectedAt,
        DateTime.utc(2026, 7, 31, 10),
      );

      final junk = base.toJson()..['lastConnectedAt'] = {'not': 'a time'};
      expect(PairedDesktop.fromJson(junk)!.lastConnectedAt, isNull);
    });

    test('copyWith keeps an existing stamp when none is passed', () {
      final stamped = base.copyWith(lastConnectedAt: DateTime(2026, 7, 1));
      expect(stamped.copyWith(name: 'Renamed').lastConnectedAt, DateTime(2026, 7, 1));
    });
  });
}
