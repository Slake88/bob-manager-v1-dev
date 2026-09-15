create or replace function public.member_motorcycle_timeline_trigger_v1()
returns trigger
language plpgsql security definer set search_path=public
as $$
declare
  v_label text;
begin
  if tg_op='DELETE' then
    if exists (
      select 1
      from public.members m
      where m.id = old.member_id
        and m.club_id = old.club_id
    ) then
      v_label:=trim(coalesce(old.brand,'')||' '||coalesce(old.model,''));
      perform public.member_timeline_append_v1(
        old.club_id,
        old.member_id,
        'motorcycle_removed',
        'Mota removida: '||coalesce(nullif(v_label,''),'Mota'),
        old.registration,
        current_date,
        'member_private',
        'member_motorcycle',
        old.id
      );
    end if;
    return old;
  end if;

  v_label:=trim(coalesce(new.brand,'')||' '||coalesce(new.model,''));
  if tg_op='INSERT' then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'motorcycle_added','Mota adicionada: '||coalesce(nullif(v_label,''),'Mota'),new.registration,coalesce(new.acquired_on,current_date),'member_private','member_motorcycle',new.id);
  elsif old.active=true and new.active=false then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'motorcycle_archived','Mota arquivada: '||coalesce(nullif(v_label,''),'Mota'),new.registration,coalesce(new.retired_on,current_date),'member_private','member_motorcycle',new.id);
  elsif old.primary_motorcycle=false and new.primary_motorcycle=true then
    perform public.member_timeline_append_v1(new.club_id,new.member_id,'motorcycle_primary','Nova mota principal: '||coalesce(nullif(v_label,''),'Mota'),new.registration,current_date,'member_private','member_motorcycle',new.id);
  end if;
  return new;
end
$$;
