-- ============================================================
--  MAXIKIA EXPRESS — Banners de publicidad (pagada por comercios)
--  Tú los creas desde el admin (cuando un comercio paga su banner) y
--  se muestran en el carrusel de Inicio. Soportan imagen, enlace a una
--  tienda o URL, orden, estado y vigencia por fechas.
--  Ejecutar en Supabase → SQL Editor. 100% aditivo.
-- ============================================================

create table if not exists public.banners (
  id           uuid primary key default gen_random_uuid(),
  titulo       text,
  subtitulo    text,
  cta_texto    text default 'Ver más',
  imagen_url   text,
  color        text default 'linear-gradient(135deg,#D4001A,#FF4D62)',
  tienda_id    uuid references public.tiendas(id) on delete set null,
  url          text,
  anunciante   text,                 -- nombre del comercio que paga (referencia interna)
  activo       boolean default true,
  orden        integer default 0,
  fecha_inicio date,
  fecha_fin    date,
  created_at   timestamptz not null default now()
);

create index if not exists idx_banners_activo on public.banners(activo, orden);

-- ─────────────────────────────────────────────
--  RLS: lectura pública de banners vigentes; solo admin los gestiona.
-- ─────────────────────────────────────────────
alter table public.banners enable row level security;

drop policy if exists "banners_select_vigentes" on public.banners;
drop policy if exists "banners_admin_insert"    on public.banners;
drop policy if exists "banners_admin_update"    on public.banners;
drop policy if exists "banners_admin_delete"    on public.banners;

-- LEER: cualquiera ve los banners activos y dentro de su vigencia.
--   El admin ve todos (para gestionarlos).
create policy "banners_select_vigentes"
  on public.banners for select
  using (
    public.es_admin()
    or (
      activo = true
      and (fecha_inicio is null or fecha_inicio <= current_date)
      and (fecha_fin    is null or fecha_fin    >= current_date)
    )
  );

-- INSERT / UPDATE / DELETE: solo admin.
create policy "banners_admin_insert" on public.banners for insert with check ( public.es_admin() );
create policy "banners_admin_update" on public.banners for update using ( public.es_admin() ) with check ( public.es_admin() );
create policy "banners_admin_delete" on public.banners for delete using ( public.es_admin() );

-- ============================================================
--  Listo. Crea banners desde el admin → Publicidad.
--  Se muestran en el carrusel de Inicio de la app.
-- ============================================================
