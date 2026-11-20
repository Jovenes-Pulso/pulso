-- =====================================================================
-- Pulso: medición de uso para el panel "Uso de servicios" (solo super admin)
-- Ejecutar en SQL Editor DESPUÉS de schema.sql. Se puede ejecutar más de una vez.
-- =====================================================================

-- Contadores por día. La app suma lo que descarga (estimado de tráfico de
-- salida), cuántas consultas hace y cuántas veces se abre. La función
-- admin-usuarios suma sus propias llamadas.
create table if not exists public.uso_diario (
  dia          date primary key,
  egreso_bytes bigint not null default 0,
  consultas    int    not null default 0,
  aperturas    int    not null default 0,
  funciones    int    not null default 0
);
alter table public.uso_diario enable row level security;
-- Sin políticas: nadie la lee ni la escribe directamente; solo con las funciones de abajo.

create or replace function public.hoy_bogota() returns date
language sql stable as $$ select (now() at time zone 'America/Bogota')::date $$;

-- La app reporta su uso (cualquier miembro).
create or replace function public.registrar_uso(p_bytes bigint default 0, p_consultas int default 0, p_aperturas int default 0)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_miembro() then return; end if;
  insert into public.uso_diario as u (dia, egreso_bytes, consultas, aperturas)
  values (public.hoy_bogota(), least(greatest(p_bytes, 0), 52428800), least(greatest(p_consultas, 0), 10000), least(greatest(p_aperturas, 0), 100))
  on conflict (dia) do update set
    egreso_bytes = u.egreso_bytes + excluded.egreso_bytes,
    consultas    = u.consultas    + excluded.consultas,
    aperturas    = u.aperturas    + excluded.aperturas;
end $$;
revoke all on function public.registrar_uso(bigint, int, int) from public, anon;
grant execute on function public.registrar_uso(bigint, int, int) to authenticated;

-- La función del servidor cuenta sus llamadas (solo con la llave secreta).
create or replace function public.contar_funcion() returns void
language sql security definer set search_path = public as $$
  insert into public.uso_diario as u (dia, funciones) values (public.hoy_bogota(), 1)
  on conflict (dia) do update set funciones = u.funciones + 1;
$$;
revoke all on function public.contar_funcion() from public, anon, authenticated;
grant execute on function public.contar_funcion() to service_role;

-- Resumen para el panel (solo super administrador).
create or replace function public.uso_proyecto() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  mes date := date_trunc('month', public.hoy_bogota())::date;
begin
  if not public.es_superadmin() then
    raise exception 'Solo el super administrador puede ver el uso' using errcode = '42501';
  end if;
  return json_build_object(
    'generado', now(),
    'mes', mes,
    'db_bytes', pg_database_size(current_database()),
    'tablas', json_build_array(
      json_build_object('tabla', 'jovenes',     'filas', (select count(*) from public.jovenes),     'bytes', pg_total_relation_size('public.jovenes')),
      json_build_object('tabla', 'clases',      'filas', (select count(*) from public.clases),      'bytes', pg_total_relation_size('public.clases')),
      json_build_object('tabla', 'asistencias', 'filas', (select count(*) from public.asistencias), 'bytes', pg_total_relation_size('public.asistencias')),
      json_build_object('tabla', 'perfiles',    'filas', (select count(*) from public.perfiles),    'bytes', pg_total_relation_size('public.perfiles')),
      json_build_object('tabla', 'uso_diario',  'filas', (select count(*) from public.uso_diario),  'bytes', pg_total_relation_size('public.uso_diario'))
    ),
    'usuarios', (select count(*) from auth.users),
    'mau', (select count(*) from auth.users where last_sign_in_at >= mes),
    'storage_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects),
    'egreso_mes', (select coalesce(sum(egreso_bytes), 0) from public.uso_diario where dia >= mes),
    'consultas_mes', (select coalesce(sum(consultas), 0) from public.uso_diario where dia >= mes),
    'aperturas_mes', (select coalesce(sum(aperturas), 0) from public.uso_diario where dia >= mes),
    'funciones_mes', (select coalesce(sum(funciones), 0) from public.uso_diario where dia >= mes),
    'diario', (select coalesce(json_agg(json_build_object('dia', dia, 'egreso', egreso_bytes, 'consultas', consultas, 'aperturas', aperturas) order by dia), '[]'::json)
               from public.uso_diario where dia > public.hoy_bogota() - 31),
    'ultima_actividad', greatest(
      (select max(creado) from public.asistencias),
      (select max(creado) from public.clases),
      (select max(actualizado) from public.jovenes),
      (select max(last_sign_in_at) from auth.users),
      (select max(dia)::timestamptz from public.uso_diario where consultas > 0 or aperturas > 0)
    )
  );
end $$;
revoke all on function public.uso_proyecto() from public, anon;
grant execute on function public.uso_proyecto() to authenticated;
