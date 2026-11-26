/// Auto record providers (user-fork addition): the
/// rule list and the check log, persisted in the
/// key-value store, and the checker that runs the
/// plan against every registered nasne.
///
/// Persistence follows the house rules: every write
/// is awaited, the stored form is one JSON value per
/// key, and an unreadable value reads as empty rather
/// than failing — the feature must never take the app
/// down with it.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../ui/auto_record_policy.dart';
import '../ui/epg_genre.dart';
import '../ui/epg_search.dart';
import '../ui/format.dart';
import 'bs_epg_providers.dart';
import 'cs_epg_providers.dart';
import 'providers.dart';
import 'state.dart';

/// The viewer's auto record rules, in priority order
/// (see ui/auto_record_policy.dart). Persisted as one
/// JSON array under [AutoRecordRulesNotifier._key].
class AutoRecordRulesNotifier extends Notifier<List<AutoRecordRule>> {
  static const _key = 'auto_record_rules';

  /// The initial read-back of the persisted rules.
  /// [build] cannot await, so the load lands in state
  /// a moment after the provider is first read; a
  /// caller that must not plan against a list that
  /// has not landed yet — the startup check above
  /// all, which fires in the same breath as this
  /// provider's first read — awaits [rulesWhenLoaded]
  /// instead of reading state early and finding no
  /// rules at all.
  Future<void>? _load;

  @override
  List<AutoRecordRule> build() {
    final store = ref.watch(keyValueStoreProvider);
    _load = Future.microtask(() async {
      final rules = decodeAutoRecordRules(await store.read(_key));
      if (rules.isNotEmpty && state.isEmpty) state = rules;
    });
    return const [];
  }

  /// The rules in effect once the initial load has
  /// landed: the persisted list, or whatever the
  /// viewer has already put in its place.
  Future<List<AutoRecordRule>> rulesWhenLoaded() async {
    await _load;
    return state;
  }

  Future<void> _save(List<AutoRecordRule> rules) async {
    state = rules;
    await ref
        .read(keyValueStoreProvider)
        .write(_key, encodeAutoRecordRules(rules));
  }

  Future<void> add(AutoRecordRule rule) => _save([...state, rule]);

  Future<void> update(AutoRecordRule rule) => _save([
    for (final r in state)
      if (r.id == rule.id) rule else r,
  ]);

  Future<void> remove(String id) => _save([
    for (final r in state)
      if (r.id != id) r,
  ]);

  Future<void> setEnabled(String id, bool enabled) => _save([
    for (final r in state)
      if (r.id == id) r.copyWith(enabled: enabled) else r,
  ]);

  /// Moves the rule at [oldIndex] to [newIndex], the
  /// reorderable list's adjusted-index convention
  /// (onReorderItem: the target already accounts for
  /// the moved item leaving its old place).
  Future<void> reorder(int oldIndex, int newIndex) {
    final rules = [...state];
    rules.insert(newIndex, rules.removeAt(oldIndex));
    return _save(rules);
  }
}

final autoRecordRulesProvider =
    NotifierProvider<AutoRecordRulesNotifier, List<AutoRecordRule>>(
      AutoRecordRulesNotifier.new,
    );

/// What one logged check outcome was about.
enum AutoRecordLogKind { reserved, conflict, error, ruleDisabled }

/// One line of the check log: what a check did (or
/// failed to do) about one programme on one unit.
class AutoRecordLogEntry {
  const AutoRecordLogEntry({
    required this.at,
    required this.regName,
    required this.kind,
    required this.title,
    required this.channelName,
    required this.start,
    required this.ruleText,
  });

  final DateTime at;
  final String regName;
  final AutoRecordLogKind kind;

  /// Programme title ('' when the event carried none).
  final String title;
  final String channelName;
  final DateTime start;

  /// The rule that claimed the programme, in words
  /// ('' for an error not tied to a programme).
  final String ruleText;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'reg': regName,
    'kind': kind.name,
    'title': title,
    'channel': channelName,
    'start': start.toIso8601String(),
    'rule': ruleText,
  };

  static AutoRecordLogEntry? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final at = DateTime.tryParse(value['at'] as String? ?? '');
    final start = DateTime.tryParse(value['start'] as String? ?? '');
    final kindName = value['kind'];
    if (at == null || start == null || kindName is! String) return null;
    final kind = AutoRecordLogKind.values.asNameMap()[kindName];
    if (kind == null) return null;
    return AutoRecordLogEntry(
      at: at,
      regName: value['reg'] as String? ?? '',
      kind: kind,
      title: value['title'] as String? ?? '',
      channelName: value['channel'] as String? ?? '',
      start: start,
      ruleText: value['rule'] as String? ?? '',
    );
  }
}

