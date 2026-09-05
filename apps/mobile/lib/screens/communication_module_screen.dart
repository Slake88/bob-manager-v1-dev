import 'package:flutter/material.dart';

import 'communication_screen.dart';
import 'polls_screen.dart';

class CommunicationModuleScreen extends StatefulWidget {
  const CommunicationModuleScreen({super.key});

  @override
  State<CommunicationModuleScreen> createState() => _CommunicationModuleScreenState();
}

class _CommunicationModuleScreenState extends State<CommunicationModuleScreen> {
  int _index = 0;

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
                    icon: Icon(Icons.campaign_outlined),
                    label: Text('Comunicados'),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.how_to_vote_outlined),
                    label: Text('Votações'),
                  ),
                ],
                selected: {_index},
                onSelectionChanged: (values) => setState(() => _index = values.first),
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: const [
              CommunicationScreen(),
              PollsScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
