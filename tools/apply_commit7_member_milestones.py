MIGRATION_1 = "-- Commit 7: datas de entrada Prospect e Full Color com edição restrita.\n-- Apenas Superadmin, Presidente e Vice-Presidente podem definir/alterar estes campos.\n\ncreate or replace function public.can_edit_member_milestone_dates_v1(target_club uuid)\nreturns boolean\nlanguage sql\nstable\nsecurity definer\nset search_path=public\nas $$\n  select (select auth.uid()) is not null\n    and exists (\n      select 1\n      from public.club_memberships cm\n      where cm.club_id=target_club\n        and cm.profile_id=(select auth.uid())\n        and cm.active=true\n        and cm.access_role in ('super_admin','president','vice_president')\n    );\n$$;\n\ncreate or replace function public.protect_member_milestone_dates_v1()\nreturns trigger\nlanguage plpgsql\nsecurity invoker\nset search_path=public\nas $$\nbegin\n  if tg_op='INSERT' then\n    if (new.prospect_joined_at is not null or new.full_colors_at is not null)\n       and not public.can_edit_member_milestone_dates_v1(new.club_id) then\n      raise exception using\n        errcode='42501',\n        message='Apenas Superadmin, Presidente ou Vice-Presidente podem definir as datas de Prospect e Full Color.';\n    end if;\n  elsif tg_op='UPDATE' then\n    if (new.prospect_joined_at is distinct from old.prospect_joined_at\n        or new.full_colors_at is distinct from old.full_colors_at)\n       and not public.can_edit_member_milestone_dates_v1(new.club_id) then\n      raise exception using\n        errcode='42501',\n        message='Apenas Superadmin, Presidente ou Vice-Presidente podem alterar as datas de Prospect e Full Color.';\n    end if;\n  end if;\n  return new;\nend;\n$$;\n\ndrop trigger if exists members_milestone_dates_insert_guard_v1 on public.members;\ncreate trigger members_milestone_dates_insert_guard_v1\nbefore insert on public.members\nfor each row execute function public.protect_member_milestone_dates_v1();\n\ndrop trigger if exists members_milestone_dates_update_guard_v1 on public.members;\ncreate trigger members_milestone_dates_update_guard_v1\nbefore update of prospect_joined_at, full_colors_at on public.members\nfor each row execute function public.protect_member_milestone_dates_v1();\n\nrevoke all on function public.can_edit_member_milestone_dates_v1(uuid) from public;\nrevoke all on function public.can_edit_member_milestone_dates_v1(uuid) from anon;\ngrant execute on function public.can_edit_member_milestone_dates_v1(uuid) to authenticated;\n\nrevoke all on function public.protect_member_milestone_dates_v1() from public;\nrevoke all on function public.protect_member_milestone_dates_v1() from anon;\nrevoke all on function public.protect_member_milestone_dates_v1() from authenticated;\n"
MIGRATION_2 = "-- Hardening: a função de autorização fica apenas para uso interno do trigger.\n\ncreate or replace function public.protect_member_milestone_dates_v1()\nreturns trigger\nlanguage plpgsql\nsecurity definer\nset search_path=public\nas $$\nbegin\n  if tg_op='INSERT' then\n    if (new.prospect_joined_at is not null or new.full_colors_at is not null)\n       and not public.can_edit_member_milestone_dates_v1(new.club_id) then\n      raise exception using\n        errcode='42501',\n        message='Apenas Superadmin, Presidente ou Vice-Presidente podem definir as datas de Prospect e Full Color.';\n    end if;\n  elsif tg_op='UPDATE' then\n    if (new.prospect_joined_at is distinct from old.prospect_joined_at\n        or new.full_colors_at is distinct from old.full_colors_at)\n       and not public.can_edit_member_milestone_dates_v1(new.club_id) then\n      raise exception using\n        errcode='42501',\n        message='Apenas Superadmin, Presidente ou Vice-Presidente podem alterar as datas de Prospect e Full Color.';\n    end if;\n  end if;\n  return new;\nend;\n$$;\n\nrevoke all on function public.can_edit_member_milestone_dates_v1(uuid) from authenticated;\nrevoke all on function public.can_edit_member_milestone_dates_v1(uuid) from anon;\nrevoke all on function public.can_edit_member_milestone_dates_v1(uuid) from public;\n\nrevoke all on function public.protect_member_milestone_dates_v1() from authenticated;\nrevoke all on function public.protect_member_milestone_dates_v1() from anon;\nrevoke all on function public.protect_member_milestone_dates_v1() from public;\n"

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

app_session = ROOT / "apps/mobile/lib/core/app_session.dart"
form = ROOT / "apps/mobile/lib/screens/entity_form_screen.dart"
members = ROOT / "apps/mobile/lib/screens/members_screen.dart"
detail = ROOT / "apps/mobile/lib/screens/member_detail_screen.dart"
test_file = ROOT / "apps/mobile/test/member_milestone_permissions_test.dart"

migration1 = ROOT / "supabase/migrations/20260811164743_rc1_member_milestone_permissions.sql"
migration2 = ROOT / "supabase/migrations/20260811164831_rc1_member_milestone_permissions_hardening.sql"

