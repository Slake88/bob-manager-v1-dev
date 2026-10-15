-- Membros
DROP POLICY IF EXISTS members_manage ON public.members;
CREATE POLICY members_manage ON public.members FOR ALL TO authenticated
USING (public.has_club_permission(club_id,'manageMembers'))
WITH CHECK (public.has_club_permission(club_id,'manageMembers'));
DROP POLICY IF EXISTS member_motorcycles_manage ON public.member_motorcycles;
CREATE POLICY member_motorcycles_manage ON public.member_motorcycles FOR ALL TO authenticated
USING (public.has_club_permission(club_id,'manageMembers'))
WITH CHECK (public.has_club_permission(club_id,'manageMembers'));

-- Euromilhões
DROP POLICY IF EXISTS euromillions_players_manage ON public.euromillions_players;
CREATE POLICY euromillions_players_manage ON public.euromillions_players FOR ALL TO authenticated
USING (public.has_club_permission(club_id,'manageLottery'))
WITH CHECK (public.has_club_permission(club_id,'manageLottery'));
DROP POLICY IF EXISTS euromillions_manage ON public.euromillions_draws;
CREATE POLICY euromillions_manage ON public.euromillions_draws FOR ALL TO authenticated
USING (public.has_club_permission(club_id,'manageLottery'))
WITH CHECK (public.has_club_permission(club_id,'manageLottery'));
DROP POLICY IF EXISTS euromillions_keys_manage ON public.euromillions_keys;
CREATE POLICY euromillions_keys_manage ON public.euromillions_keys FOR ALL TO authenticated
USING (EXISTS(select 1 from public.euromillions_draws d where d.id=draw_id and public.has_club_permission(d.club_id,'manageLottery')))
WITH CHECK (EXISTS(select 1 from public.euromillions_draws d where d.id=draw_id and public.has_club_permission(d.club_id,'manageLottery')));
DROP POLICY IF EXISTS euromillions_participations_manage ON public.euromillions_participations;
CREATE POLICY euromillions_participations_manage ON public.euromillions_participations FOR ALL TO authenticated
USING (EXISTS(select 1 from public.euromillions_draws d where d.id=draw_id and public.has_club_permission(d.club_id,'manageLottery')))
WITH CHECK (EXISTS(select 1 from public.euromillions_draws d where d.id=draw_id and public.has_club_permission(d.club_id,'manageLottery')));

-- Eventos
DROP POLICY IF EXISTS events_insert ON public.events;
CREATE POLICY events_insert ON public.events FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageEvents'));
DROP POLICY IF EXISTS events_update ON public.events;
CREATE POLICY events_update ON public.events FOR UPDATE TO authenticated
USING (public.has_club_permission(club_id,'manageEvents'))
WITH CHECK (public.has_club_permission(club_id,'manageEvents'));
DROP POLICY IF EXISTS events_delete ON public.events;
CREATE POLICY events_delete ON public.events FOR DELETE TO authenticated
USING (public.has_club_permission(club_id,'manageEvents'));
DROP POLICY IF EXISTS event_volunteers_insert ON public.event_volunteers;
CREATE POLICY event_volunteers_insert ON public.event_volunteers FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageEventParticipants'));
DROP POLICY IF EXISTS event_volunteers_update ON public.event_volunteers;
CREATE POLICY event_volunteers_update ON public.event_volunteers FOR UPDATE TO authenticated
USING (public.has_club_permission(club_id,'manageEventParticipants'))
WITH CHECK (public.has_club_permission(club_id,'manageEventParticipants'));
DROP POLICY IF EXISTS event_volunteers_delete ON public.event_volunteers;
CREATE POLICY event_volunteers_delete ON public.event_volunteers FOR DELETE TO authenticated
USING (public.has_club_permission(club_id,'manageEventParticipants'));
DROP POLICY IF EXISTS event_registrations_insert ON public.event_registrations;
CREATE POLICY event_registrations_insert ON public.event_registrations FOR INSERT TO authenticated
WITH CHECK (EXISTS(select 1 from public.events e where e.id=event_id and public.has_club_permission(e.club_id,'manageEventParticipants')));
DROP POLICY IF EXISTS event_registrations_update ON public.event_registrations;
CREATE POLICY event_registrations_update ON public.event_registrations FOR UPDATE TO authenticated
USING (EXISTS(select 1 from public.events e where e.id=event_id and public.has_club_permission(e.club_id,'manageEventParticipants')))
WITH CHECK (EXISTS(select 1 from public.events e where e.id=event_id and public.has_club_permission(e.club_id,'manageEventParticipants')));
DROP POLICY IF EXISTS event_registrations_delete ON public.event_registrations;
CREATE POLICY event_registrations_delete ON public.event_registrations FOR DELETE TO authenticated
USING (EXISTS(select 1 from public.events e where e.id=event_id and public.has_club_permission(e.club_id,'manageEventParticipants')));
DROP POLICY IF EXISTS event_partners_manage ON public.event_partners;
CREATE POLICY event_partners_manage ON public.event_partners FOR ALL TO authenticated
USING (EXISTS(select 1 from public.events e where e.id=event_id and public.has_club_permission(e.club_id,'manageEventParticipants')))
WITH CHECK (EXISTS(select 1 from public.events e where e.id=event_id and public.has_club_permission(e.club_id,'manageEventParticipants')));

