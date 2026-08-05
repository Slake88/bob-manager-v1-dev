import 'package:flutter/material.dart';

import '../core/entity_definition.dart';
import 'entity_crud_screen.dart';
import 'member_detail_screen.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EntityCrudScreen(
      definition: memberDefinition,
      detailBuilder: (member) => MemberDetailScreen(member: member),
    );
  }
}
