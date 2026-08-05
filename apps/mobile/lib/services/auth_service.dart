import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_config.dart';
import '../core/app_session.dart';
class AuthService {
 AuthService._(); static final instance=AuthService._();
 Future<void> signIn(String email,String password) async {
  if(AppConfig.demoMode){AppSession.instance.authenticated=true; return;}
  final r=await Supabase.instance.client.auth.signInWithPassword(email:email,password:password);
  if(r.user==null) throw const AuthException('Falha no login.');
  final row=await Supabase.instance.client.from('club_memberships').select('club_id,profiles(full_name),membership_roles(roles(name))').eq('profile_id',r.user!.id).eq('active',true).limit(1).single();
  AppSession.instance.profileId=r.user!.id; AppSession.instance.clubId=row['club_id'].toString();
  AppSession.instance.authenticated=true;
 }
 Future<bool> restore() async { if(AppConfig.demoMode)return false; final u=Supabase.instance.client.auth.currentUser; if(u==null)return false; AppSession.instance.profileId=u.id; AppSession.instance.authenticated=true; return true; }
 Future<void> signOut() async {if(!AppConfig.demoMode)await Supabase.instance.client.auth.signOut(); AppSession.instance.authenticated=false;}
}
