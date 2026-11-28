/// Composition root (plan 12.2 / 12.7): Riverpod providers that wire
/// the domain interfaces to their transport implementations. UI and
/// tests depend on the interfaces only; swapping an implementation
/// (e.g. a mock in tests, or a future transport for a newly
/// discovered path) is an override here, never a UI change.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/core.dart';
import '../ui/epg_zoom_policy.dart';
import '../ui/player_hwdec_policy.dart';
import 'ake_socket.dart';
import 'credential_downloads.dart';
import 'debug_log.dart';
import 'external_browser.dart';
import 'file_pick.dart';
import 'log_export.dart';
import 'log_folder.dart';
import 'log_share.dart';
import 'multicast_lock.dart';
import 'variant.dart';
import 'wakelock.dart';

final httpClientProvider = Provider<http.Client>((ref) => http.Client());

/// The device's Android SDK int (plan 139), read from the
/// platform side once at startup (app/android_sdk.dart) and
/// handed in as an override by the bootstrap; null — not
/// Android, or the platform did not answer — in tests and
/// headless contexts. The player screen branches the mpv
/// initialization on it (app/mpv_compat.dart).
final androidSdkIntProvider = Provider<int?>((ref) => null);

/// Sleep suppression for the player screen (plan 32, reworked in
/// plan 35): a hand-rolled platform channel flips the OS switch
/// and reads it back, so the debug log shows whether the setting
/// actually stuck.
final wakelockGuardProvider = Provider<WakelockGuard>(
  (ref) => NativeWakelockGuard(),
);

/// The single app-wide wakelock coordinator (plan 35): player
/// screens open sessions on it, and the OS lock is held while
/// any session is playing — one screen ending can no longer drop
/// the lock from under another that is still playing (the
/// build-13 field log showed exactly that).
final playbackWakelockProvider = Provider<PlaybackWakelock>(
  (ref) => PlaybackWakelock(
    guard: ref.watch(wakelockGuardProvider),
    diag: ref.watch(diagLogProvider),
  ),
);

/// Discovery chain (plan 16.3): SSDP and the unicast subnet
/// scan both run and their results are merged — a device that
/// stays silent on SSDP (measured: Buffalo NS-N100) is missed
/// if the scan only runs when SSDP finds nothing. Manual
/// registration stays available in the settings screen
/// regardless. On Android the SSDP step holds a
/// WifiManager.MulticastLock while searching (plan 17).
final discoveryServiceProvider = Provider<DiscoveryService>(
  (ref) => CompositeDiscoveryService([
    SsdpDiscoveryService(
      client: ref.watch(httpClientProvider),
      lockGuard: MethodChannelMulticastLockGuard(),
    ),
    SubnetScanDiscoveryService(client: ref.watch(httpClientProvider)),
  ]),
);

final registrationServiceProvider = Provider<RegistrationService>(
  (ref) => WebApiRegistrationService(client: ref.watch(httpClientProvider)),
);

/// Defaults to in-memory; the app entry point overrides this with a
/// file-backed store in the documents directory (app/bootstrap.dart).
final registrationStoreProvider = Provider<RegistrationStore>(
  (ref) => InMemoryRegistrationStore(),
);

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => InMemoryKeyValueStore(),
);

/// The key-value store behind the channel cache. Caches live in
/// their own files, away from the settings file: they are
/// rewritten on every fetch while settings are near-fixed, and
/// the standing rule is that writers of different volatility
/// never share a file (plan 96). Defaults to in-memory; the app
/// entry point overrides it (app/bootstrap.dart).
final channelCacheStoreProvider = Provider<KeyValueStore>(
  (ref) => InMemoryKeyValueStore(),
);

final channelCacheProvider = Provider<ChannelCache>(
  (ref) => ChannelCache(ref.watch(channelCacheStoreProvider)),
);

