/// Auto pick providers (user-fork addition): the
/// settings of the keyword-less auto recording and
/// the marks of the reservations it made, both
/// persisted in the key-value store.
///
/// Persistence follows the house rules (see
/// auto_record_providers.dart): every write is
/// awaited, the stored form is one JSON value per
/// key, and an unreadable value reads as the default
/// rather than failing — the feature must never take
/// the app down with it.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The auto pick's settings (owner request
/// 2026-11-27): whether it runs at all, the disk
/// floor under which it stops, and how many
/// programmes one check may add.
class AutoPickSettings {
  const AutoPickSettings({
    this.enabled = false,
    this.minFreeGb = defaultMinFreeGb,
    this.maxPerCheck = defaultMaxPerCheck,
  });

  /// Off unless the viewer turns it on: a feature
  /// that records unasked starts silent.
  final bool enabled;

  /// The disk floor, in GiB of free space: under
  /// this, the auto pick makes no reservations.
  ///
  /// The default, 20 GiB, is chosen to trip the
  /// guard well before the disk is actually full —
  /// it leaves the viewer room for several of their
  /// own recordings after the auto pick stops, on
  /// the smallest disk this fork is used with
  /// (250 GB) and on a 500 GB unit alike.
  static const defaultMinFreeGb = 20;
  final int minFreeGb;

  /// How many programmes one check may auto-reserve,
  /// per unit. The default, 3, is a handful: enough
  /// to be useful in one pass over an eight-day
  /// guide, never a flood.
  static const defaultMaxPerCheck = 3;
  final int maxPerCheck;

  int get minFreeBytes => minFreeGb * 1024 * 1024 * 1024;

  @override
  bool operator ==(Object other) =>
      other is AutoPickSettings &&
      other.enabled == enabled &&
      other.minFreeGb == minFreeGb &&
      other.maxPerCheck == maxPerCheck;

  @override
  int get hashCode => Object.hash(enabled, minFreeGb, maxPerCheck);

  AutoPickSettings copyWith({bool? enabled, int? minFreeGb, int? maxPerCheck}) {
    return AutoPickSettings(
      enabled: enabled ?? this.enabled,
      minFreeGb: minFreeGb ?? this.minFreeGb,
      maxPerCheck: maxPerCheck ?? this.maxPerCheck,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'minFreeGb': minFreeGb,
    'maxPerCheck': maxPerCheck,
  };

  /// Parses the stored settings; anything missing or
  /// out of range falls back to that field's default,
  /// so a stored value from another version can never
  /// switch the feature on or widen it by accident.
  static AutoPickSettings fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const AutoPickSettings();
    final minFreeGb = value['minFreeGb'];
    final maxPerCheck = value['maxPerCheck'];
    return AutoPickSettings(
      enabled: value['enabled'] == true,
      minFreeGb: minFreeGb is int && minFreeGb >= 1 && minFreeGb <= 500
          ? minFreeGb
          : defaultMinFreeGb,
      maxPerCheck: maxPerCheck is int && maxPerCheck >= 1 && maxPerCheck <= 20
          ? maxPerCheck
          : defaultMaxPerCheck,
    );
  }
}

String encodeAutoPickSettings(AutoPickSettings settings) =>
    jsonEncode(settings.toJson());

AutoPickSettings decodeAutoPickSettings(String? stored) {
  if (stored == null || stored.isEmpty) return const AutoPickSettings();
  try {
    return AutoPickSettings.fromJson(jsonDecode(stored));
  } on FormatException {
    return const AutoPickSettings();
  }
}

/// The auto pick settings, persisted as one JSON
/// value under [AutoPickSettingsNotifier._key].
class AutoPickSettingsNotifier extends Notifier<AutoPickSettings> {
  static const _key = 'auto_pick_settings';

  /// The initial read-back, awaited by callers that
  /// must not run against settings that have not
  /// landed yet (the startup check above all — see
  /// AutoRecordRulesNotifier for the race this
  /// guards against).
  Future<void>? _load;

