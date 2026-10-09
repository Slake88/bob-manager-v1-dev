import 'package:flutter/material.dart';

import 'inventory_advanced_screen.dart';
import 'inventory_hub_screen.dart';

class InventoryModuleScreen extends StatefulWidget {
  const InventoryModuleScreen({super.key});

  @override
  State<InventoryModuleScreen> createState() => _InventoryModuleScreenState();
}

class _InventoryModuleScreenState extends State<InventoryModuleScreen> {
  int _index = 0;
  int _generalRevision = 0;
  int _advancedRevision = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    icon: Icon(Icons.inventory_2_outlined),
                    label: Text('Geral'),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.layers_outlined),
                    label: Text('Stock avançado'),
                  ),
                ],
                selected: {_index},
                onSelectionChanged: (values) {
                  final nextIndex = values.first;
                  setState(() {
                    if (nextIndex == 0 && _index != 0) {
                      _generalRevision++;
                    }
                    if (nextIndex == 1 && _index != 1) {
                      _advancedRevision++;
                    }
                    _index = nextIndex;
                  });
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              InventoryHubScreen(revision: _generalRevision),
              InventoryAdvancedScreen(
                key: ValueKey(_advancedRevision),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
