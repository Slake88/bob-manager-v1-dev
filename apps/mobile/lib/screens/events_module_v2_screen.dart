import 'package:flutter/material.dart';

import 'events_agenda_v2_screen.dart';
import 'events_module_screen.dart';

class EventsModuleV2Screen extends StatefulWidget {
  const EventsModuleV2Screen({super.key});

  @override
  State<EventsModuleV2Screen> createState() => _EventsModuleV2ScreenState();
}

class _EventsModuleV2ScreenState extends State<EventsModuleV2Screen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          EventsAgendaV2Screen(),
          EventsAdvancedHomeScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Gestão',
          ),
        ],
      ),
    );
  }
}