/// The newest-first check log, capped so a season of
/// checks cannot grow the store without bound.
class AutoRecordLogNotifier extends Notifier<List<AutoRecordLogEntry>> {
  static const _key = 'auto_record_log';
  static const _cap = 100;

  @override
  List<AutoRecordLogEntry> build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final stored = await store.read(_key);
      if (stored == null || stored.isEmpty || state.isNotEmpty) return;
      try {
        final decoded = jsonDecode(stored);
        if (decoded is List) {
          state = [
            for (final entry in decoded) ?AutoRecordLogEntry.fromJson(entry),
          ];
        }
      } on FormatException {
        // An unreadable log reads as an empty log.
      }
    });
    return const [];
  }

  Future<void> addEntries(List<AutoRecordLogEntry> entries) async {
    if (entries.isEmpty) return;
    final next = [...entries.reversed, ...state].take(_cap).toList();
    state = next;
    await ref
        .read(keyValueStoreProvider)
        .write(_key, jsonEncode([for (final e in next) e.toJson()]));
  }
}

final autoRecordLogProvider =
    NotifierProvider<AutoRecordLogNotifier, List<AutoRecordLogEntry>>(
      AutoRecordLogNotifier.new,
    );

/// The tallies of one check run, for the rules
/// screen's report.
class AutoRecordRunSummary {
  const AutoRecordRunSummary({
    this.reserved = 0,
    this.conflicts = 0,
    this.errors = 0,
  });

  final int reserved;
  final int conflicts;
  final int errors;

  bool get didAnything => reserved > 0 || conflicts > 0 || errors > 0;
}

/// A minute-of-day as `H:MM`, for the rule text's
/// time-of-day window.
String _minuteOfDayLabel(int minute) =>
    '${minute ~/ 60}:${(minute % 60).toString().padLeft(2, '0')}';

/// The rule text's weekday set, in week order:
/// `金` on its own, `月水金` together.
String _weekdaysLabel(Set<int> weekdays) => [
  for (var day = 1; day <= 7; day++)
    if (weekdays.contains(day)) '月火水木金土日'[day - 1],
].join();

/// A rule in words, for the log and the rules list:
/// the positive conditions first, then the channel,
/// the exclusions, the time-of-day window, the
/// weekday set and the one-shot mode, so a stored
/// rule reads in full.
String autoRecordRuleText(AutoRecordRule rule) {
  final parts = [
    if (rule.keyword.trim().isNotEmpty) 'キーワード「${rule.keyword.trim()}」',
    if (rule.genreLevel1 != null)
      'ジャンル「${epgGenreLabel(rule.genreLevel1) ?? rule.genreLevel1}」',
    if (rule.channel != null) 'チャンネル「${rule.channel!.name}」',
    for (final word in rule.excludeKeywords) '除外「$word」',
    if (rule.hasTimeRange)
      '時間帯「${_minuteOfDayLabel(rule.startMinuteOfDay!)}'
          '〜${_minuteOfDayLabel(rule.endMinuteOfDay!)}」',
    if (rule.hasWeekdays) '曜日「${_weekdaysLabel(rule.weekdays)}」',
    if (rule.onceOnly) '1回だけ',
    if (rule.qualityMode != null) '画質「${qualityModeLabel(rule.qualityMode!)}」',
  ];
  return parts.isEmpty ? '条件なし' : parts.join('・');
}

/// Runs one auto record check (user-fork addition):
/// for every registered nasne — one at a time, in
/// registration order — plan the enabled rules
/// against the held guide and the unit's reservations,
/// then create what the plan reserved. With two
/// units, a programme reserved on one is a duplicate
/// on the other, never a second reservation; conflict
/// judgement stays per unit (see [AutoRecordChecker.run]).
///
/// The device stays the source of truth: each planned
/// reservation is conflict-checked against the unit
/// once more before it is created, so a reservation
/// made by another client between the plan and the
/// create is honoured, not overridden. Failures land
/// in the log and the summary, never in the caller's
/// face — a startup check must not break startup.
class AutoRecordChecker {
  AutoRecordChecker(this._ref);

