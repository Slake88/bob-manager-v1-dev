import 'package:flutter/material.dart';

import 'events_agenda_v2_screen.dart';
import 'events_management_v2_screen.dart';

class EventsModuleV2Screen extends StatefulWidget {
  const EventsModuleV2Screen({super.key});

  @override
  State<EventsModuleV2Screen> createState() => _EventsModuleV2ScreenState();
}

class _EventsModuleV2ScreenState extends State<EventsModuleV2Screen> {
  int _index = 0;
  int _agendaRefreshToken = 0;
  int _managementRefreshToken = 0;

  void _selectTab(int value) {
    if (value == _index) return;
    setState(() {
      _index = value;
      if (value == 0) {
        _agendaRefreshToken++;
      } else {
        _managementRefreshToken++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          EventsAgendaV2Screen(refreshToken: _agendaRefreshToken),
          EventsManagementV2Screen(refreshToken: _managementRefreshToken),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
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
