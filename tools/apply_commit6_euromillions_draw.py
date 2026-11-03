MIGRATION_SQL = "-- Commit 6: Euromilhões passa de custo semanal para custo por sorteio.\n-- A migration já foi validada/aplicada no Supabase real.\nalter table public.euromillions_weekly_charges rename to euromillions_draw_charges;\nalter table public.euromillions_draw_charges add column if not exists draw_date date;\nalter table public.euromillions_draw_charges drop constraint if exists euromillions_weekly_charges_club_id_player_id_week_start_key;\nalter table public.euromillions_draw_charges drop constraint if exists euromillions_draw_charges_club_id_player_id_week_start_key;\n\ninsert into public.club_settings (club_id,key,value)\nselect club_id,'euromillions_draw_amount',to_char(greatest(value::numeric / 2,0.01),'FM999999990.00')\nfrom public.club_settings where key='euromillions_weekly_amount'\non conflict (club_id,key) do nothing;\ninsert into public.club_settings (club_id,key,value)\nselect c.id,'euromillions_draw_amount','2.20' from public.clubs c\nwhere not exists (select 1 from public.club_settings s where s.club_id=c.id and s.key='euromillions_draw_amount');\n\nupdate public.euromillions_draw_charges c\nset draw_date=c.week_start+1, amount=round(c.amount/2,2), paid_amount=round(c.paid_amount/2,2)\nwhere c.draw_date is null;\n\ninsert into public.euromillions_draw_charges\n(club_id,player_id,week_start,draw_date,amount,paid_amount,paid_at,payment_method,transaction_id,created_at,created_by,updated_at,updated_by)\nselect c.club_id,c.player_id,c.week_start,c.week_start+4,c.amount,c.paid_amount,c.paid_at,c.payment_method,c.transaction_id,c.created_at,c.created_by,c.updated_at,c.updated_by\nfrom public.euromillions_draw_charges c\nwhere c.draw_date=c.week_start+1\nand not exists (select 1 from public.euromillions_draw_charges x where x.club_id=c.club_id and x.player_id=c.player_id and x.draw_date=c.week_start+4);\n\nalter table public.euromillions_draw_charges alter column draw_date set not null;\ncreate unique index if not exists euromillions_draw_charges_club_player_draw_uidx on public.euromillions_draw_charges(club_id,player_id,draw_date);\ncreate index if not exists euromillions_draw_charges_month_idx on public.euromillions_draw_charges(club_id,draw_date,player_id);\n\ncreate or replace function public.generate_euromillions_charges_v1(target_club uuid,p_year int,p_month int)\nreturns void language plpgsql security definer set search_path=public as $$\ndeclare v_amount numeric; d date; monday date;\nbegin\n if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;\n perform public.sync_euromillions_players_v1(target_club);\n select coalesce((select value::numeric from public.club_settings where club_id=target_club and key='euromillions_draw_amount'),2.20) into v_amount;\n d:=make_date(p_year,p_month,1);\n while extract(month from d)=p_month loop\n  if extract(isodow from d) in (2,5) then\n   monday:=d-(extract(isodow from d)::int-1);\n   insert into public.euromillions_draw_charges(club_id,player_id,week_start,draw_date,amount)\n   select target_club,p.id,monday,d,v_amount from public.euromillions_players p where p.club_id=target_club and p.status='active'\n   on conflict (club_id,player_id,draw_date) do nothing;\n  end if;\n  d:=d+1;\n end loop;\nend; $$;\n\ncreate or replace function public.register_euromillions_draw_payment_v1(target_club uuid,p_charge uuid,p_payment_method text default null)\nreturns void language plpgsql security definer set search_path=public as $$\ndeclare c public.euromillions_draw_charges%rowtype; acc uuid; tx uuid; remaining numeric;\nbegin\n if not public.has_club_permission(target_club,'manageLottery') then raise exception 'Sem permissão para registar pagamentos.'; end if;\n select * into c from public.euromillions_draw_charges where id=p_charge and club_id=target_club for update;\n if c.id is null then raise exception 'Cobrança não encontrada.'; end if;\n remaining:=greatest(c.amount-c.paid_amount,0); if remaining=0 then return; end if;\n select id into acc from public.treasury_accounts where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;\n if acc is null then raise exception 'Conta Euromilhões não encontrada.'; end if;\n insert into public.treasury_transactions(club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by)\n values(target_club,'income',acc,current_date,'Pagamento Euromilhões - sorteio '||to_char(c.draw_date,'DD/MM/YYYY'),remaining,p_payment_method,'euromillions_draw_charge',c.id,auth.uid()) returning id into tx;\n update public.euromillions_draw_charges set paid_amount=amount,paid_at=now(),payment_method=p_payment_method,transaction_id=tx where id=c.id;\nend; $$;\n\ncreate or replace function public.register_euromillions_month_payment_v1(target_club uuid,p_player uuid,p_year int,p_month int,p_payment_method text default null)\nreturns void language plpgsql security definer set search_path=public as $$\ndeclare r record;\nbegin\n if not public.has_club_permission(target_club,'manageLottery') then raise exception 'Sem permissão para registar pagamentos.'; end if;\n perform public.generate_euromillions_charges_v1(target_club,p_year,p_month);\n for r in select id from public.euromillions_draw_charges where club_id=target_club and player_id=p_player and extract(year from draw_date)=p_year and extract(month from draw_date)=p_month and paid_amount<amount order by draw_date loop\n  perform public.register_euromillions_draw_payment_v1(target_club,r.id,p_payment_method);\n end loop;\nend; $$;\n\ndrop function if exists public.register_euromillions_week_payment_v1(uuid,uuid,text);\ngrant execute on function public.register_euromillions_draw_payment_v1(uuid,uuid,text) to authenticated;\ngrant execute on function public.generate_euromillions_charges_v1(uuid,int,int) to authenticated;\ngrant execute on function public.register_euromillions_month_payment_v1(uuid,uuid,int,int,text) to authenticated;\nalter policy euromillions_charges_read on public.euromillions_draw_charges rename to euromillions_draw_charges_read;\n"

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
repo = ROOT / "apps/mobile/lib/repositories/lottery_repository.dart"
screen = ROOT / "apps/mobile/lib/screens/lottery_screen_v2.dart"
migration = ROOT / "supabase/migrations/20260811162400_rc1_euromillions_per_draw.sql"

