/// Settings screen (plan 5.6 item 4): registration management only —
/// SSDP discovery, manual address registration (both verified by
/// PINVerify through the RegistrationService), re-verification, and
/// unregistration. Device settings themselves are out of the v1
/// scope (plan 1.2).
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/auto_pick_providers.dart';
import '../app/auto_record_providers.dart';
import '../app/debug_log.dart';
import '../app/external_browser.dart';
import '../app/log_export.dart';
import '../app/log_folder.dart';
import '../app/log_share.dart';
import '../app/providers.dart';
import '../app/state.dart';
import '../app/store_directory.dart';
import '../core/core.dart';
import 'auto_record_screen.dart';
import 'ranking_screen.dart';
import 'dtcp_credential_screen.dart';
import 'epg_hidden_genres_screen.dart';
import 'error_messages.dart';
import 'format.dart';
import 'hidden_channels_screen.dart';
import 'player_hwdec_policy.dart';
import 'tv_focus.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _searching = false;
  List<NasneDevice>? _found;
  String? _searchError;
  bool _registering = false;
  bool _sharingLogs = false;
  bool _openingLogFolder = false;
  bool _exportingLogs = false;
  final _manualHost = TextEditingController();

  @override
  void dispose() {
    _manualHost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registrations = ref.watch(registrationsProvider);
    final selected = ref.watch(selectedRegistrationProvider);
    final debugSettings = ref.watch(debugSettingsProvider);
    final autoRecordRules = ref.watch(autoRecordRulesProvider);
    final autoPickSettings = ref.watch(autoPickSettingsProvider);
    final storeDir = ref.watch(storeDirectoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          // TV: the first and last items of the list hold focus
          // (TvFocusAnchor) so D-pad traversal can scroll to both
          // ends of the list (plan 123; the footer below was
          // unreachable by remote before this, plan 121).
          TvFocusAnchor(child: _sectionTitle(context, '登録済み nasne')),
          registrations.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(userMessageForError(e)),
            ),
            data: (list) => Column(
              children: [
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('登録済みの nasne はありません。下の「探す」か手動登録で追加してください。'),
                  ),
                for (final reg in list)
                  ListTile(
                    // Tapping the row selects the device, as the
                    // radio icon promises; the popup menu keeps
                    // the same action for discoverability.
                    onTap: selected?.host == reg.host
                        ? null
                        : () => _onRegistrationAction('select', reg),
                    leading: Icon(
                      selected?.host == reg.host
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(reg.friendlyName),
                    subtitle: Text('${reg.host}\nMAC ${maskMac(reg.macAddr)}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) =>
                          _onRegistrationAction(action, reg),
                      itemBuilder: (context) => [
                        if (selected?.host != reg.host)
                          const PopupMenuItem(
                            value: 'select',
                            child: Text('この nasne を使う'),
                          ),
                        const PopupMenuItem(
                          value: 'verify',
                          child: Text('登録を検証'),
                        ),
                        const PopupMenuItem(
                          value: 'home',
                          child: Text('nasne HOME を開く'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('登録を解除'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          _sectionTitle(context, 'nasne を探す'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: _searching ? null : _discover,
                  icon: const Icon(Icons.search),
                  label: Text(_searching ? '検索中…' : 'LAN 内の nasne を探す'),
                ),
                if (_searchError != null) ...[
                  const SizedBox(height: 8),
                  Text(_searchError!),
                  const SizedBox(height: 12),
                  const DiscoveryChecklist(),
                ],
                if (_found != null) ...[
                  const SizedBox(height: 8),
                  if (_found!.isEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('見つかりませんでした。'),
                        const SizedBox(height: 12),
                        const DiscoveryChecklist(),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _searching ? null : _discover,
                          child: const Text('もう一度探す'),
                        ),
                        const SizedBox(height: 8),
                        const Text('それでも見つからない場合は、下の手動登録も使えます。'),
                      ],
                    )
                  else
                    for (final device in _found!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.tv_outlined),
                        title: Text(device.friendlyName),
                        subtitle: Text(device.host),
                        trailing: FilledButton.tonal(
                          onPressed: _registering
                              ? null
                              : () => _registerDevice(device),
                          child: const Text('登録'),
                        ),
                      ),
                ],
              ],
            ),
          ),
          const Divider(),
          _sectionTitle(context, '手動登録'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _manualHost,
                  decoration: const InputDecoration(
                    labelText: 'IP アドレス / ホスト名',
                    hintText: '192.168.11.129',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _registering ? null : _registerManual,
                  icon: const Icon(Icons.add),
                  label: const Text('登録'),
                ),
              ],
            ),
          ),
          const Divider(),
          _sectionTitle(context, '番組表'),
          SwitchListTile(
            title: const Text('サブチャンネルを表示'),
            subtitle: const Text('番組表にサブチャンネル (2 / 3 チャンネル) を含めます'),
            value: ref.watch(showSubchannelsProvider),
            onChanged: (value) =>
                ref.read(showSubchannelsProvider.notifier).set(value),
          ),
          ListTile(
            title: const Text('見ないジャンル'),
            subtitle: const Text('選んだジャンルの番組は番組表で空白表示になります'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const EpgHiddenGenresScreen(),
              ),
            ),
          ),
          ListTile(
            title: const Text('見ないチャンネル'),
            subtitle: const Text('選んだチャンネルは TV視聴と番組表に表示されなくなります'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const HiddenChannelsScreen(),
              ),
            ),
          ),
          const Divider(),
          _sectionTitle(context, '再生'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('再生画質', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('元画質 (DR)')),
                    ButtonSegment(value: true, label: Text('モバイル')),
                  ],
                  selected: {ref.watch(playbackQualityProvider)},
                  onSelectionChanged: (selection) => ref
                      .read(playbackQualityProvider.notifier)
                      .set(selection.first),
                ),
                const SizedBox(height: 8),
                Text(
                  'TV 視聴と録画再生を開始するときの画質です。'
                  '各視聴画面で画質を変更すると、この値も更新されます。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // The playback buffer setting is mobile / TV only
          // this round (plan 126); the desktop builds do not
          // show it.
          if (!isDesktopStorePlatform) const PlaybackBufferSetting(),
          // The video decode mode is Android only this round
          // (plan 139): the failure it answers is Android
          // hardware's, and the desktop builds are out of
          // scope (see player_hwdec_policy.dart).
          if (Platform.isAndroid) const VideoHwdecSetting(),
          SwitchListTile(
            title: const Text('CM自動スキップ'),
            subtitle: const Text('録画再生で、短いチャプター区間をCMとみなして自動で飛ばします'),
            value: ref.watch(cmAutoSkipProvider),
            onChanged: (value) =>
                ref.read(cmAutoSkipProvider.notifier).set(value),
          ),
          const Divider(),
          _sectionTitle(context, '録画再生 (DTCP-IP)'),
          ListTile(
            title: const Text('DTCP-IP 資格情報'),
            subtitle: Text(
              ref
                  .watch(credentialSummaryProvider)
                  .when(
                    data: (summary) =>
                        summary == null ? '未インポート (再生には資格情報が必要です)' : 'インポート済み',
                    loading: () => '確認中…',
                    error: (_, _) => '読み込みエラー',
                  ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const DtcpCredentialScreen(),
              ),
            ),
          ),
          const Divider(),
          _sectionTitle(context, 'デバッグ'),
          SwitchListTile(
            title: const Text('デバッグモード'),
            subtitle: const Text(
              '診断ログを端末内のファイルに保存します (ステージ遷移・応答コード・所要時間のみ。'
              '資格情報やセッション鍵は記録されません)',
            ),
            value: debugSettings.master,
            onChanged: (value) =>
                ref.read(debugSettingsProvider.notifier).setMaster(value),
          ),
          if (debugSettings.master) ...[
            for (final category in DiagCategory.values)
              SwitchListTile(
                title: Text(diagCategoryLabel(category)),
                value: debugSettings.categories.contains(category),
                onChanged: (value) => ref
                    .read(debugSettingsProvider.notifier)
                    .setCategory(category, value),
              ),
            if (storeDir != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '保存先: ${storeDir.path}/debug_logs/',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          // Sharing stays available with the master switch off:
          // the logs that matter are usually already recorded by
          // the time the user comes here to send them (plan 46).
          // Desktop has no share sheet to send them through;
          // there the same slot opens the log folder in the file
          // manager instead (plan 71).
          if (storeDir != null)
            if (isDesktopStorePlatform)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('ログフォルダを開く'),
                subtitle: const Text('保存済みの診断ログのフォルダをファイルマネージャで開きます'),
                enabled: !_openingLogFolder,
                onTap: _openingLogFolder ? null : _openLogFolder,
              )
            else
              Builder(
                builder: (tileContext) => ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('デバッグログを共有'),
                  subtitle: const Text('保存済みの診断ログファイルを共有シートで送ります'),
                  enabled: !_sharingLogs,
                  onTap: _sharingLogs
                      ? null
                      : () => _shareDebugLogs(tileContext),
                ),
              ),
          // The TV edition also writes the logs into
          // Downloads/tmhb-log (plan 142): the TV share sheet
          // offers too few destinations to get a log off the
          // device (plan 140), while Downloads is reachable by
          // adb and file tools without any account or network
          // state.
          if (storeDir != null && isTvVariant(context))
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('デバッグログを Downloads に書き出す'),
              subtitle: const Text(
                '保存済みの診断ログを Downloads の tmhb-log フォルダに書き出します',
              ),
              enabled: !_exportingLogs,
              onTap: _exportingLogs ? null : _exportDebugLogs,
            ),
          const Divider(),
          _sectionTitle(context, 'おまかせ録画'),
          ListTile(
            title: const Text('おまかせ録画ルール'),
            subtitle: Text(
              autoRecordRules.isEmpty
                  ? 'タイトルやジャンルの条件で自動予約します'
                  : 'ルール ${autoRecordRules.length} 件',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AutoRecordScreen()),
            ),
          ),
          SwitchListTile(
            title: const Text('おまかせ自動録画'),
            subtitle: const Text('ルールに無い番組も、よく録る傾向から空き時間に自動で録画します'),
            value: autoPickSettings.enabled,
            onChanged: (value) =>
                ref.read(autoPickSettingsProvider.notifier).setEnabled(value),
          ),
          ListTile(
            title: const Text('ランキング'),
            subtitle: const Text('よく録る傾向 ・ おすすめ番組 ・ 自動録画の候補'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const RankingScreen()),
            ),
          ),
          const Divider(),
          TvFocusAnchor(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '発見にはローカルネットワークへのアクセス許可が必要です (iOS では許可ダイアログが'
                '表示される場合があります)。発見できない環境では手動登録を使ってください。\n\n'
                'torne mobile HB $appVersionLabel',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  /// Shares the recorded debug logs via the OS share sheet
  /// (plan 46). The tile's global rect anchors the iPad popover
  /// presentation; Android ignores it.
  Future<void> _shareDebugLogs(BuildContext tileContext) async {
    final sharer = ref.read(debugLogSharerProvider);
    if (sharer == null || _sharingLogs) return;
    Rect? origin;
    final renderObject = tileContext.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      origin = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    setState(() => _sharingLogs = true);
    try {
      final outcome = await sharer.share(origin: origin);
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'debug log share: outcome=${outcome.name}',
      );
      if (!mounted) return;
      final message = switch (outcome) {
        DebugLogShareOutcome.noLogs => '共有できるログがありません',
        DebugLogShareOutcome.unsupported => 'このプラットフォームではログを共有できません',
        DebugLogShareOutcome.shared => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ログの共有に失敗しました')));
    } finally {
      if (mounted) setState(() => _sharingLogs = false);
    }
  }

  /// Writes the recorded debug logs into `Downloads/tmhb-log/`
  /// (plan 142), the TV edition's counterpart of the share
  /// action: nothing visibly leaves the device, so the outcome
  /// is always answered with a message — a tap that quietly
  /// does nothing is the failure shape plan 69 taught.
  Future<void> _exportDebugLogs() async {
    final exporter = ref.read(debugLogDownloadsExporterProvider);
    if (exporter == null || _exportingLogs) return;
    setState(() => _exportingLogs = true);
    try {
      final result = await exporter.export();
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'debug log export: outcome=${result.outcome.name} '
        'count=${result.fileCount} dir=${result.directoryPath}',
      );
      if (!mounted) return;
      final message = switch (result.outcome) {
        DebugLogExportOutcome.exported =>
          'Downloads の tmhb-log フォルダに ${result.fileCount} 件のログを書き出しました',
        DebugLogExportOutcome.noLogs => '書き出せるログがありません',
        DebugLogExportOutcome.unsupported => 'このプラットフォームではログを書き出せません',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ref.read(diagLogProvider)(DiagCategory.ui, 'debug log export failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ログの書き出しに失敗しました')));
    } finally {
      if (mounted) setState(() => _exportingLogs = false);
    }
  }

  /// Opens the debug log folder in the desktop file manager
  /// (plan 71), the desktop counterpart of the share action.
  /// Failures are shown, not swallowed: a tap that silently does
  /// nothing is exactly how the picker failure in plan 69
  /// presented itself.
  Future<void> _openLogFolder() async {
    final opener = ref.read(debugLogFolderOpenerProvider);
    if (opener == null || _openingLogFolder) return;
    setState(() => _openingLogFolder = true);
    try {
      final outcome = await opener.open();
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'debug log folder open: outcome=${outcome.name}',
      );
      if (!mounted) return;
      if (outcome == DebugLogFolderOpenOutcome.unsupported) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('このプラットフォームではログフォルダを開けません')),
        );
      }
    } catch (e) {
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'debug log folder open failed: $e',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ログフォルダを開けませんでした')));
    } finally {
      if (mounted) setState(() => _openingLogFolder = false);
    }
  }

  Future<void> _discover() async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final found = await ref.read(discoveryServiceProvider).discover();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = found;
      });
    } on NasneError catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = userMessageForError(e);
      });
    }
  }

  Future<void> _registerDevice(NasneDevice device) async {
    setState(() => _registering = true);
    try {
      final registration = await ref
          .read(registrationServiceProvider)
          .register(device);
      await ref.read(registrationsProvider.notifier).add(registration);
      await ref.read(selectedHostProvider.notifier).select(registration.host);
      if (!mounted) return;
      showSnack(context, '登録しました: ${registration.host}');
    } on NasneError catch (e) {
      if (!mounted) return;
      showSnack(context, userMessageForError(e));
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _registerManual() async {
    FocusScope.of(context).unfocus();
    final host = _manualHost.text.trim();
    if (host.isEmpty) {
      showSnack(context, 'アドレスを入力してください');
      return;
    }
    setState(() => _registering = true);
    NasneDevice device;
    try {
      device = await ref
          .read(discoveryServiceProvider)
          .describe(Uri(scheme: 'http', host: host, port: 58888, path: '/'));
    } catch (_) {
      // The description may be unreachable while the device itself is
      // fine; registration re-verifies against the device directly.
      device = NasneDevice.direct(host);
    }
    if (!mounted) return;
    await _registerDevice(device);
  }

  /// Opens the unit's nasne HOME in the external browser
  /// (owner request 2026-11-26). Failures are shown, not
  /// swallowed — the same defensive line as the log actions
  /// above: a tap that silently does nothing reads as a bug.
  Future<void> _openNasneHome(RegisteredNasne reg) async {
    final opener = ref.read(externalBrowserOpenerProvider);
    try {
      final outcome = await opener.open(nasneHomeUri(reg.host));
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'nasne home open: outcome=${outcome.name} host=${reg.host}',
      );
      if (!mounted) return;
      if (outcome == ExternalBrowserOpenOutcome.unsupported) {
        showSnack(context, 'このプラットフォームではブラウザを開けません');
      }
    } catch (e) {
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'nasne home open failed: $e',
      );
      if (!mounted) return;
      showSnack(context, 'nasne HOME を開けませんでした');
    }
  }

  Future<void> _onRegistrationAction(String action, RegisteredNasne reg) async {
    switch (action) {
      case 'select':
        await ref.read(selectedHostProvider.notifier).select(reg.host);
      case 'verify':
        try {
          final ok = await ref.read(registrationServiceProvider).verify(reg);
          if (!mounted) return;
          showSnack(
            context,
            ok ? '検証 OK: ${reg.host}' : '検証に失敗しました: ${reg.host}',
          );
        } on NasneError catch (e) {
          if (!mounted) return;
          showSnack(context, userMessageForError(e));
        }
      case 'home':
        await _openNasneHome(reg);
      case 'remove':
        final ok = await confirmDialog(
          context,
          title: '登録を解除',
          message: '${reg.friendlyName} (${reg.host}) の登録を解除しますか？',
          confirmLabel: '解除',
        );
        if (!ok) return;
        await ref.read(registrationsProvider.notifier).remove(reg.host);
        if (ref.read(selectedHostProvider) == reg.host) {
          await ref.read(selectedHostProvider.notifier).select(null);
        }
        if (!mounted) return;
        showSnack(context, '登録を解除しました');
    }
  }
}

