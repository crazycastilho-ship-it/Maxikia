-- ============================================================
--  MAXIKIA EXPRESS — Bucket público para imágenes del marketplace
--  (logos de tiendas y fotos de productos)
--  Ejecutar en Supabase → SQL Editor.
--
--  Crea un bucket PÚBLICO llamado 'publico': cualquiera puede VER las
--  imágenes (el catálogo es público), pero solo usuarios autenticados
--  pueden SUBIR. Es distinto del bucket privado 'documentos' (cédulas),
--  que sigue protegido.
-- ============================================================

-- 1) Crear el bucket (si ya existe, lo deja público)
insert into storage.buckets (id, name, public)
values ('publico', 'publico', true)
on conflict (id) do update set public = true;

-- 2) Políticas de acceso sobre los archivos del bucket
drop policy if exists "publico_lectura"     on storage.objects;
drop policy if exists "publico_subir"        on storage.objects;
drop policy if exists "publico_actualizar"   on storage.objects;
drop policy if exists "publico_borrar"       on storage.objects;

-- LEER: público total (para mostrar logos y fotos en la app)
create policy "publico_lectura"
  on storage.objects for select
  using ( bucket_id = 'publico' );

-- SUBIR: cualquier usuario autenticado
create policy "publico_subir"
  on storage.objects for insert to authenticated
  with check ( bucket_id = 'publico' );

-- ACTUALIZAR / BORRAR: usuarios autenticados (para reemplazar imágenes)
create policy "publico_actualizar"
  on storage.objects for update to authenticated
  using ( bucket_id = 'publico' );

create policy "publico_borrar"
  on storage.objects for delete to authenticated
  using ( bucket_id = 'publico' );

-- ============================================================
--  Listo. El frontend sube a:  sb.storage.from('publico').upload(...)
--  y obtiene la URL pública con: getPublicUrl(ruta)
-- ============================================================
