/// Auto record rules and planning (user-fork addition;
/// not part of the upstream plans): the viewer's
/// standing rules — a keyword, a genre, or both —
/// are matched against the held programme guide, and
/// the matches are reserved in rule order, the way the
/// official clients' keyword recording works, within
/// what a phone app can promise.
///
/// The honest limits, by design:
/// - A check runs only while the app runs (at startup
///   and on demand from the rules screen). Programmes
///   that have already started are never candidates:
///   a reservation made from the app can only cover
///   the future.
/// - The unit has one tuner, so overlaps are resolved
///   by rule order: rules are planned from the first
///   (strongest) down, and a programme that would
///   overlap a reservation already on the unit — or
///   one planned earlier in the same check — is
///   skipped, never forced. Nothing is ever deleted
///   or displaced to make room.
/// - A rule with neither a keyword nor a genre would
///   match the whole guide; it matches nothing, so a
///   half-filled rule can never flood the unit.
///
/// This file is the pure half: matching, planning and
/// the rules' JSON form. Reading the guide, creating
/// the reservations and keeping the log live with the
/// providers (app/auto_record_providers.dart).
library;

import 'dart:convert';

import '../core/core.dart';
import 'epg_search.dart';

/// One standing auto record rule. The list's order is
/// the priority: earlier rules win conflicts.
class AutoRecordRule {
  const AutoRecordRule({
    required this.id,
    this.keyword = '',
    this.genreLevel1,
    this.enabled = true,
  });

  /// Stable identity across edits and reorders (a
  /// timestamp-based id minted by the editor).
  final String id;

  /// Keyword searched in the programme's own text
  /// (see [autoRecordRuleMatches] for the field set),
  /// matched case-insensitively. Empty means the rule
  /// does not filter by text.
  final String keyword;

  /// ARIB genre level-1 value, or null when the rule
  /// does not filter by genre.
  final int? genreLevel1;

  /// Off rules are kept but never planned.
  final bool enabled;

  /// Whether the rule can match anything at all: a
  /// rule with no keyword and no genre is unconfigured
  /// (see the library comment).
  bool get isConfigured => keyword.trim().isNotEmpty || genreLevel1 != null;

  AutoRecordRule copyWith({String? keyword, int? genreLevel1, bool? enabled}) {
    return AutoRecordRule(
      id: id,
      keyword: keyword ?? this.keyword,
      genreLevel1: genreLevel1 ?? this.genreLevel1,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'keyword': keyword,
    if (genreLevel1 != null) 'genre': genreLevel1,
    'enabled': enabled,
  };

  /// Parses one stored rule; null when the shape is
  /// not a rule this version wrote (a corrupt or
  /// foreign entry is dropped, never guessed at).
  static AutoRecordRule? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    if (id is! String || id.isEmpty) return null;
    final keyword = value['keyword'];
    final genre = value['genre'];
    final enabled = value['enabled'];
    return AutoRecordRule(
      id: id,
      keyword: keyword is String ? keyword : '',
      genreLevel1: genre is int ? genre : null,
      enabled: enabled is bool ? enabled : true,
    );
  }
}

/// The stored form of the rule list: a JSON array.
/// Decoding never throws — an unreadable store reads
/// as no rules, and entries that do not parse are
/// dropped one by one.
String encodeAutoRecordRules(List<AutoRecordRule> rules) =>
    jsonEncode([for (final rule in rules) rule.toJson()]);

List<AutoRecordRule> decodeAutoRecordRules(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  return [for (final entry in decoded) ?AutoRecordRule.fromJson(entry)];
}

/// Whether [rule] claims [event]: the genre must be
/// the event's when the rule names one, and the
/// keyword must appear in the programme's own text
/// when the rule names one. The text set is the
/// title, the outline (shortText), the programme
/// description, the cast and the remaining
/// extended-event text — the fields the search
/// screen indexes, minus the channel name, which is
/// not the programme's text. (Owner request
/// 2026-11-26: a keyword that appears only in the
/// outline or the description claims the programme
/// too, not just one in the title.)
bool autoRecordRuleMatches(AutoRecordRule rule, EpgEvent event) {
  if (!rule.isConfigured) return false;
  final genre = rule.genreLevel1;
  if (genre != null && event.genreLevel1 != genre) return false;
  final keyword = rule.keyword.trim().toLowerCase();
  if (keyword.isEmpty) return true;
  for (final text in _keywordTexts(event)) {
    if (text != null && text.toLowerCase().contains(keyword)) return true;
  }
  return false;
}

/// The programme texts a keyword is searched in (see
/// [autoRecordRuleMatches]).
Iterable<String?> _keywordTexts(EpgEvent event) sync* {
  yield event.title;
  yield event.shortText;
  yield event.description;
  yield event.cast;
  yield event.extendedText;
  for (final item in event.extendedItems) {
    yield item.value;
  }
}

