/// The programme guide's vertical zoom (owner request
/// 2026-11-28: the official app's guide pinches in and
/// out — this is the same gesture, over the same scale).
///
/// The grid's density is pixels per broadcast minute; at
/// scale 1 the density is [epgBasePxPerMinute], the
/// density the guide has always had. The scale is
/// clamped to [epgMinZoomScale]–[epgMaxZoomScale]: below
/// the bottom, a day shrinks until no tile can carry a
/// title; above the top, one programme fills the screen
/// and the day stops being an overview. Pure conversions
/// only — the grid, the persisted setting and the tests
/// all read the scale through here.
library;

/// Pixels per broadcast minute at zoom scale 1.
const double epgBasePxPerMinute = 2.4;

/// The smallest zoom scale (the day at its densest).
const double epgMinZoomScale = 0.5;

/// The largest zoom scale (the day at its roomiest).
const double epgMaxZoomScale = 3.0;

/// The scale an untouched guide sits at.
const double epgDefaultZoomScale = 1.0;

/// [scale] held inside the zoom range.
double clampEpgZoomScale(double scale) =>
    scale.clamp(epgMinZoomScale, epgMaxZoomScale);

/// The grid density for [scale]: pixels per broadcast
/// minute, the scale clamped first.
double epgPxPerMinuteForScale(double scale) =>
    epgBasePxPerMinute * clampEpgZoomScale(scale);

/// The persisted scale's read (the key-value store holds
/// it as a plain double literal): anything unparseable
/// is the default scale, never an error — a broken stored
/// value must not break the guide.
double decodeEpgZoomScale(String? raw) {
  final value = raw == null ? null : double.tryParse(raw);
  return value == null ? epgDefaultZoomScale : clampEpgZoomScale(value);
}
