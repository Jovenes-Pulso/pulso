-- =====================================================================
-- Pulso: permisos de las tablas para la app
-- Ejecutar en SQL Editor después de schema.sql (y de uso.sql si ya lo corriste).
-- Se puede ejecutar más de una vez.
--
-- Algunos proyectos nuevos de Supabase no dan acceso automático a las
-- tablas nuevas. Sin estos permisos, el ingreso funciona pero la app no
-- puede leer el perfil ni los datos. Las reglas RLS siguen decidiendo
-- quién ve y cambia qué: esto solo abre la puerta para que se apliquen.
-- =====================================================================
grant usage on schema public to anon, authenticated, service_role;

grant select                         on public.perfiles    to authenticated;
grant select, insert, update, delete on public.jovenes     to authenticated;
grant select, insert, update, delete on public.clases      to authenticated;
grant select, insert, update, delete on public.asistencias to authenticated;
grant select, update                 on public.ajustes     to authenticated;

grant all on public.perfiles, public.jovenes, public.clases, public.asistencias, public.ajustes to service_role;

grant execute on function public.es_miembro()    to authenticated, service_role;
grant execute on function public.es_superadmin() to authenticated, service_role;

-- Tabla y funciones del panel de uso, solo si ya ejecutaste uso.sql.
do $$
begin
  if to_regclass('public.uso_diario') is not null then
    execute 'grant all on public.uso_diario to service_role';
    execute 'grant execute on function public.registrar_uso(bigint, int, int) to authenticated';
    execute 'grant execute on function public.uso_proyecto() to authenticated';
    execute 'grant execute on function public.contar_funcion() to service_role';
  end if;
end $$;

-- Comprobación: debe mostrar tu cuenta admin con rol superadmin.
select p.usuario, p.nombre, p.rol, u.email
from public.perfiles p join auth.users u on u.id = p.id;