/// The key-value store behind the programme-guide accumulation
/// cache — its own file again (plan 96). The guide is by far the
/// largest value in the app and is rewritten on every guide
/// fetch, so it shares a file with nothing else.
final epgGuideCacheStoreProvider = Provider<KeyValueStore>(
  (ref) => InMemoryKeyValueStore(),
);

/// The DTCP-IP credential vault (Phase 5, plan 26.4). The pair
/// itself is read only by the playback engine; the UI uses the
/// summary provider below.
final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => SecureCredentialStore(),
);

/// The key-value store behind [srmStoreProvider]. The SRM is
/// DTCP protocol state (a revocation list) rewritten during AKE,
/// so it lives in its own file, away from both the settings file
/// and the caches (plan 96). Defaults to in-memory; the app
/// entry point overrides it (app/bootstrap.dart).
final srmKeyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => InMemoryKeyValueStore(),
);

/// SRM persistence: signed public data in its own key-value
/// store (plan 26.4; split out in plan 96).
final srmStoreProvider = Provider<KeyValueSrmStore>(
  (ref) => KeyValueSrmStore(ref.watch(srmKeyValueStoreProvider)),
);

/// Non-sensitive facts about the imported pair for the settings UI
/// (presence, device ID, certificate fingerprint). Invalidated
/// after import / delete.
final credentialSummaryProvider = FutureProvider<CredentialSummary?>((
  ref,
) async {
  final credentials = await ref.watch(credentialStoreProvider).load();
  return credentials == null ? null : CredentialSummary.of(credentials);
});

/// Whether the programme guide shows subchannels (plan 25;
/// default off), persisted in the key-value store.
class ShowSubchannelsNotifier extends Notifier<bool> {
  static const _key = 'epg_show_subchannels';

  @override
  bool build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final value = await store.read(_key);
      if (value != null && value == 'true' && !state) state = true;
    });
    return false;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(keyValueStoreProvider).write(_key, value ? 'true' : 'false');
  }
}

final showSubchannelsProvider = NotifierProvider<ShowSubchannelsNotifier, bool>(
  ShowSubchannelsNotifier.new,
);

/// CM auto skip for recorded playback (user-fork
/// addition): while a recording plays, move past the
/// chapter segments that look like commercial breaks
/// without the viewer pressing the chapter buttons
/// (see ui/player_cm_autoskip_policy.dart for the
/// classification and its limits). Off unless the
/// viewer turns it on; persisted in the key-value
/// store. The player screen snapshots the value as it
/// opens, so a change applies from the next playback.
class CmAutoSkipNotifier extends Notifier<bool> {
  static const _key = 'cm_auto_skip_enabled';

  @override
  bool build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final value = await store.read(_key);
      if (value != null && value == 'true' && !state) state = true;
    });
    return false;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(keyValueStoreProvider).write(_key, value ? 'true' : 'false');
  }
}

final cmAutoSkipProvider = NotifierProvider<CmAutoSkipNotifier, bool>(
  CmAutoSkipNotifier.new,
);

/// Programme-guide genres the viewer does not watch
/// (Discord request, 2026-11-21): events of these genres
/// paint blank in the guide grid, so the guide only draws
/// the eye to programmes of genres the viewer cares about.
/// Persisted in the key-value store as the comma-separated
/// ARIB level-1 values.
class HiddenEpgGenresNotifier extends Notifier<Set<int>> {
  static const _key = 'epg_hidden_genres';

  @override
  Set<int> build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final restored = decode(await store.read(_key));
      if (restored.isNotEmpty && state.isEmpty) state = restored;
    });
    return const {};
  }

  /// The stored form: comma-separated level-1 values.
  /// Anything unparsable is dropped, never fatal.
  static Set<int> decode(String? raw) {
    final values = <int>{};
    for (final part in (raw ?? '').split(',')) {
      final value = int.tryParse(part.trim());
      if (value != null) values.add(value);
    }
    return values;
  }

  Future<void> setHidden(int genreLevel1, bool hidden) async {
    final next = {...state};
    if (hidden) {
      next.add(genreLevel1);
    } else {
      next.remove(genreLevel1);
    }
    state = next;
    final sorted = next.toList()..sort();
    await ref.read(keyValueStoreProvider).write(_key, sorted.join(','));
  }
}

