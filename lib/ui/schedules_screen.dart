/// Schedules screen (plan 5.6 item 2): the reservation list in
/// chronological order, with create / edit / delete and conflict
/// warnings (via the form). On wide layouts the detail opens in a
/// second pane; on narrow layouts it is a pushed page (plan 12.7).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/bs_epg_providers.dart';
import '../app/cs_epg_providers.dart';
import '../app/providers.dart';
import '../app/auto_pick_providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'error_messages.dart';
import 'auto_record_policy.dart';
import 'format.dart';
import 'schedule_form.dart';
import 'tv_focus.dart';
import 'widgets.dart';

/// Width at or above which list and detail sit side by side.
const double twoPaneBreakpoint = 1000;

class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final reg = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('予約'),
        actions: [
          if (reg != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '更新',
              onPressed: () => ref.invalidate(schedulesProvider(reg)),
            ),
        ],
      ),
      floatingActionButton: reg == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ScheduleFormPage.create(reg)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('新規予約'),
            ),
      body: reg == null
          ? NoDeviceView(
              onRegister: () =>
                  ref.read(tabIndexProvider.notifier).select(AppTabs.settings),
            )
          : _ScheduleList(
              reg: reg,
              selectedId: _selectedId,
              onSelect: (schedule, twoPane) {
                if (twoPane) {
                  setState(() => _selectedId = schedule.id);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ScheduleDetailPage(reg: reg, scheduleId: schedule.id),
                    ),
                  );
                }
              },
            ),
    );
  }
}

/// Whether [schedule] is one the auto pick made:
/// its programme key is in the mark store for [reg]
/// (see AutoPickMarksNotifier). Display only — a
/// marked reservation is the viewer's to keep or
/// delete like any other.
bool isAutoPickedSchedule(
  WidgetRef ref,
  RegisteredNasne reg,
  RecordSchedule schedule,
) {
  final marks = ref.watch(autoPickMarksProvider);
  return (marks[reg.host] ?? const <String>{}).contains(
    autoRecordProgrammeKey(
      broadcastingType: schedule.channel.broadcastingType,
      serviceId: schedule.channel.serviceId,
      start: schedule.start,
    ),
  );
}

class _ScheduleList extends ConsumerWidget {
  const _ScheduleList({
    required this.reg,
    required this.selectedId,
    required this.onSelect,
  });

  final RegisteredNasne reg;
  final String? selectedId;
  final void Function(RecordSchedule schedule, bool twoPane) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider(reg));
    final terrestrial =
        ref.watch(channelsProvider(reg)).value ?? const <Channel>[];
    final needsBs =
        schedules.value?.any(
          (s) => s.channel.broadcastingType == bsBroadcastingType,
        ) ??
        false;
    final bs = needsBs
        ? (ref.watch(bsChannelsProvider(reg)).value ?? const <Channel>[])
        : const <Channel>[];
    final needsCs =
        schedules.value?.any(
          (s) => s.channel.broadcastingType == csBroadcastingType,
        ) ??
        false;
    final cs = needsCs
        ? (ref.watch(csChannelsProvider(reg)).value ?? const <Channel>[])
        : const <Channel>[];
    final channels = [...terrestrial, ...bs, ...cs];
    return asyncSection(schedules, (list) {
      if (list.isEmpty) {
        return const Center(child: Text('予約はありません'));
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          // One width decides both the layout and the tap
          // behaviour: the width this list actually gets. Reading
          // the MediaQuery window width for the tap instead left
          // a band (window >= breakpoint, list < breakpoint, e.g.
          // a 1024-wide iPad in landscape past the shell's rail)
          // where a tap updated only the selection and opened
          // nothing. See titles_screen.dart for the full note.
          final twoPane = constraints.maxWidth >= twoPaneBreakpoint;
          final listView = ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              return ListTile(
                selected: s.id == selectedId,
                leading: const Icon(Icons.event_note_outlined),
                title: Text(
                  '${formatDateTimeWithWeekdayJst(s.start)} '
                  '${channelDisplayName(channels, s.channel)}',
                ),
                subtitle: Text(
                  '${formatTimeJst(s.start)}〜${formatTimeJst(s.end)}'
                  ' (${formatDurationSeconds(s.durationSeconds)})'
                  ' 画質 ${qualityModeLabel(s.desiredQualityMode)}'
                  '${s.title != null ? ' ${s.title}' : ''}'
                  '${isAutoPickedSchedule(ref, reg, s) ? ' ・ 自動' : ''}',
                ),
                trailing: s.priorityFlag != 0
                    ? const Icon(Icons.priority_high, size: 18)
                    : null,
                onTap: () => onSelect(s, twoPane),
              );
            },
          );
          if (!twoPane) return listView;
          RecordSchedule? selected;
          for (final s in list) {
            if (s.id == selectedId) selected = s;
          }
          return Row(
            children: [
              Expanded(flex: 5, child: listView),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                flex: 6,
                child: selected == null
                    ? const Center(child: Text('予約を選択してください'))
                    : ScheduleDetailView(reg: reg, schedule: selected),
              ),
            ],
          );
        },
      );
    }, onRetry: () => ref.invalidate(schedulesProvider(reg)));
  }
}

