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

/// One rule's editor: a title keyword, a genre, or
/// both. Saving an existing rule keeps its place in
/// the priority order; deleting removes it outright
/// (reservations it already made stay — they are the
/// unit's, not the rule's).
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
  late int? _genre = widget.rule?.genreLevel1;

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty && _genre == null) {
      showSnack(context, 'キーワードかジャンルのどちらかを入力してください');
      return;
    }
    final notifier = ref.read(autoRecordRulesProvider.notifier);
    final existing = widget.rule;
    if (existing == null) {
      await notifier.add(
        AutoRecordRule(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          keyword: keyword,
          genreLevel1: _genre,
        ),
      );
    } else {
      await notifier.update(
        AutoRecordRule(
          id: existing.id,
          keyword: keyword,
          genreLevel1: _genre,
          enabled: existing.enabled,
        ),
      );
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
          const SizedBox(height: 8),
          const Text('キーワードとジャンルの両方を指定すると、両方に合う番組だけが対象になります。'),
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
}
