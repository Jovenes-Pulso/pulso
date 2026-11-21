-- =====================================================================
-- Pulso: permisos extra para profesores
-- Ejecutar una vez en Supabase > SQL Editor. Se puede repetir sin problema.
-- El super administrador decide, profesor por profesor, si puede:
--   'eliminar'  -> eliminar jóvenes y clases
--   'archivar'  -> archivar y desarchivar clases
-- Gestionar cuentas, importar, copias y ajustes siguen siendo solo
-- del super administrador.
-- =====================================================================
alter table public.perfiles add column if not exists permisos text[] not null default '{}';

-- ¿La persona que hace la petición tiene este permiso? (el super admin los tiene todos)
create or replace function public.tiene_permiso(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfiles
                 where id = auth.uid() and (rol = 'superadmin' or p = any(permisos)));
$$;
grant execute on function public.tiene_permiso(text) to authenticated;

-- Solo el super administrador asigna permisos (los profesores no pueden dárselos a sí mismos)
create or replace function public.asignar_permisos(p_id uuid, p_permisos text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.es_superadmin() then
    raise exception 'Solo el super administrador asigna permisos' using errcode = '42501';
  end if;
  update public.perfiles
     set permisos = coalesce((select array_agg(distinct x) from unnest(p_permisos) x
                              where x in ('eliminar', 'archivar')), '{}')
   where id = p_id;
end $$;
revoke execute on function public.asignar_permisos(uuid, text[]) from public, anon;
grant execute on function public.asignar_permisos(uuid, text[]) to authenticated;

-- Eliminar jóvenes y clases: super admin o profesor con permiso
drop policy if exists jovenes_eliminar on public.jovenes;
create policy jovenes_eliminar on public.jovenes for delete to authenticated using (public.tiene_permiso('eliminar'));
drop policy if exists clases_eliminar on public.clases;
create policy clases_eliminar on public.clases for delete to authenticated using (public.tiene_permiso('eliminar'));

-- Archivar clases: super admin o profesor con permiso
-- (incluye lo de archivar.sql por si aún no se había ejecutado)
alter table public.clases  add column if not exists archivada boolean not null default false;
alter table public.ajustes add column if not exists incluir_archivadas boolean not null default false;
create or replace function public.solo_admin_archiva() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if tg_op = 'INSERT' and new.archivada and not public.tiene_permiso('archivar') then
    raise exception 'No tienes permiso para archivar clases' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.archivada is distinct from old.archivada and not public.tiene_permiso('archivar') then
    raise exception 'No tienes permiso para archivar clases' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists clases_archivar on public.clases;
create trigger clases_archivar before insert or update on public.clases
for each row execute function public.solo_admin_archiva();

-- Comprobación: lista las cuentas con sus permisos extra.
select usuario, rol, permisos from public.perfiles order by rol, usuario;
