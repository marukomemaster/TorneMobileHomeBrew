/// On-air emphasis for the programme guide (user-fork
/// addition, owner request 2026-11-28): the official
/// guide the owner compared against makes the programme
/// on air right now readable at a glance by colour, and
/// the grid here only coloured by genre. This policy is
/// the pure half of the same reading for torne mobile
/// HB's grid:
///
/// - whether an event is on air is a half-open interval
///   test, [start, end) — a programme starting this
///   instant is on air, one ending this instant is over;
/// - an on-air tile keeps its genre tint but at a
///   stronger blend, so the kind still reads while the
///   "on now" reads louder;
/// - the tile's frame stays the reservation's signal:
///   the red reserved frame (epg_reserved.dart) wins
///   when both apply, and the on-air frame — the theme
///   accent at the reserved frame's width — shows only
///   on unreserved tiles. The background tint carries
///   the on-air reading either way, so neither signal
///   is lost when a reserved programme is also on air.
///
/// The ranking screen's 放送中 tab ranks by the same
/// predicate (onair_ranking_policy.dart).
library;

import 'package:material_ui/material_ui.dart';

import 'epg_genre.dart';
import 'epg_reserved.dart';

/// Whether the programme spanning [start]–[end] is on
/// air at [now]: the start instant itself counts as on
/// air, the end instant does not (the next programme
/// owns it).
bool epgEventIsOnAir({
  required DateTime start,
  required DateTime end,
  required DateTime now,
}) => !now.isBefore(start) && now.isBefore(end);

/// How strongly the genre colour tints an on-air tile:
/// the resting tint (epgGenreTintStrength) says what
/// kind a programme is; this stronger blend says it is
/// on now, while staying a text background.
const double epgOnAirTintStrength = 0.55;

/// How strongly the accent tints an on-air tile whose
/// genre has no colour (or which has no genre): lighter
/// than the genre blend, since the accent also carries
/// the frame and the time text on the same tile.
const double epgOnAirAccentTintStrength = 0.28;

/// The background colour of an on-air guide tile: the
/// genre colour blended at [epgOnAirTintStrength] over
/// [surface]; a genre without a colour (or no genre)
/// blends [accent] at [epgOnAirAccentTintStrength] over
/// [fallback] instead — the same two bases
/// [epgGenreTileColor] paints, deepened.
Color epgOnAirTileColor({
  required int? genreLevel1,
  required Color surface,
  required Color fallback,
  required Color accent,
}) {
  final base = epgGenreColor(genreLevel1);
  if (base != null) {
    return Color.alphaBlend(
      base.withAlpha((epgOnAirTintStrength * 255).round()),
      surface,
    );
  }
  return Color.alphaBlend(
    accent.withAlpha((epgOnAirAccentTintStrength * 255).round()),
    fallback,
  );
}

/// The foreground frame of a guide tile, composing the
/// two framed states: a reservation's red frame
/// (epg_reserved.dart) when [reserved] — it is the
/// rarer, acted-on signal — and otherwise an accent
/// frame at the same width when [onAir]. Null when
/// neither applies, as tiles have always painted.
BoxDecoration? epgTileFrame({
  required bool reserved,
  required bool onAir,
  required Color onAirColor,
}) {
  if (reserved) return epgReservedFrame(true);
  if (onAir) {
    return BoxDecoration(
      border: Border.all(color: onAirColor, width: epgReservedFrameWidth),
      borderRadius: BorderRadius.circular(3),
    );
  }
  return null;
}
