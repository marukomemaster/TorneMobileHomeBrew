/// Auto record rules screen (user-fork addition):
/// the standing rules in priority order, the manual
/// check, and the check log. See
/// auto_record_policy.dart for what a rule means and
/// app/auto_record_providers.dart for the check
/// itself.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/auto_record_providers.dart';
import '../app/bs_epg_providers.dart';
import '../app/cs_epg_providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'auto_record_policy.dart';
import 'epg_genre.dart';
import 'format.dart';
import 'widgets.dart';

class AutoRecordScreen extends ConsumerStatefulWidget {
  const AutoRecordScreen({super.key});

  @override
  ConsumerState<AutoRecordScreen> createState() => _AutoRecordScreenState();
}

class _AutoRecordScreenState extends ConsumerState<AutoRecordScreen> {
  bool _checking = false;

  Future<void> _runCheck() async {
    setState(() => _checking = true);
    final summary = await ref.read(autoRecordCheckerProvider).run();
    if (!mounted) return;
    setState(() => _checking = false);
    showSnack(
      context,
      summary.didAnything
          ? 'チェック完了：予約 ${summary.reserved} 件・'
                '競合で見送り ${summary.conflicts} 件・'
                'エラー ${summary.errors} 件'
          : 'チェック完了：新しい予約はありませんでした',
    );
  }

