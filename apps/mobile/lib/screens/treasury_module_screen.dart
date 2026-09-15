import 'package:flutter/material.dart';

import 'treasury_operational_screen.dart';
import 'treasury_reports_screen.dart';
import 'treasury_screen.dart';

class TreasuryModuleScreen extends StatelessWidget {
  const TreasuryModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            child: TabBar(
              tabs: [
                Tab(text: 'Resumo', icon: Icon(Icons.account_balance_wallet_outlined)),
                Tab(text: 'Operações', icon: Icon(Icons.tune_outlined)),
                Tab(text: 'Relatórios', icon: Icon(Icons.assessment_outlined)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                TreasuryScreen(),
                TreasuryOperationalScreen(),
                TreasuryReportsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