  final Ref _ref;
  bool _running = false;

  Future<AutoRecordRunSummary> run() async {
    if (_running) return const AutoRecordRunSummary();
    // The persisted rules land asynchronously after
    // the provider's first read (see
    // AutoRecordRulesNotifier): reading state here
    // without waiting made the startup check — which
    // runs in the same breath — always find no rules
    // and reserve nothing, however many matches the
    // guide held.
    final rules = await _ref
        .read(autoRecordRulesProvider.notifier)
        .rulesWhenLoaded();
    if (!rules.any((r) => r.enabled && r.isConfigured)) {
      return const AutoRecordRunSummary();
    }
    _running = true;
    var reserved = 0;
    var conflicts = 0;
    var errors = 0;
    final logEntries = <AutoRecordLogEntry>[];
    // The units are checked one at a time, in
    // registration order (owner request 2026-11-27):
    // a programme reserved on an earlier unit — before
    // the check or by it — is a duplicate on the later
    // ones, never a second reservation, while the
    // earlier unit's tuner time is not a conflict
    // there, so a same-time different programme can
    // still land on the second unit. [workingRules]
    // is the rule list as the check leaves it: a
    // one-shot rule an earlier unit fired is already
    // off for the later ones.
    var workingRules = rules;
    final crossUnitKeys = <String>{};
    try {
      final registrations = await _ref.read(registrationsProvider.future);
      for (final reg in registrations) {
        final outcome = await _runForUnit(
          reg,
          workingRules,
          logEntries,
          crossUnitKeys,
        );
        reserved += outcome.reserved;
        conflicts += outcome.conflicts;
        errors += outcome.errors;
        crossUnitKeys.addAll(outcome.reservedKeys);
        if (outcome.spentOnceRuleIds.isNotEmpty) {
          final notifier = _ref.read(autoRecordRulesProvider.notifier);
          for (final id in outcome.spentOnceRuleIds) {
            await notifier.setEnabled(id, false);
          }
          final spent = outcome.spentOnceRuleIds.toSet();
          workingRules = [
            for (final rule in workingRules)
              spent.contains(rule.id) ? rule.copyWith(enabled: false) : rule,
          ];
        }
      }
    } catch (_) {
      errors++;
    } finally {
      _running = false;
    }
    await _ref.read(autoRecordLogProvider.notifier).addEntries(logEntries);
    return AutoRecordRunSummary(
      reserved: reserved,
      conflicts: conflicts,
      errors: errors,
    );
  }

