/// The app shell (plan 5.6 / 12.7): six destinations — home /
/// status, live viewing (plan 39), schedules, recorded titles,
/// programme guide, settings — with the navigation form switching
/// by width: a bottom navigation bar on phones, a side rail on
/// tablets and wider layouts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/auto_record_providers.dart';
import '../app/state.dart';
import 'epg_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'schedules_screen.dart';
import 'settings_screen.dart';
import 'titles_screen.dart';

/// Width at or above which the shell uses a navigation rail.
const double railBreakpoint = 720;

/// Minimum top clearance guaranteed in the rail (wide) layout, in
/// logical pixels. Some environments (LiveContainer on iPad, observed
/// 2026-11-17) report a top safe-area inset smaller than the status
/// bar actually drawn over the app, which left the rail and the
/// screens' app bars flush with the top edge of the screen. The
/// screens' app bars already consume the reported inset, so the shell
/// only tops up the shortfall below this floor; where the inset is
/// reported correctly nothing is added. The phone (bottom bar) layout
/// is unaffected.
const double wideLayoutMinTopInset = 24;

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _destinations = [
    (icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'ホーム'),
    (icon: Icons.live_tv_outlined, selectedIcon: Icons.live_tv, label: 'TV視聴'),
    (
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      label: '予約',
    ),
    (
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library,
      label: '録画済み',
    ),
    (
      icon: Icons.view_week_outlined,
      selectedIcon: Icons.view_week,
      label: '番組表',
    ),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '設定'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabIndexProvider);
    // Fires the auto record startup check once per app
    // session (user-fork addition; see
    // app/auto_record_providers.dart).
    ref.watch(autoRecordStartupProvider);
    final screens = const [
      HomeScreen(),
      LiveScreen(),
      SchedulesScreen(),
      TitlesScreen(),
      EpgScreen(),
      SettingsScreen(),
    ];
    void select(int index) => ref.read(tabIndexProvider.notifier).select(index);

    return LayoutBuilder(
      builder: (context, constraints) {
        final body = IndexedStack(index: tab, children: screens);
        if (constraints.maxWidth >= railBreakpoint) {
          final reportedTopInset = MediaQuery.paddingOf(context).top;
          final extraTop = wideLayoutMinTopInset > reportedTopInset
              ? wideLayoutMinTopInset - reportedTopInset
              : 0.0;
          return Scaffold(
            body: Padding(
              padding: EdgeInsets.only(top: extraTop),
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: tab,
                    onDestinationSelected: select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(child: body),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: select,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
