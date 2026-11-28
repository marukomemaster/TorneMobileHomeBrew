/// The title detail's thumbnail banner on the TV variant
/// (owner report 2026-11-28: the banner looked coarse on
/// Fire TV). The unit's thumbnail frames are 360x240 and
/// no larger source exists (plan 99), so the TV banner is
/// width-capped and centred instead of stretched across
/// the whole TV; the standard variant keeps its full-width
/// 16:9 banner.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/app/variant.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/titles_screen.dart';

const _reg = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

const _title = RecordedTitle(id: '1', title: 'テスト番組');

/// A 1x1 PNG: the frame's content is beside the point —
/// the banner's box is what is under test.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  required AppVariant variant,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVariantProvider.overrideWithValue(variant),
        titleThumbnailProvider.overrideWith((ref, key) async => _pngBytes),
        channelsProvider.overrideWith((ref, reg) async => <Channel>[]),
        credentialSummaryProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(
        home: Scaffold(body: TitleDetailView(reg: _reg, title: _title)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the TV banner is capped at 600 wide and centred', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      variant: AppVariant.tv,
      size: const Size(1920, 1080),
    );
    final image = find.byType(Image);
    expect(image, findsOneWidget);
    final size = tester.getSize(image);
    // The cap, at the banner's 16:9 — not the ~1888 px the
    // full TV width used to stretch the 360-px frame to.
    expect(size.width, 600);
    expect(size.height, closeTo(600 * 9 / 16, 0.6));
    // Centred in the detail's width.
    final centre = tester.getCenter(image);
    expect(centre.dx, closeTo(1920 / 2, 1));
  });

  testWidgets('the standard banner keeps its full-width 16:9', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      variant: AppVariant.standard,
      size: const Size(1200, 800),
    );
    final image = find.byType(Image);
    expect(image, findsOneWidget);
    final size = tester.getSize(image);
    expect(size.width, greaterThan(600));
    expect(size.height, closeTo(size.width * 9 / 16, 0.6));
  });
}
