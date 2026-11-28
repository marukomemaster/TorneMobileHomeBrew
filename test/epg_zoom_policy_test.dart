import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/epg_zoom_policy.dart';

void main() {
  group('clampEpgZoomScale', () {
    test('keeps scales inside the range', () {
      expect(clampEpgZoomScale(0.5), 0.5);
      expect(clampEpgZoomScale(1.0), 1.0);
      expect(clampEpgZoomScale(2.25), 2.25);
      expect(clampEpgZoomScale(3.0), 3.0);
    });

    test('clamps scales outside the range to its ends', () {
      expect(clampEpgZoomScale(0.1), epgMinZoomScale);
      expect(clampEpgZoomScale(0), epgMinZoomScale);
      expect(clampEpgZoomScale(-2), epgMinZoomScale);
      expect(clampEpgZoomScale(99), epgMaxZoomScale);
    });
  });

  group('epgPxPerMinuteForScale', () {
    test('scale 1 is the density the guide has always had', () {
      expect(epgPxPerMinuteForScale(1), epgBasePxPerMinute);
      expect(epgBasePxPerMinute, 2.4);
    });

    test('the density follows the scale', () {
      expect(epgPxPerMinuteForScale(0.5), closeTo(1.2, 1e-9));
      expect(epgPxPerMinuteForScale(2), closeTo(4.8, 1e-9));
      expect(epgPxPerMinuteForScale(3), closeTo(7.2, 1e-9));
    });

    test('an out-of-range scale converts at the clamped scale', () {
      expect(epgPxPerMinuteForScale(0.01), closeTo(1.2, 1e-9));
      expect(epgPxPerMinuteForScale(100), closeTo(7.2, 1e-9));
    });
  });

  group('decodeEpgZoomScale', () {
    test('nothing stored is the default scale', () {
      expect(decodeEpgZoomScale(null), epgDefaultZoomScale);
    });

    test('a stored scale reads back', () {
      expect(decodeEpgZoomScale('1.5'), 1.5);
      expect(decodeEpgZoomScale('2.0'), 2.0);
    });

    test('an unparseable value is the default, never an error', () {
      expect(decodeEpgZoomScale('wide'), epgDefaultZoomScale);
      expect(decodeEpgZoomScale(''), epgDefaultZoomScale);
    });

    test('a stored out-of-range value reads back clamped', () {
      expect(decodeEpgZoomScale('0.1'), epgMinZoomScale);
      expect(decodeEpgZoomScale('42'), epgMaxZoomScale);
    });
  });
}