final hiddenEpgGenresProvider =
    NotifierProvider<HiddenEpgGenresNotifier, Set<int>>(
      HiddenEpgGenresNotifier.new,
    );

/// Channels the viewer does not watch (owner request
/// 2026-11-26): a hidden channel drops out of the TV視聴
/// live list and the programme guide alike (the filter
/// itself is ui/channel_visibility.dart). Persisted in the
/// key-value store as the comma-separated channel keys —
/// the (networkId, transportStreamId, serviceId) triple in
/// the stored form ui/channel_visibility.dart defines. The
/// choice is app-wide, not per device: the triple names a
/// broadcast service, the same service on every unit in the
/// area.
class HiddenChannelsNotifier extends Notifier<Set<String>> {
  static const _key = 'hidden_channels';

  /// The initial read-back of the persisted choice.
  /// [build] cannot await, so the restore lands a moment
  /// after the provider is first read; every mutation
  /// awaits it before applying, so a restore that lands
  /// late can never resurrect a choice a mutation — above
  /// all a reset — has already replaced (the lost-update
  /// shape the store's data rules exist to prevent).
  Future<void>? _load;

  @override
  Set<String> build() {
    final store = ref.watch(keyValueStoreProvider);
    _load = Future.microtask(() async {
      final restored = decode(await store.read(_key));
      if (restored.isNotEmpty && state.isEmpty) state = restored;
    });
    return const {};
  }

  /// The stored form: comma-separated channel keys.
  /// Anything that is not a three-part numeric triple is
  /// dropped, never fatal.
  static Set<String> decode(String? raw) {
    final keys = <String>{};
    for (final part in (raw ?? '').split(',')) {
      final trimmed = part.trim();
      final fields = trimmed.split(':');
      if (fields.length != 3) continue;
      if (fields.every((f) => int.tryParse(f) != null)) keys.add(trimmed);
    }
    return keys;
  }

  Future<void> _persist(Set<String> keys) async {
    final sorted = keys.toList()..sort();
    await ref.read(keyValueStoreProvider).write(_key, sorted.join(','));
  }

  Future<void> setHidden(String channelKey, bool hidden) async {
    await _load;
    final next = {...state};
    if (hidden) {
      next.add(channelKey);
    } else {
      next.remove(channelKey);
    }
    state = next;
    await _persist(next);
  }

  /// Shows every channel again (the settings page's reset).
  Future<void> reset() async {
    await _load;
    state = const {};
    await _persist(const {});
  }
}

final hiddenChannelsProvider =
    NotifierProvider<HiddenChannelsNotifier, Set<String>>(
      HiddenChannelsNotifier.new,
    );

/// Channels the viewer pinned as favourites (owner request
/// 2026-11-26): the TV視聴 screen's ピン留め tab lists them
/// across every band (the filter itself is
/// ui/channel_pins.dart). Persisted and keyed exactly like
/// the not-watched choice above — the same
/// (networkId, transportStreamId, serviceId) triple in the
/// same stored form, app-wide rather than per device: the
/// triple names a broadcast service, the same service on
/// every unit in the area.
class PinnedChannelsNotifier extends Notifier<Set<String>> {
  static const _key = 'pinned_channels';

  /// The initial read-back of the persisted choice, with
  /// the same lost-update guard as the not-watched choice:
  /// every mutation awaits it before applying, so a restore
  /// that lands late can never resurrect a choice a
  /// mutation has already replaced.
  Future<void>? _load;

  @override
  Set<String> build() {
    final store = ref.watch(keyValueStoreProvider);
    _load = Future.microtask(() async {
      final restored = decode(await store.read(_key));
      if (restored.isNotEmpty && state.isEmpty) state = restored;
    });
    return const {};
  }

