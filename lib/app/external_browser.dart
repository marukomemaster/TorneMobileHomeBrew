/// Opening a URL in the device's external browser (owner
/// request 2026-11-26): the settings screen's registration
/// menu hands the unit's nasne HOME to the browser the user
/// already uses, instead of growing a web view inside the app.
///
/// The launch follows the project's standing split (plan 35 /
/// 46 / 71): desktop runs the OS opener as a process — the
/// same shape as the log-folder open (app/log_folder.dart) —
/// and mobile goes through a hand-rolled platform channel,
/// because a url_launcher dependency would pull in a
/// platform-interface tree for one intent / open call.
/// Failures are reported to the caller, never swallowed: the
/// settings screen turns them into a visible error, the same
/// defensive line as the log actions.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// The nasne HOME address of a registered unit: the unit's
/// own web UI, plain HTTP on the registered host with no
/// port. The ports the app itself talks to (WebAPI 64210,
/// UPnP 58888, SOAP 64230) are machine interfaces; HOME is
/// served on the standard web port.
Uri nasneHomeUri(String host) => Uri(scheme: 'http', host: host, path: '/');

/// A command that opens a URL in a desktop browser.
class BrowserOpenCommand {
  const BrowserOpenCommand(
    this.executable,
    this.arguments, {
    required this.exitCodeMatters,
  });

  /// The program to run (`rundll32`, `open`, `xdg-open`).
  final String executable;

  /// Its arguments: the URL to open.
  final List<String> arguments;

  /// Whether a non-zero exit code means the open failed.
  ///
  /// rundll32's exit code is not a success signal (it answers
  /// 0 whether or not a browser actually took the URL), so on
  /// Windows only a failure to start the process counts.
  /// `open` and `xdg-open` report honestly and are checked.
  final bool exitCodeMatters;
}

/// The browser-open command for the platform selected by
/// [isWindows] / [isMacOS] / [isLinux], or null when none of
/// them applies (mobile: the platform channel's job).
BrowserOpenCommand? browserOpenCommandFor({
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
  required String url,
}) {
  if (isWindows) {
    // url.dll's FileProtocolHandler is the long-standing way
    // to hand a URL to the default browser from a process;
    // explorer.exe would treat the URL as a folder path.
    return BrowserOpenCommand('rundll32', [
      'url.dll,FileProtocolHandler',
      url,
    ], exitCodeMatters: false);
  }
  if (isMacOS) {
    return BrowserOpenCommand('open', [url], exitCodeMatters: true);
  }
  if (isLinux) {
    return BrowserOpenCommand('xdg-open', [url], exitCodeMatters: true);
  }
  return null;
}

/// Outcome of an [ExternalBrowserOpener.open] attempt.
enum ExternalBrowserOpenOutcome {
  /// The browser was launched on the URL.
  opened,

  /// This platform has no launch route (anything other than
  /// Windows / macOS / Linux / Android / iOS). Nothing was
  /// launched.
  unsupported,
}

/// The platform call behind [ExternalBrowserOpener] on
/// mobile: hands [url] to the native side, which fires the
/// platform's view intent / open call.
typedef PlatformUrlOpen = Future<void> Function(String url);

/// Opens URLs in the device's external browser.
class ExternalBrowserOpener {
  ExternalBrowserOpener({
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runProcess,
    PlatformUrlOpen? openViaPlatform,
    bool? isWindows,
    bool? isMacOS,
    bool? isLinux,
    bool? isAndroid,
    bool? isIOS,
  }) : _runProcess = runProcess ?? Process.run,
       _openViaPlatform = openViaPlatform ?? _openViaChannel,
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isLinux = isLinux ?? Platform.isLinux,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _isIOS = isIOS ?? Platform.isIOS;

  final Future<ProcessResult> Function(String, List<String>) _runProcess;
  final PlatformUrlOpen _openViaPlatform;
  final bool _isWindows;
  final bool _isMacOS;
  final bool _isLinux;
  final bool _isAndroid;
  final bool _isIOS;

  static const MethodChannel _channel = MethodChannel(
    'com.markun.tmhb/external_browser',
  );

  static Future<void> _openViaChannel(String url) =>
      _channel.invokeMethod<void>('openUrl', {'url': url});

  /// Launches the browser on [url].
  ///
  /// Throws when the launch route exists but fails (a
  /// non-zero exit on platforms whose exit code matters, the
  /// process failing to start, or the platform side refusing)
  /// — the caller surfaces the failure instead of the tap
  /// looking dead. A platform with no route at all answers
  /// [ExternalBrowserOpenOutcome.unsupported] instead. A
  /// mobile build whose native side predates the channel has
  /// no route either: the missing-plugin answer folds into
  /// unsupported, never a crash.
  Future<ExternalBrowserOpenOutcome> open(Uri url) async {
    final command = browserOpenCommandFor(
      isWindows: _isWindows,
      isMacOS: _isMacOS,
      isLinux: _isLinux,
      url: url.toString(),
    );
    if (command != null) {
      final result = await _runProcess(command.executable, command.arguments);
      if (command.exitCodeMatters && result.exitCode != 0) {
        throw ProcessException(
          command.executable,
          command.arguments,
          'exited with code ${result.exitCode}',
          result.exitCode,
        );
      }
      return ExternalBrowserOpenOutcome.opened;
    }
    if (_isAndroid || _isIOS) {
      try {
        await _openViaPlatform(url.toString());
      } on MissingPluginException {
        return ExternalBrowserOpenOutcome.unsupported;
      }
      return ExternalBrowserOpenOutcome.opened;
    }
    return ExternalBrowserOpenOutcome.unsupported;
  }
}