  /// The outcome of one unit's check: the tallies,
  /// the programme keys this unit holds reserved
  /// afterwards (its own list plus what this check
  /// created — the next unit's duplicate set), and
  /// the one-shot rules this unit fired (the caller
  /// switches them off before the next unit's turn).
  Future<
    ({
      int reserved,
      int conflicts,
      int errors,
      Set<String> reservedKeys,
      List<String> spentOnceRuleIds,
    })
  >
  _runForUnit(
    RegisteredNasne reg,
    List<AutoRecordRule> rules,
    List<AutoRecordLogEntry> logEntries,
    Set<String> externalReservedKeys,
  ) async {
    var reserved = 0;
    var conflicts = 0;
    var errors = 0;
    final spentOnceRuleIds = <String>[];
    final now = DateTime.now();

    void log(AutoRecordLogKind kind, EpgSearchHit? hit, AutoRecordRule? rule) {
      logEntries.add(
        AutoRecordLogEntry(
          at: now,
          regName: reg.friendlyName,
          kind: kind,
          title: hit?.event.title ?? '',
          channelName: hit?.channelName ?? '',
          start: hit?.event.start ?? now,
          ruleText: rule == null ? '' : autoRecordRuleText(rule),
        ),
      );
    }

    final hits = <EpgSearchHit>[];
    for (final provider in [
      epgGuideProvider(reg),
      bsEpgGuideProvider(reg),
      csEpgGuideProvider(reg),
    ]) {
      try {
        final guide = await _ref.read(provider.future);
        for (final service in guide.services) {
          for (final event in service.events) {
            hits.add(EpgSearchHit(service: service, event: event));
          }
        }
      } catch (_) {
        // One band's guide failing must not sink the
        // other band's check.
      }
    }
    if (hits.isEmpty) {
      return (
        reserved: 0,
        conflicts: 0,
        errors: 0,
        reservedKeys: <String>{},
        spentOnceRuleIds: const <String>[],
      );
    }

    final List<RecordSchedule> existing;
    try {
      existing = await _ref.read(schedulesProvider(reg).future);
    } catch (_) {
      log(AutoRecordLogKind.error, null, null);
      return (
        reserved: 0,
        conflicts: 0,
        errors: 1,
        reservedKeys: <String>{},
        spentOnceRuleIds: const <String>[],
      );
    }
    final unitKeys = <String>{
      for (final s in existing)
        autoRecordProgrammeKey(
          broadcastingType: s.channel.broadcastingType,
          serviceId: s.channel.serviceId,
          start: s.start,
        ),
    };

    final plan = planAutoRecord(
      rules: rules,
      hits: hits,
      existing: existing,
      now: now,
      externalReservedKeys: externalReservedKeys,
    );
    conflicts += plan.skips
        .where((s) => s.reason == AutoRecordSkipReason.conflict)
        .length;
    for (final skip in plan.skips) {
      if (skip.reason == AutoRecordSkipReason.conflict) {
        log(AutoRecordLogKind.conflict, skip.hit, rules[skip.ruleIndex]);
      }
    }

    final services = _ref.read(deviceServicesProvider(reg));
    var createdAny = false;
    for (final action in plan.reservations) {
      final hit = action.hit;
      final event = hit.event;
      final channel = hit.channel;
      final rule = rules[action.ruleIndex];
      final candidate = NewRecordSchedule(
        start: event.start,
        durationSeconds: event.duration.inSeconds,
        channel: ScheduleChannel(
          broadcastingType: channel.broadcastingType,
          channelType: channel.broadcastingType,
          serviceId: channel.serviceId,
        ),
        networkId: channel.networkId,
        eventId: event.eventId,
        // The rule's quality choice, when it makes
        // one; no specification keeps the create
        // model's own default (100 = DR), as before
        // the choice existed.
        desiredQualityMode: rule.qualityMode ?? 100,
      );
      try {
        final deviceConflicts = await services.schedules.checkConflicts(
          candidate,
        );
        if (deviceConflicts.isNotEmpty) {
          conflicts++;
          log(AutoRecordLogKind.conflict, hit, rules[action.ruleIndex]);
          continue;
        }
        await services.schedules.createSchedule(candidate);
        createdAny = true;
        reserved++;
        unitKeys.add(
          autoRecordProgrammeKey(
            broadcastingType: channel.broadcastingType,
            serviceId: channel.serviceId,
            start: event.start,
          ),
        );
        log(AutoRecordLogKind.reserved, hit, rules[action.ruleIndex]);
        // A one-shot rule that just fired is spent:
        // the caller switches it off (and logs say it
        // happened, on the programme that spent it).
        if (rule.onceOnly && !spentOnceRuleIds.contains(rule.id)) {
          spentOnceRuleIds.add(rule.id);
          log(AutoRecordLogKind.ruleDisabled, hit, rule);
        }
      } catch (_) {
        errors++;
        log(AutoRecordLogKind.error, hit, rules[action.ruleIndex]);
      }
    }
    if (createdAny) _ref.invalidate(schedulesProvider(reg));
    return (
      reserved: reserved,
      conflicts: conflicts,
      errors: errors,
      reservedKeys: unitKeys,
      spentOnceRuleIds: spentOnceRuleIds,
    );
  }
}

final autoRecordCheckerProvider = Provider<AutoRecordChecker>(
  (ref) => AutoRecordChecker(ref),
);

/// Fires one check shortly after the app starts
/// (watched by the app shell). A provider body runs
/// once per app session, which is exactly the startup
/// check's cadence; the work is fire-and-forget and
/// swallows its own failures (see AutoRecordChecker).
final autoRecordStartupProvider = Provider<void>((ref) {
  Future.microtask(() async {
    try {
      await ref.read(autoRecordCheckerProvider).run();
    } catch (_) {
      // A startup check must never break startup.
    }
  });
});
