-- =====================================================================
-- Pulso: esquema para Supabase (fase 2, borrador)
-- Ejecutar completo en: Supabase > SQL Editor > New query
-- =====================================================================

-- ---------- Tablas ----------

-- Una fila por cuenta. Se borra sola cuando se elimina el usuario de Auth.
create table if not exists public.perfiles (
  id      uuid primary key references auth.users(id) on delete cascade,
  usuario text not null unique check (usuario ~ '^[a-z0-9._]{3,20}$'),
  nombre  text not null,
  rol     text not null default 'profesor' check (rol in ('superadmin', 'profesor')),
  creado  timestamptz not null default now()
);

-- id en texto para conservar los IDs que vienen de Bubble.
create table if not exists public.jovenes (
  id               text primary key default gen_random_uuid()::text,
  nombres          text,
  apellidos        text,
  edad             int,
  fecha_nacimiento date,
  curso            text,
  acudiente        text,
  telefono         text,
  fecha_ingreso    date,
  foto             text,
  notas            text,
  por_identificar  boolean not null default false,
  ids_anteriores   text[] not null default '{}',
  creado           timestamptz not null default now(),
  actualizado      timestamptz not null default now()
);

create table if not exists public.clases (
  id                    text primary key default gen_random_uuid()::text,
  fecha                 date not null,
  servicio              text,
  tema                  text,
  ponente               text,
  notas                 text,
  -- si se elimina la cuenta del profesor, la clase conserva su nombre
  registrado_por        uuid references public.perfiles(id) on delete set null,
  registrado_por_nombre text,
  archivada             boolean not null default false,
  creado                timestamptz not null default now()
);
create index if not exists clases_fecha_idx on public.clases (fecha);

create table if not exists public.asistencias (
  clase_id    text not null references public.clases(id) on delete cascade,
  joven_id    text not null references public.jovenes(id) on delete cascade,
  marcado_por uuid references public.perfiles(id) on delete set null,
  creado      timestamptz not null default now(),
  primary key (clase_id, joven_id)
);
create index if not exists asistencias_joven_idx on public.asistencias (joven_id);

create table if not exists public.ajustes (
  id       int primary key default 1 check (id = 1),
  grupo    text not null default 'Grupo de jóvenes',
  servicio text,
  riesgo   int not null default 3,
  inactivo int not null default 8,
  incluir_archivadas boolean not null default false
);
insert into public.ajustes (id) values (1) on conflict do nothing;

-- ---------- Fecha de actualización automática ----------
create or replace function public.tocar_actualizado() returns trigger
language plpgsql as $$
begin new.actualizado := now(); return new; end $$;

drop trigger if exists jovenes_actualizado on public.jovenes;
create trigger jovenes_actualizado before update on public.jovenes
for each row execute function public.tocar_actualizado();

-- ---------- Quién puede qué ----------
-- Se revisa en cada consulta: si se elimina una cuenta, su perfil
-- desaparece y pierde el acceso de inmediato, aunque su sesión siga abierta.
create or replace function public.es_miembro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid());
$$;

create or replace function public.es_superadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'superadmin');
$$;

alter table public.perfiles    enable row level security;
alter table public.jovenes     enable row level security;
alter table public.clases      enable row level security;
alter table public.asistencias enable row level security;
alter table public.ajustes     enable row level security;

-- Perfiles: todos los miembros los ven; solo se crean, cambian y borran
-- desde la función admin-usuarios (usa la llave de servicio).
create policy perfiles_ver on public.perfiles for select to authenticated using (public.es_miembro());

-- Jóvenes: profesores ven, crean y editan; solo el super admin elimina.
create policy jovenes_ver      on public.jovenes for select to authenticated using (public.es_miembro());
create policy jovenes_crear    on public.jovenes for insert to authenticated with check (public.es_miembro());
create policy jovenes_editar   on public.jovenes for update to authenticated using (public.es_miembro()) with check (public.es_miembro());
create policy jovenes_eliminar on public.jovenes for delete to authenticated using (public.es_superadmin());

-- Clases: igual que jóvenes.
create policy clases_ver      on public.clases for select to authenticated using (public.es_miembro());
create policy clases_crear    on public.clases for insert to authenticated with check (public.es_miembro());
create policy clases_editar   on public.clases for update to authenticated using (public.es_miembro()) with check (public.es_miembro());
create policy clases_eliminar on public.clases for delete to authenticated using (public.es_superadmin());

-- Asistencias: marcar y desmarcar es parte de tomar lista.
create policy asistencias_ver      on public.asistencias for select to authenticated using (public.es_miembro());
create policy asistencias_marcar   on public.asistencias for insert to authenticated with check (public.es_miembro());
create policy asistencias_desmarcar on public.asistencias for delete to authenticated using (public.es_miembro());

-- Ajustes: todos los leen; solo el super admin los cambia.
create policy ajustes_ver    on public.ajustes for select to authenticated using (public.es_miembro());
create policy ajustes_editar on public.ajustes for update to authenticated using (public.es_superadmin()) with check (public.es_superadmin());


-- ---------- Permisos de acceso para la app ----------
-- Algunos proyectos nuevos no dan acceso automático a tablas nuevas.
grant usage on schema public to anon, authenticated, service_role;
grant select                         on public.perfiles    to authenticated;
grant select, insert, update, delete on public.jovenes     to authenticated;
grant select, insert, update, delete on public.clases      to authenticated;
grant select, insert, update, delete on public.asistencias to authenticated;
grant select, update                 on public.ajustes     to authenticated;
grant all on public.perfiles, public.jovenes, public.clases, public.asistencias, public.ajustes to service_role;
grant execute on function public.es_miembro()    to authenticated, service_role;
grant execute on function public.es_superadmin() to authenticated, service_role;

-- ---------- Solo el super administrador archiva clases ----------
create or replace function public.solo_admin_archiva() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
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

-- ---------- Tiempo real ----------
-- Para que la asistencia que marca un profesor aparezca sola en el
-- celular de otro, Supabase debe publicar los cambios de estas tablas.
alter publication supabase_realtime add table public.asistencias, public.clases, public.jovenes, public.perfiles, public.ajustes;

-- =====================================================================
-- Primer super administrador (una sola vez)
-- 1. Authentication > Sign In / Providers > Email: desactiva
--    "Allow new users to sign up" y "Confirm email".
-- 2. Authentication > Users > Add user > Create new user:
--    correo admin@pulso.app, tu contraseña, marca "Auto Confirm User".
--    (admin@pulso.app es una cuenta técnica: no necesita existir ni se lee.)
-- 3. Ejecuta esto cambiando el nombre:
--
-- insert into public.perfiles (id, usuario, nombre, rol)
-- select id, 'admin', 'Tu nombre', 'superadmin' from auth.users where email = 'admin@pulso.app';
-- =====================================================================