/// Why a matched programme was not reserved.
enum AutoRecordSkipReason {
  /// A reservation for this programme is already on
  /// the unit (made by hand, by torne, or by an
  /// earlier check).
  alreadyReserved,

  /// The tuner is taken at that time — by a
  /// reservation already on the unit, or by a
  /// stronger rule's programme in the same check.
  conflict,
}

/// A programme the plan will reserve, under the rule
/// that claimed it.
class AutoRecordPlannedReservation {
  const AutoRecordPlannedReservation({
    required this.ruleIndex,
    required this.hit,
  });

  /// Index into the rule list the plan was given.
  final int ruleIndex;
  final EpgSearchHit hit;
}

/// A programme the plan leaves alone, and why.
class AutoRecordPlannedSkip {
  const AutoRecordPlannedSkip({
    required this.ruleIndex,
    required this.hit,
    required this.reason,
  });

  final int ruleIndex;
  final EpgSearchHit hit;
  final AutoRecordSkipReason reason;
}

/// The outcome of one planning pass.
class AutoRecordPlan {
  const AutoRecordPlan({required this.reservations, required this.skips});

  final List<AutoRecordPlannedReservation> reservations;
  final List<AutoRecordPlannedSkip> skips;
}

/// The identity of one programme across the guide,
/// the reservation list and runs: its channel and its
/// start. (The same event id can repeat across days
/// and services; channel + start cannot collide for
/// distinct programmes.)
String autoRecordProgrammeKey({
  required int broadcastingType,
  required int serviceId,
  required DateTime start,
}) => '$broadcastingType:$serviceId:${start.toIso8601String()}';

bool _overlaps(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) => aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// Plans one check: matches the enabled [rules] (in
/// priority order) against [hits] (the whole held
/// guide) and decides, against the reservations
/// already on the unit, what to reserve.
///
/// Only programmes starting after [now] are
/// candidates. A programme matched by several rules
/// is claimed by the strongest one. Planning walks
/// the rules from strongest to weakest, each rule's
/// programmes in start order, so the outcome is the
/// same whenever the same inputs meet.
AutoRecordPlan planAutoRecord({
  required List<AutoRecordRule> rules,
  required List<EpgSearchHit> hits,
  required List<RecordSchedule> existing,
  required DateTime now,
}) {
  final enabled = [
    for (var i = 0; i < rules.length; i++)
      if (rules[i].enabled) i,
  ];
  final busy = <({DateTime start, DateTime end})>[
    for (final s in existing) (start: s.start, end: s.end),
  ];
  final reservedKeys = <String>{
    for (final s in existing)
      autoRecordProgrammeKey(
        broadcastingType: s.channel.broadcastingType,
        serviceId: s.channel.serviceId,
        start: s.start,
      ),
  };

  // Claim each future programme for the strongest
  // rule that matches it.
  final claimed = <String, ({int ruleIndex, EpgSearchHit hit})>{};
  for (final hit in hits) {
    final event = hit.event;
    if (!event.start.isAfter(now)) continue;
    final key = autoRecordProgrammeKey(
      broadcastingType: hit.channel.broadcastingType,
      serviceId: hit.channel.serviceId,
      start: event.start,
    );
    if (claimed.containsKey(key)) continue;
    for (final ruleIndex in enabled) {
      if (autoRecordRuleMatches(rules[ruleIndex], event)) {
        claimed[key] = (ruleIndex: ruleIndex, hit: hit);
        break;
      }
    }
  }

  final reservations = <AutoRecordPlannedReservation>[];
  final skips = <AutoRecordPlannedSkip>[];
  for (final ruleIndex in enabled) {
    final mine = [
      for (final entry in claimed.values)
        if (entry.ruleIndex == ruleIndex) entry.hit,
    ]..sort((a, b) => a.event.start.compareTo(b.event.start));
    for (final hit in mine) {
      final event = hit.event;
      final key = autoRecordProgrammeKey(
        broadcastingType: hit.channel.broadcastingType,
        serviceId: hit.channel.serviceId,
        start: event.start,
      );
      if (reservedKeys.contains(key)) {
        skips.add(
          AutoRecordPlannedSkip(
            ruleIndex: ruleIndex,
            hit: hit,
            reason: AutoRecordSkipReason.alreadyReserved,
          ),
        );
        continue;
      }
      if (busy.any(
        (span) => _overlaps(event.start, event.end, span.start, span.end),
      )) {
        skips.add(
          AutoRecordPlannedSkip(
            ruleIndex: ruleIndex,
            hit: hit,
            reason: AutoRecordSkipReason.conflict,
          ),
        );
        continue;
      }
      reservations.add(
        AutoRecordPlannedReservation(ruleIndex: ruleIndex, hit: hit),
      );
      busy.add((start: event.start, end: event.end));
      reservedKeys.add(key);
    }
  }
  return AutoRecordPlan(reservations: reservations, skips: skips);
}
