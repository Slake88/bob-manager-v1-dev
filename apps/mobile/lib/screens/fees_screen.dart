import 'package:flutter/material.dart';

import 'fees_annual_screen.dart' as annual;
import 'fees_operational_screen.dart';

class FeesScreen extends StatelessWidget {
  const FeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            child: TabBar(
              tabs: [
                Tab(text: 'Operações', icon: Icon(Icons.payments_outlined)),
                Tab(text: 'Mapa anual', icon: Icon(Icons.calendar_month_outlined)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                FeesOperationalScreen(),
                annual.FeesScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