  /// Whether the viewer has already saved over the
  /// initial value; a late load must not clobber it.
  bool _touched = false;

  @override
  AutoPickSettings build() {
    final store = ref.watch(keyValueStoreProvider);
    _load = Future.microtask(() async {
      final settings = decodeAutoPickSettings(await store.read(_key));
      if (!_touched) state = settings;
    });
    return const AutoPickSettings();
  }

  /// The settings in effect once the initial load
  /// has landed.
  Future<AutoPickSettings> settingsWhenLoaded() async {
    await _load;
    return state;
  }

  Future<void> _save(AutoPickSettings settings) async {
    _touched = true;
    state = settings;
    await ref
        .read(keyValueStoreProvider)
        .write(_key, encodeAutoPickSettings(settings));
  }

  Future<void> setEnabled(bool enabled) =>
      _save(state.copyWith(enabled: enabled));

  Future<void> setMinFreeGb(int gb) => _save(state.copyWith(minFreeGb: gb));

  Future<void> setMaxPerCheck(int count) =>
      _save(state.copyWith(maxPerCheck: count));
}

final autoPickSettingsProvider =
    NotifierProvider<AutoPickSettingsNotifier, AutoPickSettings>(
      AutoPickSettingsNotifier.new,
    );

/// The stored form of the auto pick marks: a JSON
/// object from a unit's host to the programme keys
/// (see autoRecordProgrammeKey) the auto pick
/// reserved on it, oldest first.
String encodeAutoPickMarks(Map<String, Set<String>> marks) => jsonEncode({
  for (final entry in marks.entries) entry.key: entry.value.toList(),
});

Map<String, Set<String>> decodeAutoPickMarks(String? stored) {
  if (stored == null || stored.isEmpty) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, dynamic>) return const {};
  return {
    for (final entry in decoded.entries)
      if (entry.value is List)
        entry.key: {
          for (final key in entry.value as List)
            if (key is String) key,
        },
  };
}

/// Which reservations the auto pick made, per unit:
/// the programme keys it created, kept so the
/// reservation list and the candidate list can mark
/// them as the app's own doing rather than the
/// viewer's. A mark whose reservation the viewer has
/// since deleted simply never matches again; the
/// store is capped per unit so it cannot grow
/// without bound. Marks are never used to delete or
/// alter anything — display only.
class AutoPickMarksNotifier extends Notifier<Map<String, Set<String>>> {
  static const _key = 'auto_pick_marks';
  static const _capPerHost = 300;

  Future<void>? _load;

  @override
  Map<String, Set<String>> build() {
    final store = ref.watch(keyValueStoreProvider);
    _load = Future.microtask(() async {
      final marks = decodeAutoPickMarks(await store.read(_key));
      if (marks.isNotEmpty && state.isEmpty) state = marks;
    });
    return const {};
  }

  /// The marks in effect once the initial load has
  /// landed.
  Future<Map<String, Set<String>>> marksWhenLoaded() async {
    await _load;
    return state;
  }

  /// The programme keys marked for [host] (empty when
  /// the unit has none, or the load has not landed).
  Set<String> keysFor(String host) => state[host] ?? const {};

  Future<void> addKeys(String host, Iterable<String> keys) async {
    final added = keys.toList();
    if (added.isEmpty) return;
    final current = state[host] ?? const <String>{};
    final merged = [...current, ...added.where((k) => !current.contains(k))];
    final capped = merged.length > _capPerHost
        ? merged.sublist(merged.length - _capPerHost)
        : merged;
    final next = {...state, host: capped.toSet()};
    state = next;
    await ref
        .read(keyValueStoreProvider)
        .write(_key, encodeAutoPickMarks(next));
  }
}

final autoPickMarksProvider =
    NotifierProvider<AutoPickMarksNotifier, Map<String, Set<String>>>(
      AutoPickMarksNotifier.new,
    );
