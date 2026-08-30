import 'package:flutter/material.dart';

import '../core/module_definition.dart';
import 'activity_screen.dart';
import 'agenda_screen.dart';
import 'bar_screen_v3.dart';
import 'communication_module_screen.dart';
import 'dashboard_screen.dart';
import 'documents_module_screen.dart';
import 'emergency_screen.dart';
import 'events_module_screen.dart';
import 'fees_screen.dart';
import 'financial_requests_screen.dart';
import 'inventory_module_screen.dart';
import 'lottery_screen.dart';
import 'members_screen.dart';
import 'reports_hub_screen.dart';
import 'settings_screen.dart';
import 'treasury_module_screen.dart';
import 'weekly_officer_screen.dart';

class ModuleRouter extends StatelessWidget {
  const ModuleRouter({super.key, required this.module});

  final ModuleDefinition module;

  @override
  Widget build(BuildContext context) {
    return switch (module.code) {
      'dashboard' => const DashboardScreen(),
      'activity' => const ActivityScreen(),
      'members' => const MembersScreen(),
      'treasury' => const TreasuryModuleScreen(),
      'fees' => const FeesScreen(),
      'financial' => const FinancialRequestsScreen(),
      'lottery' => const LotteryScreen(),
      'events' => const EventsModuleScreen(),
      'weekly_officer' => const WeeklyOfficerScreen(),
      'agenda' => const AgendaScreen(),
      'bar' => const BarScreenV3(),
      'inventory' => const InventoryModuleScreen(),
      'documents' => const DocumentsModuleScreen(),
      'communication' => const CommunicationModuleScreen(),
      'reports' => const ReportsHubScreen(),
      'settings' => const SettingsScreen(),
      'emergency' => const EmergencyScreen(),
      _ => const SizedBox.shrink(),
    };
  }
}