old_commit6 = ROOT / "supabase/migrations/20260811162400_rc1_euromillions_per_draw.sql"
real_commit6 = ROOT / "supabase/migrations/20260811162720_rc1_euromillions_per_draw.sql"

def replace_once(path: Path, old: str, new: str):
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(
            f"\nNão encontrei o bloco esperado em:\n{path}\n\n"
            f"Isto evita alterar o ficheiro errado. Envia-me o conteúdo do ficheiro se acontecer."
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

# 0) Corrige apenas o NOME da migration do Commit 6 para coincidir com o histórico real do Supabase.
if old_commit6.exists():
    if real_commit6.exists():
        if old_commit6.read_bytes() == real_commit6.read_bytes():
            old_commit6.unlink()
        else:
            raise SystemExit(
                "Existem duas migrations do Commit 6 com conteúdos diferentes. "
                "Não foi feita nenhuma alteração automática."
            )
    else:
        old_commit6.rename(real_commit6)

# 1) Regra fixa na sessão: não depende das permissões dinâmicas.
replace_once(
    app_session,
    "  AppRole get currentRole => AppRole.fromValue(role);\n\n"
    "  bool can(AppPermission permission) {\n",
    "  AppRole get currentRole => AppRole.fromValue(role);\n\n"
    "  bool get canEditMemberMilestoneDates =>\n"
    "      superAdmin ||\n"
    "      currentRole == AppRole.president ||\n"
    "      currentRole == AppRole.vicePresident;\n\n"
    "  bool can(AppPermission permission) {\n",
)

# 2) EntityFormScreen passa a aceitar campos dinamicamente só de leitura.
replace_once(
    form,
    "    this.initialValues,\n"
    "    this.onSave,\n"
    "  });\n\n"
    "  final EntityDefinition definition;\n"
    "  final Map<String, dynamic>? initialValues;\n"
    "  final EntitySaveHandler? onSave;\n",
    "    this.initialValues,\n"
    "    this.onSave,\n"
    "    this.readOnlyKeys = const <String>{},\n"
    "  });\n\n"
    "  final EntityDefinition definition;\n"
    "  final Map<String, dynamic>? initialValues;\n"
    "  final EntitySaveHandler? onSave;\n"
    "  final Set<String> readOnlyKeys;\n",
)

replace_once(
    form,
    "  dynamic _valueFor(EntityFieldDefinition field) {\n",
    "  bool _isReadOnly(EntityFieldDefinition field) =>\n"
    "      field.readOnly || widget.readOnlyKeys.contains(field.key);\n\n"
    "  dynamic _valueFor(EntityFieldDefinition field) {\n",
)

replace_once(
    form,
    "      if (field.readOnly) continue;\n",
    "      if (_isReadOnly(field)) continue;\n",
)

replace_once(
    form,
    "        onChanged: field.readOnly\n",
    "        onChanged: _isReadOnly(field)\n",
)

replace_once(
    form,
    "        decoration: InputDecoration(labelText: field.label),\n",
    "        decoration: InputDecoration(\n"
    "          labelText: field.label,\n"
    "          helperText: _isReadOnly(field) ? 'Sem permissão para editar este campo.' : null,\n"
    "        ),\n",
)

replace_once(
    form,
    "        onChanged: field.readOnly\n",
    "        onChanged: _isReadOnly(field)\n",
)

replace_once(
    form,
    "      readOnly: field.readOnly || isDate || isDateTime,\n",
    "      readOnly: _isReadOnly(field) || isDate || isDateTime,\n",
)

replace_once(
    form,
    "        labelText: field.label,\n"
    "        suffixIcon: isDate || isDateTime\n",
    "        labelText: field.label,\n"
    "        helperText: _isReadOnly(field) ? 'Sem permissão para editar este campo.' : null,\n"
    "        suffixIcon: isDate || isDateTime\n",
)

replace_once(
    form,
    "                onPressed: field.readOnly\n",
    "                onPressed: _isReadOnly(field)\n",
)

# Garante que qualquer controlo genérico restante respeita o bloqueio dinâmico.
_form_text = form.read_text(encoding="utf-8")
_form_text = _form_text.replace(
    "onChanged: field.readOnly",
    "onChanged: _isReadOnly(field)",
)
form.write_text(_form_text, encoding="utf-8")

# 3) Lista de membros: criação/edição mantém as duas datas visíveis, mas bloqueadas para outros cargos.
replace_once(
    members,
    "  bool get _canManage => PermissionPolicy.allows(\n"
    "        AppRole.fromValue(AppSession.instance.role),\n"
    "        AppPermission.manageMembers,\n"
    "      );\n",
    "  bool get _canManage => PermissionPolicy.allows(\n"
    "        AppRole.fromValue(AppSession.instance.role),\n"
    "        AppPermission.manageMembers,\n"
    "      );\n\n"
    "  Set<String> get _memberReadOnlyKeys =>\n"
    "      AppSession.instance.canEditMemberMilestoneDates\n"
    "          ? const <String>{}\n"
    "          : const <String>{'prospect_joined_at', 'full_colors_at'};\n",
)

replace_once(
    members,
    "          initialValues: member,\n"
    "          onSave: (values, id) async {\n",
    "          initialValues: member,\n"
    "          readOnlyKeys: _memberReadOnlyKeys,\n"
    "          onSave: (values, id) async {\n",
)

# 4) Ficha de membro: mesma regra ao editar a partir do detalhe.
replace_once(
    detail,
    "  bool get _canManage => PermissionPolicy.allows(\n"
    "        AppRole.fromValue(AppSession.instance.role),\n"
    "        AppPermission.manageMembers,\n"
    "      );\n",
    "  bool get _canManage => PermissionPolicy.allows(\n"
    "        AppRole.fromValue(AppSession.instance.role),\n"
    "        AppPermission.manageMembers,\n"
    "      );\n\n"
    "  Set<String> get _memberReadOnlyKeys =>\n"
    "      AppSession.instance.canEditMemberMilestoneDates\n"
    "          ? const <String>{}\n"
    "          : const <String>{'prospect_joined_at', 'full_colors_at'};\n",
)

replace_once(
    detail,
    "          initialValues: _member,\n"
    "          onSave: (values, id) async {\n",
    "          initialValues: _member,\n"
    "          readOnlyKeys: _memberReadOnlyKeys,\n"
    "          onSave: (values, id) async {\n",
)

# 5) Testes da regra fixa de cargos.
test_file.write_text(
    """import 'package:flutter_test/flutter_test.dart';\n"
    "import 'package:bob_manager_mobile/core/app_session.dart';\n\n"
    "void main() {\n"
    "  final session = AppSession.instance;\n\n"
    "  tearDown(session.clear);\n\n"
    "  bool allowedFor(String role) {\n"
    "    session.clear();\n"
    "    session.authenticate(\n"
    "      newProfileId: 'profile-test',\n"
    "      newClubId: 'club-test',\n"
    "      newFullName: 'Teste',\n"
    "      newRole: role,\n"
    "    );\n"
    "    return session.canEditMemberMilestoneDates;\n"
    "  }\n\n"
    "  test('Superadmin pode editar datas Prospect e Full Color', () {\n"
    "    expect(allowedFor('super_admin'), isTrue);\n"
    "  });\n\n"
    "  test('Presidente pode editar datas Prospect e Full Color', () {\n"
    "    expect(allowedFor('Presidente'), isTrue);\n"
    "  });\n\n"
    "  test('Vice-Presidente pode editar datas Prospect e Full Color', () {\n"
    "    expect(allowedFor('Vice-Presidente'), isTrue);\n"
    "  });\n\n"
    "  test('Administrador normal não recebe esta permissão fixa', () {\n"
    "    expect(allowedFor('Administrador'), isFalse);\n"
    "  });\n\n"
    "  test('Secretário não pode editar datas Prospect e Full Color', () {\n"
    "    expect(allowedFor('Secretário'), isFalse);\n"
    "  });\n"
    "}\n""".replace('"', ''),
    encoding="utf-8",
)

# O bloco acima é construído sem escapes frágeis.
# Reescrevemos explicitamente para garantir Dart válido.
test_file.write_text(
"""import 'package:flutter_test/flutter_test.dart';
import 'package:bob_manager_mobile/core/app_session.dart';

void main() {
  final session = AppSession.instance;

  tearDown(session.clear);

  bool allowedFor(String role) {
    session.clear();
    session.authenticate(
      newProfileId: 'profile-test',
      newClubId: 'club-test',
      newFullName: 'Teste',
      newRole: role,
    );
    return session.canEditMemberMilestoneDates;
  }

  test('Superadmin pode editar datas Prospect e Full Color', () {
    expect(allowedFor('super_admin'), isTrue);
  });

  test('Presidente pode editar datas Prospect e Full Color', () {
    expect(allowedFor('Presidente'), isTrue);
  });

  test('Vice-Presidente pode editar datas Prospect e Full Color', () {
    expect(allowedFor('Vice-Presidente'), isTrue);
  });

  test('Administrador normal não recebe esta permissão fixa', () {
    expect(allowedFor('Administrador'), isFalse);
  });

  test('Secretário não pode editar datas Prospect e Full Color', () {
    expect(allowedFor('Secretário'), isFalse);
  });
}
""",
    encoding="utf-8",
)

migration1.parent.mkdir(parents=True, exist_ok=True)
migration1.write_text(MIGRATION_1, encoding="utf-8")
migration2.write_text(MIGRATION_2, encoding="utf-8")

print("Commit 7 — permissões das datas Prospect / Full Color preparado com sucesso.")
print()
print("Alterações:")
print(" - Superadmin, Presidente e Vice-Presidente podem editar as duas datas.")
print(" - Outros gestores de membros continuam a editar o restante perfil, mas estas datas ficam bloqueadas.")
print(" - Proteção também existe no Supabase através de triggers.")
print(" - Foi adicionado teste automático da regra de cargos.")
if real_commit6.exists():
    print(" - Nome local da migration do Commit 6 alinhado com o histórico real do Supabase.")