def rep(path, old, new):
    text = path.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"Bloco esperado não encontrado em {path}: {old[:120]}")
    path.write_text(text.replace(old, new), encoding="utf-8")

rep(repo, "'weekly_amount': 4.40,", "'draw_amount': 2.20,")
rep(repo, ".from('euromillions_weekly_charges')", ".from('euromillions_draw_charges')")
rep(repo, ".gte('week_start', _dateOnly(chargeStart))\n          .lt('week_start', nextIso)\n          .order('week_start')",
          ".gte('draw_date', firstIso)\n          .lt('draw_date', nextIso)\n          .order('draw_date')")
rep(repo, "'euromillions_weekly_amount',", "'euromillions_draw_amount',")
rep(repo, "'weekly_amount':\n          double.tryParse(settings['euromillions_weekly_amount'] ?? '') ?? 4.40,",
          "'draw_amount':\n          double.tryParse(settings['euromillions_draw_amount'] ?? '') ?? 2.20,")
rep(repo, "required double weeklyAmount,", "required double drawAmount,")
rep(repo, "if (weeklyAmount <= 0 || finePerMiss < 0)", "if (drawAmount <= 0 || finePerMiss < 0)")
rep(repo, "'euromillions_weekly_amount': weeklyAmount.toStringAsFixed(2),",
          "'euromillions_draw_amount': drawAmount.toStringAsFixed(2),")
rep(repo, "Future<void> payWeek({", "Future<void> payDraw({")
rep(repo, "'register_euromillions_week_payment_v1',", "'register_euromillions_draw_payment_v1',")

rep(screen, "_payWeek", "_payDraw")
rep(screen, "payWeek(", "payDraw(")
rep(screen, "weeklyAmount: _asDouble(data['weekly_amount']),", "drawAmount: _asDouble(data['draw_amount']),")
rep(screen, "final weeklyAmount = _asDouble(data['weekly_amount']);\n          final weeks = drawDates.map(_repository.weekStart).map(_dateOnly).toSet();\n          final monthlyPerPlayer = weeks.length * weeklyAmount;",
          "final drawAmount = _asDouble(data['draw_amount']);\n          final monthlyPerPlayer = drawDates.length * drawAmount;")
rep(screen, "onPayWeek:", "onPayDraw:")
rep(screen, "required this.onPayWeek,", "required this.onPayDraw,")
rep(screen, "final Future<void> Function(Map<String, dynamic>)? onPayWeek;", "final Future<void> Function(Map<String, dynamic>)? onPayDraw;")
rep(screen, "final week = _dateOnly(repository.weekStart(drawDate));", "final draw = _dateOnly(drawDate);")
rep(screen, "row['week_start']?.toString() == week", "row['draw_date']?.toString() == draw")
rep(screen, "message: 'Semana liquidada'", "message: 'Sorteio liquidado'")
rep(screen, "if (onPayWeek == null)", "if (onPayDraw == null)")
rep(screen, "tooltip: 'Registar pagamento desta semana',", "tooltip: 'Registar pagamento deste sorteio',")
rep(screen, "onPressed: () => onPayWeek!(current),", "onPressed: () => onPayDraw!(current),")
rep(screen, "required this.weeklyAmount,", "required this.drawAmount,")
rep(screen, "final double weeklyAmount;", "final double drawAmount;")
rep(screen, "late final TextEditingController _weekly;", "late final TextEditingController _draw;")
rep(screen, "_weekly = TextEditingController(text: widget.weeklyAmount.toStringAsFixed(2));", "_draw = TextEditingController(text: widget.drawAmount.toStringAsFixed(2));")
rep(screen, "_weekly.dispose();", "_draw.dispose();")
rep(screen, "final weekly = double.tryParse(_weekly.text.replaceAll(',', '.'));", "final draw = double.tryParse(_draw.text.replaceAll(',', '.'));")
rep(screen, "if (weekly == null || fine == null) return;", "if (draw == null || fine == null) return;")
rep(screen, "saveSettings(weeklyAmount: weekly, finePerMiss: fine)", "saveSettings(drawAmount: draw, finePerMiss: fine)")
rep(screen, "controller: _weekly,", "controller: _draw,")
rep(screen, "labelText: 'Valor semanal por jogador (€)'", "labelText: 'Custo por sorteio / jogador (€)'")

migration.parent.mkdir(parents=True, exist_ok=True)
migration.write_text(MIGRATION_SQL, encoding="utf-8")

print("Commit 6 — Euromilhões por sorteio preparado com sucesso.")
print("Ficheiros alterados:")
print(" - apps/mobile/lib/repositories/lottery_repository.dart")
print(" - apps/mobile/lib/screens/lottery_screen_v2.dart")
print(" - supabase/migrations/20260811162400_rc1_euromillions_per_draw.sql")
