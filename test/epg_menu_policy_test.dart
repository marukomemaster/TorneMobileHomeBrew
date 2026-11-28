import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/epg_menu_policy.dart';

void main() {
  final now = DateTime(2026, 11, 28, 12, 0);

  group('epgMenuActions', () {
    test('a programme that has ended offers no menu', () {
      expect(
        epgMenuActions(
          start: now.subtract(const Duration(minutes: 30)),
          end: now.subtract(const Duration(minutes: 1)),
          now: now,
          reserved: false,
        ),
        isEmpty,
      );
    });

    test('a programme ending exactly now has already ended', () {
      expect(
        epgMenuActions(
          start: now.subtract(const Duration(minutes: 30)),
          end: now,
          now: now,
          reserved: true,
        ),
        isEmpty,
      );
    });

    test('a future programme offers detail and record', () {
      expect(
        epgMenuActions(
          start: now.add(const Duration(minutes: 10)),
          end: now.add(const Duration(minutes: 40)),
          now: now,
          reserved: false,
        ),
        [EpgMenuAction.detail, EpgMenuAction.record],
      );
    });

    test('a future reserved programme offers unrecord in place of record',
        () {
      expect(
        epgMenuActions(
          start: now.add(const Duration(minutes: 10)),
          end: now.add(const Duration(minutes: 40)),
          now: now,
          reserved: true,
        ),
        [EpgMenuAction.detail, EpgMenuAction.unrecord],
      );
    });

    test('an on-air programme offers watching between detail and record',
        () {
      expect(
        epgMenuActions(
          start: now.subtract(const Duration(minutes: 10)),
          end: now.add(const Duration(minutes: 20)),
          now: now,
          reserved: false,
        ),
        [EpgMenuAction.detail, EpgMenuAction.watch, EpgMenuAction.record],
      );
    });

    test('an on-air reserved programme offers watching and unrecord', () {
      expect(
        epgMenuActions(
          start: now.subtract(const Duration(minutes: 10)),
          end: now.add(const Duration(minutes: 20)),
          now: now,
          reserved: true,
        ),
        [EpgMenuAction.detail, EpgMenuAction.watch, EpgMenuAction.unrecord],
      );
    });

    test('a programme starting exactly now is already watchable', () {
      expect(
        epgMenuActions(
          start: now,
          end: now.add(const Duration(minutes: 30)),
          now: now,
          reserved: false,
        ),
        contains(EpgMenuAction.watch),
      );
    });
  });
}
