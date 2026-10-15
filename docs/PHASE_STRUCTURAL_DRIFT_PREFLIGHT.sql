begin transaction read only;
select jsonb_build_object(
 'captured_at',now(),'version',version(),
 'relations',(select jsonb_agg(jsonb_build_object(
  'name',c.relname,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'columns',(select coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum),'[]') from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
  'constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',k.conname,'type',k.contype,'definition',pg_get_constraintdef(k.oid),'validated',k.convalidated) order by k.conname),'[]') from pg_constraint k where k.conrelid=c.oid),
  'indexes',(select coalesce(jsonb_agg(jsonb_build_object('name',ic.relname,'definition',pg_get_indexdef(i.indexrelid),'valid',i.indisvalid,'unique',i.indisunique) order by ic.relname),'[]') from pg_index i join pg_class ic on ic.oid=i.indexrelid where i.indrelid=c.oid),
  'policies',(select coalesce(jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,'roles',(select jsonb_agg(case when r=0 then 'PUBLIC' else pg_get_userbyid(r) end order by r) from unnest(p.polroles) r),'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname),'[]') from pg_policy p where p.polrelid=c.oid),
  'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',t.tgname,'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled,'function',t.tgfoid::regprocedure::text,'body',p.prosrc,'security_definer',p.prosecdef,'config',p.proconfig) order by t.tgname),'[]') from pg_trigger t join pg_proc p on p.oid=t.tgfoid where t.tgrelid=c.oid and not t.tgisinternal)
 ) order by c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p')),
 'enums',(select coalesce(jsonb_agg(jsonb_build_object('name',t.typname,'values',(select jsonb_agg(e.enumlabel order by e.enumsortorder) from pg_enum e where e.enumtypid=t.oid)) order by t.typname),'[]') from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typtype='e')
) as snapshot;
rollback;