  /// The stored form: comma-separated channel keys, the
  /// same three-part numeric triples the not-watched
  /// choice stores (ui/channel_visibility.dart defines the
  /// key). Anything else is dropped, never fatal.
  static Set<String> decode(String? raw) {
    final keys = <String>{};
    for (final part in (raw ?? '').split(',')) {
      final trimmed = part.trim();
      final fields = trimmed.split(':');
      if (fields.length != 3) continue;
      if (fields.every((f) => int.tryParse(f) != null)) keys.add(trimmed);
    }
    return keys;
  }

  Future<void> setPinned(String channelKey, bool pinned) async {
    await _load;
    final next = {...state};
    if (pinned) {
      next.add(channelKey);
    } else {
      next.remove(channelKey);
    }
    state = next;
    final sorted = next.toList()..sort();
    await ref.read(keyValueStoreProvider).write(_key, sorted.join(','));
  }
}

final pinnedChannelsProvider =
    NotifierProvider<PinnedChannelsNotifier, Set<String>>(
      PinnedChannelsNotifier.new,
    );

/// The playback quality every viewing starts with (Discord
/// request, 2026-11-21): false = the content's original quality
/// (DR / 3倍 as recorded), true = the mobile transcode. One
/// value serves live viewing and recordings alike — the plan-33
/// choice is the same original/mobile pair on both detail
/// screens. The value is the single one the settings screen's
/// default and the detail screens' choices both read and
/// write: changing the quality on a detail screen updates it,
/// so the next viewing starts where the last one left off.
/// Nothing stored means the variant's starting quality
/// (app/variant.dart): the original quality for the standard
/// edition, the mobile transcode for the TV edition.
class PlaybackQualityNotifier extends Notifier<bool> {
  static const _key = 'playback_use_mobile';

  @override
  bool build() {
    final variant = ref.watch(appVariantProvider);
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final value = await store.read(_key);
      if (value != null) state = value == 'true';
    });
    return variant.defaultUseMobilePlayback;
  }

  Future<void> set(bool useMobile) async {
    state = useMobile;
    await ref.read(keyValueStoreProvider).write(_key, '$useMobile');
  }
}

final playbackQualityProvider = NotifierProvider<PlaybackQualityNotifier, bool>(
  PlaybackQualityNotifier.new,
);

/// The viewer's playback buffer choice (plan 126): how much
/// content the playback path banks ahead of the play position,
/// in seconds (see core/playback_buffer.dart for the design).
/// The state is one of playbackBufferChoicesSeconds; the
/// standard value (0) keeps every layer's long-standing cap,
/// so nothing stored reproduces the behaviour from before
/// this setting existed. One value serves live viewing and
/// recordings alike, like the quality above. The playback
/// engine and the player screen read it at each start, so a
/// change applies from the next playback.
class PlaybackBufferNotifier extends Notifier<int> {
  static const _key = 'playback_buffer_seconds';

  @override
  int build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final value = await store.read(_key);
      state = parsePlaybackBufferSeconds(value);
    });
    return playbackBufferStandardSeconds;
  }

  Future<void> set(int seconds) async {
    final normalized = normalizePlaybackBufferSeconds(seconds);
    state = normalized;
    await ref.read(keyValueStoreProvider).write(_key, '$normalized');
  }
}

final playbackBufferProvider = NotifierProvider<PlaybackBufferNotifier, int>(
  PlaybackBufferNotifier.new,
);

/// The programme guide's zoom scale (owner request
/// 2026-11-28; see ui/epg_zoom_policy.dart for the scale
/// and its range). The state is the scale itself, 1 until
/// the viewer pinches the guide. Persisted in the
/// key-value store as a plain double literal; an
/// unparseable or out-of-range stored value reads back
/// clamped or defaulted by the policy, never as an error.
/// The guide screen watches it, so a restored value
/// applies as soon as it lands.
class EpgZoomNotifier extends Notifier<double> {
  static const _key = 'epg_zoom_scale';

