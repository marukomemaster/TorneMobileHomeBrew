/// Recording switch policy tests (user-fork addition,
/// 2026-11-26).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_record_switch_policy.dart';

void main() {
  group('canSwitchRecords', () {
    test('a recording with two or more titles can switch', () {
      expect(canSwitchRecords(live: false, targetCount: 2), isTrue);
      expect(canSwitchRecords(live: false, targetCount: 40), isTrue);
    });

    test('a single playable title has nowhere to move to', () {
      expect(canSwitchRecords(live: false, targetCount: 1), isFalse);
      expect(canSwitchRecords(live: false, targetCount: 0), isFalse);
    });

    test('live viewing never switches recordings, whatever the count', () {
      expect(canSwitchRecords(live: true, targetCount: 5), isFalse);
      expect(canSwitchRecords(live: true, targetCount: 0), isFalse);
    });
  });
}
