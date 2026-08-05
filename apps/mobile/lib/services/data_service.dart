import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_config.dart';
import '../core/app_session.dart';
class DataService {
 DataService._(); static final instance=DataService._();
 Future<List<Map<String,dynamic>>> list(String table,{String order='created_at',int limit=100}) async {
  if(AppConfig.demoMode)return demo(table);
  var q=Supabase.instance.client.from(table).select().eq('club_id',AppSession.instance.clubId).limit(limit);
  final rows=await q; return List<Map<String,dynamic>>.from(rows);
 }
 Future<Map<String,dynamic>> dashboard() async {
  if(AppConfig.demoMode)return {'members':24,'prospects':3,'total_balance':5842.70,'fee_outstanding':350.0,'open_events':4,'low_stock':7};
  final r=await Supabase.instance.client.rpc('dashboard_summary',params:{'target_club':AppSession.instance.clubId}); return Map<String,dynamic>.from(r);
 }
 Future<void> insert(String table,Map<String,dynamic> values) async {if(AppConfig.demoMode)return; await Supabase.instance.client.from(table).insert({...values,'club_id':AppSession.instance.clubId});}
 Future<void> update(String table,String id,Map<String,dynamic> values) async {if(AppConfig.demoMode)return; await Supabase.instance.client.from(table).update(values).eq('id',id).eq('club_id',AppSession.instance.clubId);}
 List<Map<String,dynamic>> demo(String table)=>switch(table){
  'members'=>[{'id':'m1','member_number':1,'full_name':'Israel Sousa','nickname':'Slake','status':'full_color','phone':'','email':''}],
  'financial_accounts'=>[{'id':'a1','name':'Caixa','account_type':'cash','opening_balance':850},{'id':'a2','name':'Banco CGD','account_type':'bank','opening_balance':3200}],
  'fee_obligations'=>[{'id':'f1','member_id':'m1','amount':25,'paid_amount':0,'status':'pending','period_start':'2026-08-01'}],
  'lottery_groups'=>[{'id':'l1','name':'Euromilhões Blue On Black','billing_frequency':'weekly','participant_amount':5,'active':true}],
  'events'=>[{'id':'e1','name':'Rock & Ride In','event_type':'rock_ride','status':'planning','starts_at':'2027-06-20T14:00:00Z'}],
  'products'=>[{'id':'p1','name':'T-shirt Blue On Black','category':'Merchandising','active':true}],
  'documents'=>[{'id':'d1','name':'Regulamento interno','category':'Regulamentos','status':'approved'}],
  'announcements'=>[{'id':'c1','title':'Próximo passeio','body':'Confirma a tua presença.','priority':'normal'}],
  _=>[]};
}