  @override
  double build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final value = await store.read(_key);
      state = decodeEpgZoomScale(value);
    });
    return epgDefaultZoomScale;
  }

  Future<void> set(double scale) async {
    final normalized = clampEpgZoomScale(scale);
    state = normalized;
    await ref.read(keyValueStoreProvider).write(_key, '$normalized');
  }
}

final epgZoomProvider = NotifierProvider<EpgZoomNotifier, double>(
  EpgZoomNotifier.new,
);

/// The viewer's video decode mode (plan 139): how much of the
/// video decoding mpv may hand to the device's hardware
/// decoder (see ui/player_hwdec_policy.dart for the modes and
/// the failure they answer). The state is a VideoHwdecMode.
/// Nothing stored reads as the variant's default
/// (defaultVideoHwdecMode): auto on the standard variant,
/// which leaves mpv's and media_kit_video's defaults exactly
/// as they were, and software (full software decoding) on
/// the TV variant. A mode the viewer stored always wins. The player screen snapshots
/// the value as it opens, so a change applies from the next
/// playback.
class VideoHwdecModeNotifier extends Notifier<VideoHwdecMode> {
  static const _key = 'video_hwdec_mode';

  @override
  VideoHwdecMode build() {
    final store = ref.watch(keyValueStoreProvider);
    final fallback = defaultVideoHwdecMode(
      isTv: ref.watch(appVariantProvider).isTv,
    );
    Future.microtask(() async {
      final value = await store.read(_key);
      state = parseVideoHwdecMode(value, fallback: fallback);
    });
    return fallback;
  }

  Future<void> set(VideoHwdecMode mode) async {
    state = mode;
    await ref.read(keyValueStoreProvider).write(_key, mode.name);
  }
}

final videoHwdecModeProvider =
    NotifierProvider<VideoHwdecModeNotifier, VideoHwdecMode>(
      VideoHwdecModeNotifier.new,
    );

/// The app store directory (file stores and the debug log
/// destination, plan 28; location rule in plan 47).
/// The bootstrap overrides this with the real directory; null in
/// tests / headless contexts (debug logging then stays off).
final storeDirectoryProvider = Provider<Directory?>((ref) => null);

/// Debug mode settings (plan 28): the master switch and the
/// enabled category set, persisted in the key-value store.
class DebugSettingsNotifier extends Notifier<DebugSettings> {
  static const _masterKey = 'debug_mode_enabled';
  static const _categoriesKey = 'debug_categories';

  @override
  DebugSettings build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final master = await store.read(_masterKey);
      final categories = await store.read(_categoriesKey);
      state = DebugSettings(
        master: master == 'true',
        categories: DebugSettings.decodeCategories(categories),
      );
    });
    return const DebugSettings();
  }

  Future<void> setMaster(bool value) async {
    state = state.copyWith(master: value);
    await ref.read(keyValueStoreProvider).write(_masterKey, '$value');
  }

  Future<void> setCategory(DiagCategory category, bool enabled) async {
    final next = {...state.categories};
    if (enabled) {
      next.add(category);
    } else {
      next.remove(category);
    }
    state = state.copyWith(categories: next);
    await ref
        .read(keyValueStoreProvider)
        .write(_categoriesKey, state.encodeCategories());
  }
}

final debugSettingsProvider =
    NotifierProvider<DebugSettingsNotifier, DebugSettings>(
      DebugSettingsNotifier.new,
    );

/// The app-wide diagnostics logger (plan 28). Reflects the current
/// debug settings on every record: master off, the category off,
/// or no store directory records nothing.
final diagLogProvider = Provider<DiagLog>((ref) {
  final dir = ref.watch(storeDirectoryProvider);
  if (dir == null) return const DiagLog.none();
  final sink = FileDebugLogSink(dir);
  return DiagLog((category, message) => sink.write(category, message), (
    category,
  ) {
    final settings = ref.read(debugSettingsProvider);
    return settings.master && settings.categories.contains(category);
  });
});