-- Inventário
DROP POLICY IF EXISTS products_insert ON public.products;
CREATE POLICY products_insert ON public.products FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageInventory'));
DROP POLICY IF EXISTS products_update ON public.products;
CREATE POLICY products_update ON public.products FOR UPDATE TO authenticated
USING (public.has_club_permission(club_id,'manageInventory'))
WITH CHECK (public.has_club_permission(club_id,'manageInventory'));
DROP POLICY IF EXISTS products_delete ON public.products;
CREATE POLICY products_delete ON public.products FOR DELETE TO authenticated
USING (public.has_club_permission(club_id,'manageInventory'));
DROP POLICY IF EXISTS product_variants_manage ON public.product_variants;
CREATE POLICY product_variants_manage ON public.product_variants FOR ALL TO authenticated
USING (EXISTS(select 1 from public.products p where p.id=product_id and public.has_club_permission(p.club_id,'manageInventory')))
WITH CHECK (EXISTS(select 1 from public.products p where p.id=product_id and public.has_club_permission(p.club_id,'manageInventory')));
DROP POLICY IF EXISTS stock_movements_insert ON public.stock_movements;
CREATE POLICY stock_movements_insert ON public.stock_movements FOR INSERT TO authenticated
WITH CHECK ((public.has_club_permission(club_id,'manageInventory') or public.has_club_permission(club_id,'sellInventory')) and created_by=auth.uid());

-- Documentos
DROP POLICY IF EXISTS documents_select ON public.documents;
CREATE POLICY documents_select ON public.documents FOR SELECT TO authenticated
USING (public.has_club_permission(club_id,'viewDocuments') and (sensitive=false or public.has_club_permission(club_id,'viewSensitiveDocuments')));
DROP POLICY IF EXISTS documents_insert ON public.documents;
CREATE POLICY documents_insert ON public.documents FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageDocuments') and created_by=auth.uid());
DROP POLICY IF EXISTS documents_update ON public.documents;
CREATE POLICY documents_update ON public.documents FOR UPDATE TO authenticated
USING (public.has_club_permission(club_id,'manageDocuments'))
WITH CHECK (public.has_club_permission(club_id,'manageDocuments'));
DROP POLICY IF EXISTS documents_delete ON public.documents;
CREATE POLICY documents_delete ON public.documents FOR DELETE TO authenticated
USING (public.has_club_permission(club_id,'manageDocuments'));

-- Comunicação
DROP POLICY IF EXISTS announcements_insert ON public.announcements;
CREATE POLICY announcements_insert ON public.announcements FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageCommunication'));
DROP POLICY IF EXISTS announcements_update ON public.announcements;
CREATE POLICY announcements_update ON public.announcements FOR UPDATE TO authenticated
USING (public.has_club_permission(club_id,'manageCommunication'))
WITH CHECK (public.has_club_permission(club_id,'manageCommunication'));
DROP POLICY IF EXISTS announcements_delete ON public.announcements;
CREATE POLICY announcements_delete ON public.announcements FOR DELETE TO authenticated
USING (public.has_club_permission(club_id,'manageCommunication'));
DROP POLICY IF EXISTS announcement_ack_manage_read ON public.announcement_acknowledgements;
CREATE POLICY announcement_ack_manage_read ON public.announcement_acknowledgements FOR SELECT TO authenticated
USING (public.has_club_permission(club_id,'manageCommunication'));

-- Administração / Auditoria
DROP POLICY IF EXISTS audit_read ON public.audit_log;
CREATE POLICY audit_read ON public.audit_log FOR SELECT TO authenticated
USING (public.has_club_permission(club_id,'manageSettings'));
DROP POLICY IF EXISTS audit_insert ON public.audit_log;
CREATE POLICY audit_insert ON public.audit_log FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageSettings') and (actor_id is null or actor_id=auth.uid()));
DROP POLICY IF EXISTS domain_events_read ON public.domain_events;
CREATE POLICY domain_events_read ON public.domain_events FOR SELECT TO authenticated
USING (public.has_club_permission(club_id,'manageSettings'));
