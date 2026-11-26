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
import 'format.dart';

/// One channel a rule can be pinned to (owner
/// request 2026-11-27): the service triple that
/// identifies the channel in every band's guide, plus
/// the name the viewer picked it by. The triple is
/// the identity; the name is display only, kept so
/// the rule still reads in words if the channel later
/// leaves the guide.
class AutoRecordChannel {
  const AutoRecordChannel({
    required this.networkId,
    required this.transportStreamId,
    required this.serviceId,
    required this.name,
  });

  final int networkId;
  final int transportStreamId;
  final int serviceId;
  final String name;

  /// Whether [channel] is the channel this names.
  bool matches(Channel channel) =>
      channel.networkId == networkId &&
      channel.transportStreamId == transportStreamId &&
      channel.serviceId == serviceId;

  @override
  bool operator ==(Object other) =>
      other is AutoRecordChannel &&
      other.networkId == networkId &&
      other.transportStreamId == transportStreamId &&
      other.serviceId == serviceId;

  @override
  int get hashCode => Object.hash(networkId, transportStreamId, serviceId);

  Map<String, dynamic> toJson() => {
    'networkId': networkId,
    'transportStreamId': transportStreamId,
    'serviceId': serviceId,
    'name': name,
  };

  /// Parses a stored channel; null when the shape is
  /// not one this version wrote.
  static AutoRecordChannel? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final networkId = value['networkId'];
    final transportStreamId = value['transportStreamId'];
    final serviceId = value['serviceId'];
    if (networkId is! int || transportStreamId is! int || serviceId is! int) {
      return null;
    }
    final name = value['name'];
    return AutoRecordChannel(
      networkId: networkId,
      transportStreamId: transportStreamId,
      serviceId: serviceId,
      name: name is String ? name : '',
    );
  }
}