/// Shares the recorded debug logs through the OS share sheet
/// (plan 46). Null when there is no store directory (tests /
/// headless contexts) — the settings screen then hides the share
/// action, like the log destination display.
final debugLogSharerProvider = Provider<DebugLogSharer?>((ref) {
  final dir = ref.watch(storeDirectoryProvider);
  if (dir == null) return null;
  return DebugLogSharer(storeDirectory: dir);
});

/// Opens the debug log folder in the desktop file manager
/// (plan 71) — the desktop counterpart of the share action
/// above. Null under the same conditions as
/// [debugLogSharerProvider]; the settings screen shows the
/// folder action on desktop instead of the share action.
final debugLogFolderOpenerProvider = Provider<DebugLogFolderOpener?>((ref) {
  final dir = ref.watch(storeDirectoryProvider);
  if (dir == null) return null;
  return DebugLogFolderOpener(storeDirectory: dir);
});

/// Exports the recorded debug logs into `Downloads/tmhb-log/`
/// (plan 142) — the TV edition's second way out for the logs,
/// next to the share action above: the TV share sheet offers
/// too few destinations to get a log off the device (plan
/// 140), while Downloads is reachable by adb and file tools.
/// Android only, and null under the same store conditions as
/// [debugLogSharerProvider]; the settings screen shows the
/// action on the TV edition only.
final debugLogDownloadsExporterProvider = Provider<DebugLogDownloadsExporter?>((
  ref,
) {
  final dir = ref.watch(storeDirectoryProvider);
  if (dir == null || !Platform.isAndroid) return null;
  return DebugLogDownloadsExporter(storeDirectory: dir);
});

/// Opens a URL in the device's external browser (owner
/// request 2026-11-26): the settings screen's registration
/// menu sends the unit's nasne HOME there. Like the file
/// picker above this needs no store directory, so it is
/// always available; platforms with no launch route answer
/// unsupported at call time.
final externalBrowserOpenerProvider = Provider<ExternalBrowserOpener>(
  (ref) => ExternalBrowserOpener(),
);

/// Picks a file's bytes for the credential import (plan 84).
/// Unlike the log actions above this needs no store directory,
/// so it is always available.
final fileBytesPickerProvider = Provider<FileBytesPicker>(
  (ref) => FileBytesPicker(),
);

/// Scans the Downloads folder for credential files (plan 127).
/// Android only: the other platforms have a working file picker
/// and no Downloads convention this app targets, so the provider
/// is null there and the import screen hides the entry.
final credentialDownloadsScannerProvider =
    Provider<CredentialDownloadsScanner?>(
      (ref) => Platform.isAndroid ? CredentialDownloadsScanner() : null,
    );

final playbackEngineProvider = Provider<PlaybackEngine>(
  (ref) => DtcpPlaybackEngine(
    credentialStore: ref.watch(credentialStoreProvider),
    srmStore: ref.watch(srmStoreProvider),
    diag: ref.watch(diagLogProvider),
    // Automatic drop recovery (plan 129) is Android-only: the
    // platform of the in-car / tethering environments it was
    // built for. Other platforms keep the previous behaviour.
    autoReconnect: Platform.isAndroid,
    bufferSecondsSource: () => ref.read(playbackBufferProvider),
    akeConnectionFactory: (host, port) =>
        nativeAkeConnectionFactory(host, port, diag: ref.read(diagLogProvider)),
  ),
);

/// The per-device service bundle, assembled from a registration.
/// Control URLs come from [NasneDevice.direct] (the measured
/// fallback forms, plan 11.6) unless a described device is supplied.
class DeviceServices {
  const DeviceServices({
    required this.deviceInfo,
    required this.settings,
    required this.schedules,
    required this.titles,
    required this.metadata,
    required this.live,
    required this.playback,
  });