  void _openEditor([AutoRecordRule? rule]) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AutoRecordRuleEditScreen(rule: rule),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(autoRecordRulesProvider);
    final log = ref.watch(autoRecordLogProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('おまかせ録画'),
        actions: [
          IconButton(
            tooltip: 'ルールを追加',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '条件に合う番組を、アプリ起動時と「今すぐチェック」で自動予約します。'
              '上にあるルールほど優先で、時間の重なる番組は先に予約された方が残ります。'
              'すでに始まった番組は対象外です。',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              onPressed: _checking ? null : _runCheck,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: const Text('今すぐチェック'),
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'ルール（上が優先）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (rules.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('ルールはまだありません。右上の＋から追加してください。'),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rules.length,
              onReorderItem: (oldIndex, newIndex) => ref
                  .read(autoRecordRulesProvider.notifier)
                  .reorder(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final rule = rules[index];
                return ListTile(
                  key: ValueKey(rule.id),
                  title: Text(autoRecordRuleText(rule)),
                  subtitle: Text('${index + 1} 番目の優先度'),
                  trailing: Switch(
                    value: rule.enabled,
                    onChanged: (value) => ref
                        .read(autoRecordRulesProvider.notifier)
                        .setEnabled(rule.id, value),
                  ),
                  onTap: () => _openEditor(rule),
                );
              },
            ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'チェック履歴',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (log.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('まだ履歴はありません。'),
            )
          else
            for (final entry in log)
              ListTile(
                leading: Icon(switch (entry.kind) {
                  AutoRecordLogKind.reserved => Icons.check_circle_outline,
                  AutoRecordLogKind.conflict => Icons.event_busy,
                  AutoRecordLogKind.error => Icons.error_outline,
                  AutoRecordLogKind.ruleDisabled =>
                    Icons.do_not_disturb_on_outlined,
                }),
                title: Text(
                  entry.title.isEmpty ? '（タイトルなし）' : entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${switch (entry.kind) {
                    AutoRecordLogKind.reserved => '予約しました',
                    AutoRecordLogKind.conflict => '競合で見送り',
                    AutoRecordLogKind.error => 'エラー',
                    AutoRecordLogKind.ruleDisabled => '1回だけのためルールを無効化',
                  }}'
                  ' ・ ${entry.channelName}'
                  ' ・ ${formatDateTimeWithWeekdayJst(entry.start)}'
                  '${entry.ruleText.isEmpty ? '' : ' ・ ${entry.ruleText}'}',
                ),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// One rule's editor: the positive conditions (a
/// keyword, a genre, or both), the refinements on
/// top of them (one channel, exclusion keywords, a
/// time-of-day window, a weekday set), the repeat
/// mode and the recording quality. Saving
/// an existing rule keeps its place in the priority
/// order; deleting removes it outright (reservations
/// it already made stay — they are the unit's, not
/// the rule's).
class AutoRecordRuleEditScreen extends ConsumerStatefulWidget {
  const AutoRecordRuleEditScreen({super.key, this.rule});

  /// The rule being edited; null when adding.
  final AutoRecordRule? rule;

  @override
  ConsumerState<AutoRecordRuleEditScreen> createState() =>
      _AutoRecordRuleEditScreenState();
}

class _AutoRecordRuleEditScreenState
    extends ConsumerState<AutoRecordRuleEditScreen> {
  late final TextEditingController _keyword = TextEditingController(
    text: widget.rule?.keyword ?? '',
  );
  late final TextEditingController _exclude = TextEditingController(
    text: widget.rule?.excludeKeywords.join('、') ?? '',
  );
  late int? _genre = widget.rule?.genreLevel1;
  late AutoRecordChannel? _channel = widget.rule?.channel;
  late bool _onceOnly = widget.rule?.onceOnly ?? false;
  late int? _qualityMode = widget.rule?.qualityMode;
  late int? _startMinute = widget.rule?.startMinuteOfDay;
  late int? _endMinute = widget.rule?.endMinuteOfDay;
  late final Set<int> _weekdays = {...(widget.rule?.weekdays ?? const <int>{})};

  @override
  void dispose() {
    _keyword.dispose();
    _exclude.dispose();
    super.dispose();
  }

  /// The channels the editor can offer: every service
  /// of every registered unit's three guides, merged
  /// by service triple, in band / channel-number
  /// order. Guides that have not landed yet simply
  /// contribute nothing yet.
  List<AutoRecordChannel> _guideChannels() {
    final registrations =
        ref.watch(registrationsProvider).value ?? const <RegisteredNasne>[];
    final seen = <(int, int, int), Channel>{};
    for (final reg in registrations) {
      for (final provider in [
        epgGuideProvider(reg),
        bsEpgGuideProvider(reg),
        csEpgGuideProvider(reg),
      ]) {
        final guide = ref.watch(provider).value;
        if (guide == null) continue;
        for (final service in guide.services) {
          final ch = service.channel;
          seen.putIfAbsent(
            (ch.networkId, ch.transportStreamId, ch.serviceId),
            () => ch,
          );
        }
      }
    }
    final channels = seen.values.toList()..sort((a, b) {
      final byBand = a.broadcastingType.compareTo(b.broadcastingType);
      if (byBand != 0) return byBand;
      final byNumber = a.channelNumber.compareTo(b.channelNumber);
      return byNumber != 0 ? byNumber : a.serviceId.compareTo(b.serviceId);
    });
    return [
      for (final ch in channels)
        AutoRecordChannel(
          networkId: ch.networkId,
          transportStreamId: ch.transportStreamId,
          serviceId: ch.serviceId,
          name: ch.serviceName,
        ),
    ];
  }

  /// The exclusion field's contents as a keyword
  /// list: split on 、, commas and newlines, trimmed,
  /// blanks and repeats dropped.
  List<String> _excludeList() {
    final out = <String>[];
    for (final part in _exclude.text.split(RegExp(r'[、,\n]'))) {
      final word = part.trim();
      if (word.isNotEmpty && !out.contains(word)) out.add(word);
    }
    return out;
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _startMinute : _endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 19, minute: 0)
          : TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startMinute = picked.hour * 60 + picked.minute;
      } else {
        _endMinute = picked.hour * 60 + picked.minute;
      }
    });
  }

  Future<void> _save() async {
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty && _genre == null) {
      showSnack(context, 'キーワードかジャンルのどちらかを入力してください');
      return;
    }
    if ((_startMinute == null) != (_endMinute == null)) {
      showSnack(context, '時間帯は開始と終了の両方を選んでください');
      return;
    }
    if (_startMinute != null && _startMinute == _endMinute) {
      showSnack(context, '時間帯の開始と終了が同じ時刻です');
      return;
    }
    final notifier = ref.read(autoRecordRulesProvider.notifier);
    final existing = widget.rule;
    AutoRecordRule build(String id, bool enabled) => AutoRecordRule(
      id: id,
      keyword: keyword,
      genreLevel1: _genre,
      channel: _channel,
      excludeKeywords: _excludeList(),
      startMinuteOfDay: _startMinute,
      endMinuteOfDay: _endMinute,
      weekdays: _weekdays,
      onceOnly: _onceOnly,
      qualityMode: _qualityMode,
      enabled: enabled,
    );
    if (existing == null) {
      await notifier.add(
        build(DateTime.now().microsecondsSinceEpoch.toString(), true),
      );
    } else {
      await notifier.update(build(existing.id, existing.enabled));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await ref.read(autoRecordRulesProvider.notifier).remove(widget.rule!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.rule != null;
    final channelOptions = _guideChannels();
    // The rule's own channel stays selectable even
    // when the guides no longer list it.
    if (_channel != null && !channelOptions.contains(_channel)) {
      channelOptions.insert(0, _channel!);
    }
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'ルールを編集' : 'ルールを追加')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _keyword,
            decoration: const InputDecoration(
              labelText: 'キーワード',
              hintText: '例：タイトルや概要に含まれる言葉',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            initialValue: _genre,
            decoration: const InputDecoration(
              labelText: 'ジャンル',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('指定なし')),
              for (final value in epgGenreLevel1Values)
                DropdownMenuItem<int?>(
                  value: value,
                  child: Text(epgGenreLabel(value)!),
                ),
            ],
            onChanged: (value) => setState(() => _genre = value),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AutoRecordChannel?>(
            initialValue: _channel,
            decoration: const InputDecoration(
              labelText: 'チャンネル',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<AutoRecordChannel?>(
                value: null,
                child: Text('指定なし'),
              ),
              for (final option in channelOptions)
                DropdownMenuItem<AutoRecordChannel?>(
                  value: option,
                  child: Text(option.name),
                ),
            ],
            onChanged: (value) => setState(() => _channel = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _exclude,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '除外キーワード',
              hintText: '例：再放送、総集編',
              helperText: '「、」で区切って複数指定できます',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '時間帯（番組の開始時刻）',
              border: OutlineInputBorder(),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(start: true),
                    child: Text(
                      _startMinute == null
                          ? '開始：指定なし'
                          : '開始：${_timeLabel(_startMinute!)}',
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('〜'),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(start: false),
                    child: Text(
                      _endMinute == null
                          ? '終了：指定なし'
                          : '終了：${_timeLabel(_endMinute!)}',
                    ),
                  ),
                ),
                if (_startMinute != null || _endMinute != null)
                  IconButton(
                    tooltip: '時間帯を解除',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _startMinute = null;
                      _endMinute = null;
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '曜日（番組の開始曜日）',
              border: OutlineInputBorder(),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                    label: Text('月火水木金土日'[day - 1]),
                    selected: _weekdays.contains(day),
                    onSelected: (value) => setState(() {
                      if (value) {
                        _weekdays.add(day);
                      } else {
                        _weekdays.remove(day);
                      }
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<bool>(
            initialValue: _onceOnly,
            decoration: const InputDecoration(
              labelText: '繰り返し',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem<bool>(value: false, child: Text('毎週録画')),
              DropdownMenuItem<bool>(value: true, child: Text('1回だけ')),
            ],
            onChanged: (value) => setState(() => _onceOnly = value ?? false),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            initialValue: _qualityMode,
            decoration: const InputDecoration(
              labelText: '画質モード',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('指定なし')),
              for (final mode in const [100, 230])
                DropdownMenuItem<int?>(
                  value: mode,
                  child: Text(qualityModeLabel(mode)),
                ),
            ],
            onChanged: (value) => setState(() => _qualityMode = value),
          ),
          const SizedBox(height: 8),
          const Text(
            'キーワードとジャンルの両方を指定すると、両方に合う番組だけが対象になります。'
            'チャンネル・曜日・時間帯も同じく、すべてに合う番組だけが対象です。'
            '曜日を何も選ばないときは、毎日が対象です。'
            '除外キーワードを含む番組は、条件に合っても録画しません。'
            '時間帯は開始時刻ちょうどを含み、終了時刻ちょうどは含みません。'
            '「1回だけ」は、予約できたら自動でルールを無効にします。'
            '画質モードを指定しないときは DR で録画します。',
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存')),
          if (editing) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _delete, child: const Text('このルールを削除')),
          ],
        ],
      ),
    );
  }

  /// A minute-of-day as `H:MM`, for the time pickers.
  String _timeLabel(int minute) =>
      '${minute ~/ 60}:${(minute % 60).toString().padLeft(2, '0')}';
}
