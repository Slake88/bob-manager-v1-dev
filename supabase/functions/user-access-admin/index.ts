import { createClient, User } from 'npm:@supabase/supabase-js@2';

const H = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

type Json = Record<string, unknown>;
type AdminClient = ReturnType<typeof createClient>;

const ASSIGNABLE_ROLES = new Set([
  'president',
  'vice_president',
  'admin',
  'administrator',
  'treasurer',
  'secretary',
  'road_captain',
  'sergeant_at_arms',
  'inventory_manager',
  'event_manager',
  'events_manager',
  'euromillions_manager',
  'prospect',
  'member',
]);

function response(body: Json, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: H });
}

function text(value: unknown) {
  return typeof value === 'string' ? value.trim() : '';
}

function isBanned(value: unknown) {
  const raw = text(value);
  if (!raw) return false;
  const date = new Date(raw);
  return Number.isFinite(date.getTime()) && date.getTime() > Date.now();
}

function accountState(input: {
  profileId: string;
  membershipActive: boolean | null;
  profileActive: boolean | null;
  authUser: User | null;
}) {
  if (!input.profileId || input.membershipActive === null || input.authUser === null) {
    return 'no_access';
  }
  if (input.membershipActive === false || input.profileActive === false || isBanned(input.authUser.banned_until)) {
    return 'blocked';
  }
  if (!input.authUser.last_sign_in_at) return 'invited';
  return 'active';
}

async function allAuthUsers(admin: AdminClient) {
  const users: User[] = [];
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) break;
  }
  return users;
}

async function audit(
  admin: AdminClient,
  clubId: string,
  actorId: string,
  action: string,
  entityId: string,
  data: Json,
) {
  const { error } = await admin.from('audit_log').insert({
    club_id: clubId,
    actor_id: actorId,
    entity_type: 'user_access',
    entity_id: entityId,
    action,
    data,
  });
  if (error) throw error;
}