  final DeviceInfoService deviceInfo;
  final SettingsService settings;
  final ScheduleService schedules;
  final TitleCatalogService titles;
  final MetadataService metadata;
  final LiveCatalogService live;
  final PlaybackEngine playback;
}

DeviceServices assembleDeviceServices(
  RegisteredNasne reg, {
  NasneDevice? describedDevice,
  http.Client? client,
  KeyValueStore? epgCacheStore,
  KeyValueStore? srmKeyValueStore,
  CredentialStore? credentialStore,
  SrmStore? srmStore,
  DiagLog? diagLog,
  int Function()? bufferSecondsSource,
}) {
  final device = describedDevice ?? NasneDevice.direct(reg.host);
  final plain = WebApiTransport(reg.host, client: client);
  final authed = WebApiTransport(
    reg.host,
    client: client,
    tokenProvider: reg.tokenProvider,
  );
  final soap = SoapTransport(client: client);
  final xsrs = device.controlUrl(SoapServices.scheduledRecording.serviceType);
  final cds = device.controlUrl(SoapServices.contentDirectory.serviceType);
  // X_PvrControl carries X_GetTitleInfo (chapters, plan
  // 112). Unlike the two services above it is not
  // load-bearing — a description without it simply has
  // no chapters — so it is passed through as nullable.
  final pvr = device.controlUrl(SoapServices.pvrControl.serviceType);
  if (xsrs == null || cds == null) {
    throw NasneError.validation(
      'providers',
      'device exposes no XSRS/ContentDirectory control URL',
    );
  }
  final metadata = CompositeMetadataService(
    dlna: DlnaMetadataService(soap: soap, controlUrl: cds),
    epg: WebApiEpgService(
      plain: plain,
      authed: authed,
      diag: diagLog ?? const DiagLog.none(),
      // Persistent guide accumulation (plan 23), backed by the
      // guide cache's own key-value store when one is wired.
      guideCache: epgCacheStore == null ? null : EpgGuideCache(epgCacheStore),
      cacheHost: reg.host,
    ),
  );
  return DeviceServices(
    deviceInfo: WebApiDeviceInfoService(plain),
    settings: WebApiSettingsService(authed),
    schedules: SoapScheduleService(soap: soap, controlUrl: xsrs),
    titles: SoapTitleCatalogService(
      soap: soap,
      xsrsControlUrl: xsrs,
      webApi: plain,
      metadata: metadata,
      pvrControlUrl: pvr,
    ),
    metadata: metadata,
    live: DlnaLiveCatalogService(metadata: metadata),
    playback: DtcpPlaybackEngine(
      bufferSecondsSource: bufferSecondsSource,
      autoReconnect: Platform.isAndroid,
      credentialStore: credentialStore ?? SecureCredentialStore(),
      srmStore:
          srmStore ??
          KeyValueSrmStore(srmKeyValueStore ?? InMemoryKeyValueStore()),
      diag: diagLog ?? const DiagLog.none(),
      akeConnectionFactory: (host, port) => nativeAkeConnectionFactory(
        host,
        port,
        diag: diagLog ?? const DiagLog.none(),
      ),
    ),
  );
}

final deviceServicesProvider = Provider.family<DeviceServices, RegisteredNasne>(
  (ref, reg) => assembleDeviceServices(
    reg,
    client: ref.watch(httpClientProvider),
    epgCacheStore: ref.watch(epgGuideCacheStoreProvider),
    srmKeyValueStore: ref.watch(srmKeyValueStoreProvider),
    credentialStore: ref.watch(credentialStoreProvider),
    srmStore: ref.watch(srmStoreProvider),
    diagLog: ref.watch(diagLogProvider),
    bufferSecondsSource: () => ref.read(playbackBufferProvider),
  ),
);
