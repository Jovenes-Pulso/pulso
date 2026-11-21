-- =====================================================================
-- Pulso: archivar clases
-- Ejecutar una vez en Supabase > SQL Editor. Se puede repetir sin problema.
-- Las clases archivadas no se borran: dejan de contar en las estadísticas,
-- salvo que en Ajustes del grupo se elija incluirlas.
-- =====================================================================
alter table public.clases  add column if not exists archivada boolean not null default false;
alter table public.ajustes add column if not exists incluir_archivadas boolean not null default false;
create index if not exists clases_archivada_idx on public.clases (archivada);

-- Solo el super administrador puede archivar o desarchivar.
create or replace function public.solo_admin_archiva() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;  -- llamadas internas o con llave secreta
  if tg_op = 'INSERT' and new.archivada and not public.es_superadmin() then
    raise exception 'Solo el super administrador puede archivar clases' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.archivada is distinct from old.archivada and not public.es_superadmin() then
    raise exception 'Solo el super administrador puede archivar clases' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists clases_archivar on public.clases;
create trigger clases_archivar before insert or update on public.clases
for each row execute function public.solo_admin_archiva();

-- Comprobación: debe mostrar cuántas clases hay activas y archivadas.
select archivada, count(*) as clases from public.clases group by archivada;
