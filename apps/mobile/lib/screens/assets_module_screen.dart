import 'package:flutter/material.dart';

import 'assets_phase2_screen.dart';
import 'assets_screen.dart';

class AssetsModuleScreen extends StatelessWidget {
  const AssetsModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          Material(
            child: TabBar(
              tabs: [
                Tab(text: 'Bens', icon: Icon(Icons.home_repair_service_outlined)),
                Tab(text: 'Operações', icon: Icon(Icons.settings_suggest_outlined)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                AssetsScreen(),
                AssetsPhase2Screen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
