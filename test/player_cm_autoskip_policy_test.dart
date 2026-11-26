/// Player CM auto skip policy tests (user-fork
/// addition): the run classification, the opening /
/// ending rails, and the manual-seek suppression.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_cm_autoskip_policy.dart';

void main() {
  // A 30-minute recording: a long opening, a long
  // programme segment, a two-spot break (30 s + 30 s),
  // programme, a one-spot break (30 s), programme,
  // and a long ending segment.
  const duration = Duration(seconds: 1800);
  const chapters = [
    Duration(seconds: 300),
    Duration(seconds: 480),
    Duration(seconds: 510),
    Duration(seconds: 540),
    Duration(seconds: 900),
    Duration(seconds: 1080),
    Duration(seconds: 1110),
    Duration(seconds: 1500),
  ];

  Duration? target(Duration position, {Duration? suppressedRunStart}) =>
      cmAutoSkipTarget(
        chapters: chapters,
        position: position,
        duration: duration,
        suppressedRunStart: suppressedRunStart,
      );

  group('cmAutoSkipTarget', () {
    test('no chapters, no skip', () {
      expect(
        cmAutoSkipTarget(
          chapters: const [],
          position: const Duration(seconds: 500),
          duration: duration,
        ),
        isNull,
      );
    });

    test('unknown duration, no skip', () {
      expect(
        cmAutoSkipTarget(
          chapters: chapters,
          position: const Duration(seconds: 500),
          duration: Duration.zero,
        ),
        isNull,
      );
    });

    test('the opening segment is never skipped', () {
      expect(target(const Duration(seconds: 100)), isNull);
    });

    test('a long programme segment is not skipped', () {
      expect(target(const Duration(seconds: 400)), isNull);
      expect(target(const Duration(seconds: 600)), isNull);
    });

    test('a two-spot break is skipped as one run', () {
      expect(
        target(const Duration(seconds: 500)),
        const Duration(seconds: 540),
      );
      expect(
        target(const Duration(seconds: 530)),
        const Duration(seconds: 540),
      );
    });

    test('a one-spot break is skipped to its end', () {
      expect(
        target(const Duration(seconds: 1090)),
        const Duration(seconds: 1110),
      );
    });

    test('standing on a break start still skips', () {
      expect(
        target(const Duration(seconds: 480)),
        const Duration(seconds: 540),
      );
    });

    test('standing on the segment after a break does not skip', () {
      expect(target(const Duration(seconds: 540)), isNull);
    });

    test('the ending segment is never skipped', () {
      expect(target(const Duration(seconds: 1600)), isNull);
    });

    test('a suppressed run is left alone', () {
      expect(
        target(
          const Duration(seconds: 500),
          suppressedRunStart: const Duration(seconds: 480),
        ),
        isNull,
      );
    });

    test('suppressing another run does not stop this one', () {
      expect(
        target(
          const Duration(seconds: 500),
          suppressedRunStart: const Duration(seconds: 1080),
        ),
        const Duration(seconds: 540),
      );
    });

    test('a short first segment is not skipped', () {
      expect(
        cmAutoSkipTarget(
          chapters: const [Duration(seconds: 30)],
          position: const Duration(seconds: 10),
          duration: duration,
        ),
        isNull,
      );
    });

    test('a short last segment is not skipped', () {
      expect(
        cmAutoSkipTarget(
          chapters: const [Duration(seconds: 1700)],
          position: const Duration(seconds: 1750),
          duration: duration,
        ),
        isNull,
      );
    });

    test('a run before the last segment lands on its start', () {
      expect(
        cmAutoSkipTarget(
          chapters: const [
            Duration(seconds: 600),
            Duration(seconds: 630),
            Duration(seconds: 660),
          ],
          position: const Duration(seconds: 640),
          duration: duration,
        ),
        const Duration(seconds: 660),
      );
    });
  });

  group('cmRunStartAt', () {
    Duration? runStart(Duration position) => cmRunStartAt(
      chapters: chapters,
      position: position,
      duration: duration,
    );

    test('inside a break, the run start comes back', () {
      expect(runStart(const Duration(seconds: 520)), const Duration(seconds: 480));
      expect(
        runStart(const Duration(seconds: 1095)),
        const Duration(seconds: 1080),
      );
    });

    test('outside a break, nothing comes back', () {
      expect(runStart(const Duration(seconds: 100)), isNull);
      expect(runStart(const Duration(seconds: 400)), isNull);
      expect(runStart(const Duration(seconds: 1600)), isNull);
    });
  });
}
