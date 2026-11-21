-- =====================================================================
-- Pulso: fotos de los jóvenes
-- Ejecutar una vez en Supabase > SQL Editor. Se puede repetir sin problema.
-- Crea la carpeta "fotos" en Storage. Cualquier profesor o el super
-- administrador puede subir, cambiar o quitar fotos desde la app.
-- Las fotos se ven por enlace (nombre aleatorio, no se pueden listar).
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1048576,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "pulso fotos subir"    on storage.objects;
drop policy if exists "pulso fotos cambiar"  on storage.objects;
drop policy if exists "pulso fotos borrar"   on storage.objects;
drop policy if exists "pulso fotos ver"      on storage.objects;

create policy "pulso fotos subir" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and public.es_miembro());
create policy "pulso fotos cambiar" on storage.objects for update to authenticated
  using (bucket_id = 'fotos' and public.es_miembro()) with check (bucket_id = 'fotos' and public.es_miembro());
create policy "pulso fotos borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and public.es_miembro());
-- Necesaria para reemplazar y borrar (solo usuarios de la app, no público)
create policy "pulso fotos ver" on storage.objects for select to authenticated
  using (bucket_id = 'fotos' and public.es_miembro());

-- Comprobación: debe mostrar la carpeta "fotos" como pública.
select id, public, file_size_limit from storage.buckets where id = 'fotos';