/// One standing auto record rule. The list's order is
/// the priority: earlier rules win conflicts.
class AutoRecordRule {
  const AutoRecordRule({
    required this.id,
    this.keyword = '',
    this.genreLevel1,
    this.channel,
    this.excludeKeywords = const [],
    this.startMinuteOfDay,
    this.endMinuteOfDay,
    this.onceOnly = false,
    this.qualityMode,
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

  /// The one channel the rule is pinned to, or null
  /// when it ranges over every channel. A filter on
  /// top of the keyword / genre conditions, never a
  /// condition of its own: a rule with only a channel
  /// is still unconfigured (see [isConfigured]).
  final AutoRecordChannel? channel;

  /// Exclusion keywords (owner request 2026-11-27):
  /// a programme whose own text — the same field set
  /// the keyword is searched in — contains any of
  /// these is vetoed, however well it fits the
  /// positive conditions. Blank entries never veto.
  final List<String> excludeKeywords;

  /// The time-of-day window (owner request
  /// 2026-11-27): minutes after midnight, JST wall
  /// clock, judged on the programme's start. Both
  /// bounds are set together or neither is; null
  /// means the rule ranges over the whole day. The
  /// window is half-open — the start bound counts,
  /// the end bound does not — and a start later than
  /// the end wraps past midnight (23:00–02:00). Equal
  /// bounds are an empty window that matches nothing
  /// (see [autoRecordStartInTimeRange]); the editor
  /// refuses to save them.
  final int? startMinuteOfDay;
  final int? endMinuteOfDay;

  /// Whether the rule names a time-of-day window.
  bool get hasTimeRange => startMinuteOfDay != null && endMinuteOfDay != null;

  /// One-shot mode (owner request 2026-11-27): false
  /// is the standing behaviour — the rule fires on
  /// every check, week after week. True makes the
  /// rule fire once: a check plans at most one
  /// reservation for it (see [planAutoRecord]), and
  /// when that reservation is actually created the
  /// checker switches the rule off and logs that it
  /// did. A check that creates nothing for the rule —
  /// every match a duplicate or a conflict — leaves
  /// it on to try again next time.
  final bool onceOnly;

  /// The recording quality the rule's reservations
  /// are created with (owner request 2026-11-27): an
  /// XSRS desiredQualityMode value, or null for no
  /// specification, which keeps the create model's
  /// own default (100 = DR) — the behaviour before
  /// the choice existed. Only the measured torne
  /// values are ever stored (100 = DR, 230 = 3倍,
  /// plan 28; see qualityModeLabel): the editor
  /// offers exactly those, and the stored form reads
  /// any other value as no specification, so an
  /// unmeasured mode never reaches the wire.
  final int? qualityMode;

  /// Off rules are kept but never planned.
  final bool enabled;

  /// Whether the rule can match anything at all: a
  /// rule with no keyword and no genre is unconfigured
  /// (see the library comment).
  bool get isConfigured => keyword.trim().isNotEmpty || genreLevel1 != null;

  AutoRecordRule copyWith({
    String? keyword,
    int? genreLevel1,
    AutoRecordChannel? channel,
    List<String>? excludeKeywords,
    int? startMinuteOfDay,
    int? endMinuteOfDay,
    bool? onceOnly,
    int? qualityMode,
    bool? enabled,
  }) {
    return AutoRecordRule(
      id: id,
      keyword: keyword ?? this.keyword,
      genreLevel1: genreLevel1 ?? this.genreLevel1,
      channel: channel ?? this.channel,
      excludeKeywords: excludeKeywords ?? this.excludeKeywords,
      startMinuteOfDay: startMinuteOfDay ?? this.startMinuteOfDay,
      endMinuteOfDay: endMinuteOfDay ?? this.endMinuteOfDay,
      onceOnly: onceOnly ?? this.onceOnly,
      qualityMode: qualityMode ?? this.qualityMode,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'keyword': keyword,
    if (genreLevel1 != null) 'genre': genreLevel1,
    if (channel != null) 'channel': channel!.toJson(),
    if (excludeKeywords.isNotEmpty) 'exclude': excludeKeywords,
    if (hasTimeRange) 'startMinute': startMinuteOfDay,
    if (hasTimeRange) 'endMinute': endMinuteOfDay,
    if (onceOnly) 'once': true,
    if (qualityMode != null) 'quality': qualityMode,
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
      // A stored channel that does not parse reads as
      // no channel, the same leniency the other fields
      // get; rules written before channels existed
      // simply have no 'channel' key.
      channel: AutoRecordChannel.fromJson(value['channel']),
      excludeKeywords: _parseExcludeKeywords(value['exclude']),
      startMinuteOfDay: _parseTimeRange(value)[0],
      endMinuteOfDay: _parseTimeRange(value)[1],
      // Rules stored before one-shot mode have no
      // 'once' key and read as the standing mode.
      onceOnly: value['once'] == true,
      qualityMode: _parseQualityMode(value['quality']),
      enabled: enabled is bool ? enabled : true,
    );
  }

  /// The stored recording quality: only the measured
  /// torne modes (100 = DR, 230 = 3倍, plan 28) are
  /// honoured; anything else — including rules stored
  /// before the choice existed — reads as no
  /// specification.
  static int? _parseQualityMode(Object? value) =>
      value is int && (value == 100 || value == 230) ? value : null;

  /// The stored time-of-day window as [start, end]:
  /// both bounds count only when both are stored as
  /// minutes after midnight (0–1439); anything else
  /// reads as no window.
  static List<int?> _parseTimeRange(Map<String, dynamic> value) {
    final start = value['startMinute'];
    final end = value['endMinute'];
    bool valid(Object? v) => v is int && v >= 0 && v < 24 * 60;
    if (valid(start) && valid(end)) return [start as int, end as int];
    return const [null, null];
  }

  /// The stored exclusion list: the string entries,
  /// trimmed, blanks and repeats dropped. Anything
  /// else reads as no exclusions.
  static List<String> _parseExcludeKeywords(Object? value) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final entry in value) {
      if (entry is! String) continue;
      final word = entry.trim();
      if (word.isNotEmpty && !out.contains(word)) out.add(word);
    }
    return out;
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

/// Whether a programme starting at [start] falls in
/// the time-of-day window [rangeStart]–[rangeEnd]
/// (minutes after midnight). The judgement is on the
/// JST wall clock — the clock every timestamp in the
/// app is rendered in (see format.dart) — not the
/// host's timezone. The window is half-open: a start
/// exactly at [rangeStart] is in, a start exactly at
/// [rangeEnd] is out, so adjacent windows never
/// double-claim a boundary programme. A start later
/// than the end wraps past midnight. Equal bounds
/// are an empty window: nothing is in it, rather
/// than the whole day — a stored rule can only get
/// there by corruption (the editor refuses to save
/// equal bounds), and matching nothing is the side
/// that never records unasked.
bool autoRecordStartInTimeRange(
  DateTime start,
  int rangeStart,
  int rangeEnd,
) {
  final wall = jstWallClock(start);
  final minute = wall.hour * 60 + wall.minute;
  if (rangeStart < rangeEnd) {
    return minute >= rangeStart && minute < rangeEnd;
  }
  if (rangeStart > rangeEnd) {
    return minute >= rangeStart || minute < rangeEnd;
  }
  return false;
}

/// Whether [rule] claims [event]: the programme must
/// be on the rule's channel when it names one (the
/// caller passes the event's [channel]; a pinned rule
/// never matches without one), the genre must be
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
bool autoRecordRuleMatches(AutoRecordRule rule, EpgEvent event, {Channel? channel}) {
  if (!rule.isConfigured) return false;
  final pinned = rule.channel;
  if (pinned != null && (channel == null || !pinned.matches(channel))) {
    return false;
  }
  final genre = rule.genreLevel1;
  if (genre != null && event.genreLevel1 != genre) return false;
  if (rule.hasTimeRange &&
      !autoRecordStartInTimeRange(
        event.start,
        rule.startMinuteOfDay!,
        rule.endMinuteOfDay!,
      )) {
    return false;
  }
  final keyword = rule.keyword.trim().toLowerCase();
  if (keyword.isNotEmpty) {
    var found = false;
    for (final text in _keywordTexts(event)) {
      if (text != null && text.toLowerCase().contains(keyword)) {
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  // The veto runs last: an exclusion word anywhere in
  // the programme's own text (the same field set as
  // the keyword's) rejects the programme however well
  // it fit the positive conditions above.
  for (final excluded in rule.excludeKeywords) {
    final needle = excluded.trim().toLowerCase();
    if (needle.isEmpty) continue;
    for (final text in _keywordTexts(event)) {
      if (text != null && text.toLowerCase().contains(needle)) return false;
    }
  }
  return true;
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
///
/// [externalReservedKeys] carries the programme keys
/// (see [autoRecordProgrammeKey]) already reserved
/// on OTHER units (owner request 2026-11-27, the
/// two-nasne check): such a programme is a duplicate
/// here too — reserved once across the household is
/// enough — but it does not occupy this unit's
/// tuner, so it never makes another programme a
/// conflict. With one unit the set stays empty and
/// the plan is exactly what it always was.
AutoRecordPlan planAutoRecord({
  required List<AutoRecordRule> rules,
  required List<EpgSearchHit> hits,
  required List<RecordSchedule> existing,
  required DateTime now,
  Set<String> externalReservedKeys = const {},
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
      if (autoRecordRuleMatches(rules[ruleIndex], event, channel: hit.channel)) {
        claimed[key] = (ruleIndex: ruleIndex, hit: hit);
        break;
      }
    }
  }

  final reservations = <AutoRecordPlannedReservation>[];
  final skips = <AutoRecordPlannedSkip>[];
  // One-shot rules that already hold this check's one
  // reservation; their remaining programmes are left
  // entirely alone (see the loop body).
  final onceSatisfied = <int>{};
  for (final ruleIndex in enabled) {
    final mine = [
      for (final entry in claimed.values)
        if (entry.ruleIndex == ruleIndex) entry.hit,
    ]..sort((a, b) => a.event.start.compareTo(b.event.start));
    for (final hit in mine) {
      // A one-shot rule reserves at most one programme
      // per check: its earliest claimed programme that
      // is neither a duplicate nor a conflict. Once it
      // holds that one, its later programmes produce
      // neither reservations nor skips — the rule is
      // about to switch off, and they never took the
      // tuner, so weaker rules still see a free one.
      if (rules[ruleIndex].onceOnly && onceSatisfied.contains(ruleIndex)) {
        continue;
      }
      final event = hit.event;
      final key = autoRecordProgrammeKey(
        broadcastingType: hit.channel.broadcastingType,
        serviceId: hit.channel.serviceId,
        start: event.start,
      );
      if (externalReservedKeys.contains(key)) {
        // Reserved on another unit: a duplicate for
        // this programme, but no tuner time is taken
        // here, so nothing is added to the busy spans.
        skips.add(
          AutoRecordPlannedSkip(
            ruleIndex: ruleIndex,
            hit: hit,
            reason: AutoRecordSkipReason.alreadyReserved,
          ),
        );
        continue;
      }
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
      if (rules[ruleIndex].onceOnly) onceSatisfied.add(ruleIndex);
      busy.add((start: event.start, end: event.end));
      reservedKeys.add(key);
    }
  }
  return AutoRecordPlan(reservations: reservations, skips: skips);
}