async function requireTarget(
  admin: AdminClient,
  clubId: string,
  profileId: string,
  callerId: string,
  callerRole: string,
) {
  const { data: membership, error } = await admin
    .from('club_memberships')
    .select('profile_id,access_role,active')
    .eq('club_id', clubId)
    .eq('profile_id', profileId)
    .maybeSingle();
  if (error) throw error;
  if (!membership) throw new Error('A conta não pertence a este clube.');
  const targetRole = text(membership.access_role);
  if (profileId === callerId) throw new Error('Não podes alterar ou bloquear a tua própria conta por este ecrã.');
  if (targetRole === 'super_admin' && callerRole !== 'super_admin') {
    throw new Error('A conta Super Admin só pode ser gerida por outro Super Admin.');
  }
  return membership as { profile_id: string; access_role: string; active: boolean };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { status: 200, headers: H });
  if (req.method !== 'POST') return response({ error: 'method_not_allowed' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  let service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}') as Record<string, string>;
    service = keys.default ?? service;
  } catch (_) {}

  if (!authHeader || !url || !anon || !service) {
    return response({ error: 'supabase_server_config_missing' }, 500);
  }

  const userClient = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const publicClient = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const body = await req.json() as Json;
    const action = text(body.action) || 'list';
    const clubId = text(body.club_id);
    if (!clubId) return response({ error: 'club_id_required' }, 400);

    const { data: callerData, error: callerError } = await userClient.auth.getUser();
    const caller = callerData.user;
    if (callerError || !caller) return response({ error: 'authentication_required' }, 401);

    const { data: allowed, error: permissionError } = await userClient.rpc('has_club_permission', {
      target_club: clubId,
      requested_permission: 'manageUserAccess',
    });
    if (permissionError) throw permissionError;
    if (allowed !== true) return response({ error: 'user_access_permission_required' }, 403);

    const { data: callerMembership, error: callerMembershipError } = await admin
      .from('club_memberships')
      .select('access_role,active')
      .eq('club_id', clubId)
      .eq('profile_id', caller.id)
      .eq('active', true)
      .maybeSingle();
    if (callerMembershipError) throw callerMembershipError;
    if (!callerMembership) return response({ error: 'active_membership_required' }, 403);
    const callerRole = text(callerMembership.access_role);

    if (action === 'list') {
      const [{ data: members, error: membersError }, { data: memberships, error: membershipsError }, { data: profiles, error: profilesError }, users] = await Promise.all([
        admin.from('members').select('id,full_name,nickname,email,profile_id,status').eq('club_id', clubId).order('full_name'),
        admin.from('club_memberships').select('profile_id,access_role,active').eq('club_id', clubId),
        admin.from('profiles').select('id,full_name,email,active'),
        allAuthUsers(admin),
      ]);
      if (membersError) throw membersError;
      if (membershipsError) throw membershipsError;
      if (profilesError) throw profilesError;

      const membershipsByProfile = new Map((memberships ?? []).map((row) => [String(row.profile_id), row]));
      const profilesById = new Map((profiles ?? []).map((row) => [String(row.id), row]));
      const usersById = new Map(users.map((row) => [row.id, row]));
      const representedProfiles = new Set<string>();
      const accounts: Json[] = [];

      for (const member of members ?? []) {
        const profileId = text(member.profile_id);
        if (profileId) representedProfiles.add(profileId);
        const membership = profileId ? membershipsByProfile.get(profileId) : null;
        const profile = profileId ? profilesById.get(profileId) : null;
        const authUser = profileId ? usersById.get(profileId) ?? null : null;
        const state = accountState({
          profileId,
          membershipActive: membership ? membership.active === true : null,
          profileActive: profile ? profile.active === true : null,
          authUser,
        });
        const role = membership ? text(membership.access_role) : '';
        accounts.push({
          member_id: member.id,
          profile_id: profileId || null,
          full_name: text(member.full_name) || text(profile?.full_name) || 'Membro',
          nickname: text(member.nickname) || null,
          member_status: text(member.status),
          email: text(authUser?.email) || text(profile?.email) || text(member.email) || null,
          access_role: role || null,
          access_state: state,
          invited_at: authUser?.invited_at ?? null,
          email_confirmed_at: authUser?.email_confirmed_at ?? null,
          last_sign_in_at: authUser?.last_sign_in_at ?? null,
          banned_until: authUser?.banned_until ?? null,
          protected: role === 'super_admin',
          self: profileId === caller.id,
        });
      }

      for (const membership of memberships ?? []) {
        const profileId = text(membership.profile_id);
        if (!profileId || representedProfiles.has(profileId)) continue;
        const profile = profilesById.get(profileId);
        const authUser = usersById.get(profileId) ?? null;
        const role = text(membership.access_role);
        accounts.push({
          member_id: null,
          profile_id: profileId,
          full_name: text(profile?.full_name) || text(authUser?.email) || 'Utilizador',
          nickname: null,
          member_status: null,
          email: text(authUser?.email) || text(profile?.email) || null,
          access_role: role || null,
          access_state: accountState({
            profileId,
            membershipActive: membership.active === true,
            profileActive: profile ? profile.active === true : null,
            authUser,
          }),
          invited_at: authUser?.invited_at ?? null,
          email_confirmed_at: authUser?.email_confirmed_at ?? null,
          last_sign_in_at: authUser?.last_sign_in_at ?? null,
          banned_until: authUser?.banned_until ?? null,
          protected: role === 'super_admin',
          self: profileId === caller.id,
        });
      }

      accounts.sort((a, b) => String(a.full_name).localeCompare(String(b.full_name), 'pt'));
      return response({ accounts });
    }

    if (action === 'invite') {
      const memberId = text(body.member_id);
      const email = text(body.email).toLowerCase();
      const role = text(body.access_role) || 'member';
      if (!memberId || !email) return response({ error: 'member_and_email_required' }, 400);
      if (!ASSIGNABLE_ROLES.has(role)) return response({ error: 'invalid_access_role' }, 400);

      const { data: member, error: memberError } = await admin
        .from('members')
        .select('id,full_name,email,profile_id')
        .eq('club_id', clubId)
        .eq('id', memberId)
        .maybeSingle();
      if (memberError) throw memberError;
      if (!member) return response({ error: 'member_not_found' }, 404);
      if (text(member.profile_id)) return response({ error: 'member_already_has_access' }, 409);

      const existingUsers = await allAuthUsers(admin);
      if (existingUsers.some((u) => text(u.email).toLowerCase() === email)) {
        return response({ error: 'email_already_registered' }, 409);
      }

      let createdUser: User | null = null;
      try {
        const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
          data: {
            full_name: text(member.full_name),
            club_id: clubId,
            member_id: memberId,
            must_set_password: true,
          },
        });
        if (inviteError) throw inviteError;
        createdUser = inviteData.user;
        if (!createdUser) throw new Error('O Supabase não devolveu o utilizador convidado.');

        const { error: profileError } = await admin.from('profiles').upsert({
          id: createdUser.id,
          full_name: text(member.full_name) || email,
          email,
          active: true,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'id' });
        if (profileError) throw profileError;

        const { error: membershipError } = await admin.from('club_memberships').upsert({
          club_id: clubId,
          profile_id: createdUser.id,
          access_role: role,
          active: true,
          created_by: caller.id,
          updated_by: caller.id,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'club_id,profile_id' });
        if (membershipError) throw membershipError;

        const { error: linkError } = await admin.from('members').update({
          profile_id: createdUser.id,
          email,
          updated_by: caller.id,
          updated_at: new Date().toISOString(),
        }).eq('club_id', clubId).eq('id', memberId);
        if (linkError) throw linkError;

        await audit(admin, clubId, caller.id, 'invite', createdUser.id, { member_id: memberId, email, access_role: role });
        return response({ ok: true, profile_id: createdUser.id, access_state: 'invited' });
      } catch (error) {
        if (createdUser) {
          try { await admin.auth.admin.deleteUser(createdUser.id); } catch (_) {}
        }
        throw error;
      }
    }

    const profileId = text(body.profile_id);
    if (!profileId) return response({ error: 'profile_id_required' }, 400);
    const targetMembership = await requireTarget(admin, clubId, profileId, caller.id, callerRole);
    const { data: targetData, error: targetError } = await admin.auth.admin.getUserById(profileId);
    if (targetError || !targetData.user) return response({ error: 'auth_user_not_found' }, 404);
    const targetUser = targetData.user;
    const email = text(targetUser.email).toLowerCase();

    if (action === 'resend_invite') {
      if (targetUser.last_sign_in_at) return response({ error: 'account_already_active' }, 409);
      const { error } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { ...targetUser.user_metadata, must_set_password: true },
      });
      if (error) throw error;
      await audit(admin, clubId, caller.id, 'resend_invite', profileId, { email });
      return response({ ok: true });
    }

    if (action === 'send_password_reset') {
      const redirectTo = text(body.redirect_to);
      const { error } = await publicClient.auth.resetPasswordForEmail(
        email,
        redirectTo ? { redirectTo } : undefined,
      );
      if (error) throw error;
      await audit(admin, clubId, caller.id, 'password_reset_sent', profileId, { email });
      return response({ ok: true });
    }

    if (action === 'block') {
      if (targetMembership.access_role === 'super_admin') {
        return response({ error: 'super_admin_cannot_be_blocked_here' }, 403);
      }
      const now = new Date().toISOString();
      const { error: membershipError } = await admin.from('club_memberships').update({
        active: false,
        updated_by: caller.id,
        updated_at: now,
      }).eq('club_id', clubId).eq('profile_id', profileId);
      if (membershipError) throw membershipError;
      const { error: profileError } = await admin.from('profiles').update({
        active: false,
        updated_at: now,
      }).eq('id', profileId);
      if (profileError) throw profileError;
      const { error: banError } = await admin.auth.admin.updateUserById(profileId, { ban_duration: '876000h' });
      if (banError) throw banError;
      await audit(admin, clubId, caller.id, 'block', profileId, { access_role: targetMembership.access_role });
      return response({ ok: true, access_state: 'blocked' });
    }

    if (action === 'unblock') {
      const now = new Date().toISOString();
      const { error: membershipError } = await admin.from('club_memberships').update({
        active: true,
        updated_by: caller.id,
        updated_at: now,
      }).eq('club_id', clubId).eq('profile_id', profileId);
      if (membershipError) throw membershipError;
      const { error: profileError } = await admin.from('profiles').update({
        active: true,
        updated_at: now,
      }).eq('id', profileId);
      if (profileError) throw profileError;
      const { error: unbanError } = await admin.auth.admin.updateUserById(profileId, { ban_duration: 'none' });
      if (unbanError) throw unbanError;
      await audit(admin, clubId, caller.id, 'unblock', profileId, { access_role: targetMembership.access_role });
      return response({ ok: true, access_state: 'active' });
    }

    if (action === 'change_role') {
      const role = text(body.access_role);
      if (!ASSIGNABLE_ROLES.has(role)) return response({ error: 'invalid_access_role' }, 400);
      if (targetMembership.access_role === 'super_admin') {
        return response({ error: 'super_admin_role_cannot_be_changed_here' }, 403);
      }
      const { error } = await admin.from('club_memberships').update({
        access_role: role,
        updated_by: caller.id,
        updated_at: new Date().toISOString(),
      }).eq('club_id', clubId).eq('profile_id', profileId);
      if (error) throw error;
      await audit(admin, clubId, caller.id, 'change_role', profileId, { from: targetMembership.access_role, to: role });
      return response({ ok: true, access_role: role });
    }

    return response({ error: 'unknown_action' }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return response({ error: message }, 500);
  }
});