/// Detail page for narrow layouts; resolves the reservation from the
/// list provider so edits are reflected when the form returns.
class ScheduleDetailPage extends ConsumerWidget {
  const ScheduleDetailPage({
    super.key,
    required this.reg,
    required this.scheduleId,
  });

  final RegisteredNasne reg;
  final String scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider(reg));
    return Scaffold(
      appBar: AppBar(title: const Text('予約の詳細')),
      body: asyncSection(schedules, (list) {
        for (final s in list) {
          if (s.id == scheduleId) {
            return ScheduleDetailView(reg: reg, schedule: s);
          }
        }
        return const Center(child: Text('予約が見つかりません'));
      }, onRetry: () => ref.invalidate(schedulesProvider(reg))),
    );
  }
}

/// The reservation detail: fields plus edit / time-change / delete
/// actions implementing the plan 12.5 operation semantics.
class ScheduleDetailView extends ConsumerWidget {
  const ScheduleDetailView({
    super.key,
    required this.reg,
    required this.schedule,
    this.onDeleted,
  });

  final RegisteredNasne reg;
  final RecordSchedule schedule;

  /// Called after a successful delete (wide layouts clear the pane).
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = schedule;
    final channels = switch (s.channel.broadcastingType) {
      bsBroadcastingType => ref.watch(bsChannelsProvider(reg)).value,
      csBroadcastingType => ref.watch(csChannelsProvider(reg)).value,
      _ => ref.watch(channelsProvider(reg)).value,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // TV: the head rows are display-only; the heading block
        // holds focus (TvFocusAnchor) so D-pad traversal can
        // scroll back to the top of the detail (plan 123). The
        // action buttons at the bottom already take focus.
        TvFocusAnchor(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    s.title!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              FieldRow(
                label: 'チャンネル',
                value: channelDisplayName(channels, s.channel),
              ),
            ],
          ),
        ),
        FieldRow(label: '開始', value: formatDateTimeWithWeekdayJst(s.start)),
        FieldRow(label: '終了', value: formatDateTimeWithWeekdayJst(s.end)),
        FieldRow(label: '長さ', value: formatDurationSeconds(s.durationSeconds)),
        FieldRow(label: '画質モード', value: qualityModeLabel(s.desiredQualityMode)),
        FieldRow(label: '優先フラグ', value: '${s.priorityFlag}'),
        FieldRow(label: '条件 ID', value: s.conditionId),
        if (isAutoPickedSchedule(ref, reg, s))
          const FieldRow(label: '自動録画', value: 'おまかせ自動録画で予約しました'),
        // recordDestinationId is deliberately not shown (plan 28):
        // on a reservation it is the creator's desired/template
        // value, not the physical destination — torne's 3倍
        // template carries 'USBHDD' while the recording lands on
        // the internal HDD (the resulting title reports 'HDD').
        // Presenting it as 録画先 would state something the device
        // itself contradicts. It stays editable in the edit form,
        // which is a raw-field editor.
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ScheduleFormPage.edit(reg, s),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('編集'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ScheduleFormPage.timeChange(reg, s),
                ),
              ),
              icon: const Icon(Icons.schedule),
              label: const Text('時刻を変更'),
            ),
            OutlinedButton.icon(
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline),
              label: const Text('削除'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final s = schedule;
    final ok = await confirmDialog(
      context,
      title: '予約を削除',
      message: '${formatDateTimeWithWeekdayJst(s.start)} の予約を削除しますか？',
    );
    if (!ok) return;
    try {
      await ref
          .read(deviceServicesProvider(reg))
          .schedules
          .deleteSchedule(s.id);
    } on NasneError catch (e) {
      if (context.mounted) showSnack(context, userMessageForError(e));
      return;
    }
    ref.invalidate(schedulesProvider(reg));
    onDeleted?.call();
    if (context.mounted) {
      showSnack(context, '予約を削除しました');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }
}
