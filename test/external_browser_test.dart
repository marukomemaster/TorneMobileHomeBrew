/// External browser opening tests (owner request
/// 2026-11-26): the nasne HOME URL form, the per-platform
/// desktop commands, rundll32's meaningless exit code being
/// ignored, honest non-zero exits and start failures
/// surfacing as errors, the mobile platform route, and
/// unsupported platforms launching nothing. The settings
/// screen's registration menu hands the tapped unit's HOME
/// address to the opener.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/external_browser.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/settings_screen.dart';

void main() {
  group('nasneHomeUri', () {
    test('is plain HTTP on the registered host, no port', () {
      expect(
        nasneHomeUri('192.168.11.129').toString(),
        'http://192.168.11.129/',
      );
      expect(nasneHomeUri('nasne.local').toString(), 'http://nasne.local/');
    });
  });

  group('browserOpenCommandFor', () {
    const url = 'http://192.168.11.129/';

    test('windows hands the URL to rundll32 and ignores its exit code', () {
      final command = browserOpenCommandFor(
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        url: url,
      );
      expect(command, isNotNull);
      expect(command!.executable, 'rundll32');
      expect(command.arguments, ['url.dll,FileProtocolHandler', url]);
      expect(command.exitCodeMatters, isFalse);
    });

    test('macos opens with open and checks its exit code', () {
      final command = browserOpenCommandFor(
        isWindows: false,
        isMacOS: true,
        isLinux: false,
        url: url,
      );
      expect(command, isNotNull);
      expect(command!.executable, 'open');
      expect(command.arguments, [url]);
      expect(command.exitCodeMatters, isTrue);
    });

    test('linux opens with xdg-open and checks its exit code', () {
      final command = browserOpenCommandFor(
        isWindows: false,
        isMacOS: false,
        isLinux: true,
        url: url,
      );
      expect(command, isNotNull);
      expect(command!.executable, 'xdg-open');
      expect(command.arguments, [url]);
      expect(command.exitCodeMatters, isTrue);
    });

    test('no desktop platform means no command', () {
      expect(
        browserOpenCommandFor(
          isWindows: false,
          isMacOS: false,
          isLinux: false,
          url: url,
        ),
        isNull,
      );
    });
  });

  group('ExternalBrowserOpener', () {
    final home = nasneHomeUri('192.168.11.129');

    ExternalBrowserOpener opener({
      required List<(String, List<String>)> runs,
      int exitCode = 0,
      List<String>? platformOpens,
      bool throwMissingPlugin = false,
      bool isWindows = false,
      bool isMacOS = false,
      bool isLinux = false,
      bool isAndroid = false,
      bool isIOS = false,
    }) {
      return ExternalBrowserOpener(
        runProcess: (executable, arguments) async {
          runs.add((executable, arguments));
          return ProcessResult(0, exitCode, '', '');
        },
        openViaPlatform: (url) async {
          if (throwMissingPlugin) throw MissingPluginException();
          platformOpens?.add(url);
        },
        isWindows: isWindows,
        isMacOS: isMacOS,
        isLinux: isLinux,
        isAndroid: isAndroid,
        isIOS: isIOS,
      );
    }

    test('linux runs xdg-open on the URL', () async {
      final runs = <(String, List<String>)>[];
      final outcome = await opener(runs: runs, isLinux: true).open(home);
      expect(outcome, ExternalBrowserOpenOutcome.opened);
      expect(runs, hasLength(1));
      expect(runs.single.$1, 'xdg-open');
      expect(runs.single.$2, ['http://192.168.11.129/']);
    });

    test('a non-zero xdg-open exit surfaces as an error', () async {
      final runs = <(String, List<String>)>[];
      await expectLater(
        opener(runs: runs, exitCode: 1, isLinux: true).open(home),
        throwsA(isA<ProcessException>()),
      );
    });

    test('a non-zero rundll32 exit is ignored on windows', () async {
      final runs = <(String, List<String>)>[];
      final outcome = await opener(
        runs: runs,
        exitCode: 1,
        isWindows: true,
      ).open(home);
      expect(outcome, ExternalBrowserOpenOutcome.opened);
      expect(runs.single.$1, 'rundll32');
    });

    test('android goes through the platform route', () async {
      final runs = <(String, List<String>)>[];
      final platformOpens = <String>[];
      final outcome = await opener(
        runs: runs,
        platformOpens: platformOpens,
        isAndroid: true,
      ).open(home);
      expect(outcome, ExternalBrowserOpenOutcome.opened);
      expect(platformOpens, ['http://192.168.11.129/']);
      expect(runs, isEmpty);
    });

    test('a missing native side folds into unsupported', () async {
      final runs = <(String, List<String>)>[];
      final outcome = await opener(
        runs: runs,
        throwMissingPlugin: true,
        isIOS: true,
      ).open(home);
      expect(outcome, ExternalBrowserOpenOutcome.unsupported);
    });

    test('no platform at all is unsupported and launches nothing', () async {
      final runs = <(String, List<String>)>[];
      final outcome = await opener(runs: runs).open(home);
      expect(outcome, ExternalBrowserOpenOutcome.unsupported);
      expect(runs, isEmpty);
    });
  });

  group('settings screen registration menu', () {
    testWidgets('nasne HOME を開く hands the unit address to the opener', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const reg = RegisteredNasne(
        host: '192.168.11.129',
        udn: 'uuid:00000000-0000-0000-0000-000000000000',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );
      final recording = _RecordingOpener();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [reg]),
            ),
            externalBrowserOpenerProvider.overrideWithValue(recording),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('nasne HOME を開く'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(recording.opened, [Uri.parse('http://192.168.11.129/')]);
    });
  });
}

/// An opener that records instead of launching, for the
/// settings screen test.
class _RecordingOpener extends ExternalBrowserOpener {
  final List<Uri> opened = [];

  @override
  Future<ExternalBrowserOpenOutcome> open(Uri url) async {
    opened.add(url);
    return ExternalBrowserOpenOutcome.opened;
  }
}
