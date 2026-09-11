create or replace function public.member_status_timeline_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $function$
begin
  if tg_op='INSERT' then
    insert into public.member_status_history(
      club_id,member_id,old_status,new_status,changed_at,changed_by
    )
    values(
      new.club_id,new.id,null,new.status,coalesce(new.created_at,now()),auth.uid()
    );

    perform public.member_timeline_append_v1(
      new.club_id,
      new.id,
      'member_created',
      'Membro criado',
      new.status::text,
      coalesce(new.joined_at,current_date),
      'club',
      'member',
      new.id
    );

    if new.prospect_joined_at is not null then
      perform public.member_timeline_append_v1(
        new.club_id,new.id,'prospect_joined','Entrada como Prospect',null,
        new.prospect_joined_at,'club','member',new.id
      );
    end if;

    if new.full_colors_at is not null then
      perform public.member_timeline_append_v1(
        new.club_id,new.id,'full_colors','Full Colors',null,
        new.full_colors_at,'club','member',new.id
      );
    end if;

    return new;
  end if;

  if old.status is distinct from new.status then
    insert into public.member_status_history(
      club_id,member_id,old_status,new_status,changed_at,changed_by
    )
    values(
      new.club_id,new.id,old.status,new.status,now(),auth.uid()
    );

    perform public.member_timeline_append_v1(
      new.club_id,
      new.id,
      'status_change',
      'Estado alterado para '||coalesce(new.status::text,'-'),
      'Anterior: '||coalesce(old.status::text,'-'),
      current_date,
      'club',
      'member',
      new.id
    );
  end if;

  if old.prospect_joined_at is distinct from new.prospect_joined_at
     and new.prospect_joined_at is not null then
    perform public.member_timeline_append_v1(
      new.club_id,new.id,'prospect_joined','Entrada como Prospect',null,
      new.prospect_joined_at,'club','member',new.id
    );
  end if;

  if old.full_colors_at is distinct from new.full_colors_at
     and new.full_colors_at is not null then
    perform public.member_timeline_append_v1(
      new.club_id,new.id,'full_colors','Full Colors',null,
      new.full_colors_at,'club','member',new.id
    );
  end if;

  return new;
end
$function$;
