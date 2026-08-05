import 'package:flutter/material.dart'; import 'entity_list_screen.dart';
class MembersScreen extends StatelessWidget{const MembersScreen({super.key});@override Widget build(BuildContext c)=>const EntityListScreen(title:'Membros',table:'members',primaryField:'full_name',subtitleFields:['nickname','status','phone']);}