/// The playback buffer choice (plan 126): how much content
/// the playback path banks ahead of the play position, as a
/// segmented choice mirroring the quality choice above.
/// Seconds are the unit a viewer can reason about; the
/// conversion to per-layer byte caps lives in
/// core/playback_buffer.dart. The standard segment keeps the
/// long-standing caps (see the policy file).
class PlaybackBufferSetting extends ConsumerWidget {
  const PlaybackBufferSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('再生バッファ', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final seconds in playbackBufferChoicesSeconds)
                ButtonSegment(
                  value: seconds,
                  label: Text(
                    seconds == playbackBufferStandardSeconds
                        ? '標準'
                        : '$seconds 秒',
                  ),
                ),
            ],
            selected: {ref.watch(playbackBufferProvider)},
            onSelectionChanged: (selection) =>
                ref.read(playbackBufferProvider.notifier).set(selection.first),
          ),
          const SizedBox(height: 8),
          Text(
            '再生位置より先の内容をためておく量です。回線が不安定な環境では、'
            '大きくすると途切れにくくなります。大きくするほどメモリの使用量が増えます。'
            '次の再生から反映されます。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The video decode mode choice (plan 139): how much of the
/// video decoding mpv may hand to the device's hardware
/// decoder (see player_hwdec_policy.dart for the modes and
/// the failure they answer). Shown on Android only — the
/// settings screen gates it — where the hardware paths this
/// steers live. The tile shows the mode in force; tapping
/// opens the picker dialog.
class VideoHwdecSetting extends ConsumerWidget {
  const VideoHwdecSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(videoHwdecModeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('映像デコード方式', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(mode.shortLabel),
            subtitle: Text(mode.description),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickMode(context, ref, mode),
          ),
          const SizedBox(height: 8),
          Text(
            '元画質 (DR) で映像が出ない端末では、「MPEG-2 のみソフトウェア」で'
            '改善することがあります。次の再生から反映されます。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _pickMode(
    BuildContext context,
    WidgetRef ref,
    VideoHwdecMode current,
  ) async {
    final picked = await showDialog<VideoHwdecMode>(
      context: context,
      builder: (context) {
        // TV: the mode in force takes focus as the dialog
        // opens — the picker's primary position — so the
        // D-pad starts inside the dialog instead of staying
        // on the screen behind it (plan 134).
        final tv = isTvVariant(context);
        return AlertDialog(
          title: const Text('映像デコード方式'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: VideoHwdecMode.values.length,
              itemBuilder: (context, index) {
                final mode = VideoHwdecMode.values[index];
                return ListTile(
                  autofocus: tv && mode == current,
                  leading: Icon(
                    mode == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(mode.shortLabel),
                  subtitle: Text(mode.description),
                  onTap: () => Navigator.pop(context, mode),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
    if (picked != null && picked != current) {
      await ref.read(videoHwdecModeProvider.notifier).set(picked);
    }
  }
}
