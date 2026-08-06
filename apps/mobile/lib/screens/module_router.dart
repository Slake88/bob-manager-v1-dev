import 'package:flutter/material.dart';

import '../core/module_definition.dart';
import 'communication_screen.dart';
import 'dashboard_screen.dart';
import 'documents_screen.dart';
import 'emergency_screen.dart';
import 'events_screen.dart';
import 'fees_screen.dart';
import 'inventory_screen.dart';
import 'lottery_screen.dart';
import 'members_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'treasury_screen.dart';

class ModuleRouter extends StatelessWidget {
  const ModuleRouter({super.key, required this.module});

  final ModuleDefinition module;

  @override
  Widget build(BuildContext context) {
    return switch (module.code) {
      'dashboard' => const DashboardScreen(),
      'members' => const MembersScreen(),
      'treasury' => const TreasuryScreen(),
      'fees' => const FeesScreen(),
      'lottery' => const LotteryScreen(),
      'events' => const EventsScreen(),
      'inventory' => const InventoryScreen(),
      'documents' => const DocumentsScreen(),
      'communication' => const CommunicationScreen(),
      'reports' => const ReportsScreen(),
      'settings' => const SettingsScreen(),
      'emergency' => const EmergencyScreen(),
      _ => const SizedBox.shrink(),
    };
  }
}
