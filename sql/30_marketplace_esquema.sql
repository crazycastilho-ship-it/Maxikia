-- ============================================================
--  MAXIKIA EXPRESS — FASE 1: Marketplace (tipo Rappi)
--  Base de datos: tiendas + productos + carrito
--
--  Ejecutar en: Supabase → SQL Editor → New query → Run
--
--  ✅ 100% ADITIVO y SEGURO para producción:
--     - NO borra ni modifica ninguna tabla existente.
--     - NO toca el flujo de mandados que ya está funcionando.
--     - Todo usa "if not exists" / "add column if not exists".
--     - Reusa tu infraestructura actual: pedidos, repartidores,
--       pagos (saldo/Wompi), realtime y confirmación de entrega.
--  Es seguro re-ejecutarlo.
-- ============================================================

-- ─────────────────────────────────────────────
--  0. Reutilizamos es_admin() (ya existe en tu BD).
--     La redefinimos por si acaso, sin romper nada.
-- ─────────────────────────────────────────────
create or replace function public.es_admin()
returns boolean
language sql security definer set search_path = public stable
as $$
  select coalesce((select rol = 'admin' from public.perfiles where id = auth.uid()), false);
$$;

-- ═════════════════════════════════════════════
--  TABLA: tiendas  (restaurantes, mercados, farmacias, licoreras...)
-- ═════════════════════════════════════════════
create table if not exists public.tiendas (
  id                 uuid primary key default gen_random_uuid(),
  propietario_id     uuid references auth.users(id) on delete set null,
  nombre             text not null,
  categoria          text not null default 'comida',   -- comida | mercado | farmacia | licores | otros
  descripcion        text,
  direccion          text,
  lat                double precision,
  lng                double precision,
  logo_url           text,
  portada_url        text,
  telefono           text,
  horario            text,                              -- texto libre: "Lun-Dom 8am-10pm"
  tiempo_entrega_min integer default 30,                -- estimado en minutos
  costo_envio_base   integer default 4000,             -- domicilio por defecto de esta tienda
  pedido_minimo      integer default 0,
  activa             boolean default true,
  destacada          boolean default false,
  saldo_por_liquidar integer default 0,                 -- lo que la plataforma le debe a la tienda
  created_at         timestamptz not null default now()
);

-- Por si la tabla ya existía incompleta:
alter table public.tiendas add column if not exists propietario_id     uuid;
alter table public.tiendas add column if not exists categoria          text default 'comida';
alter table public.tiendas add column if not exists descripcion        text;
alter table public.tiendas add column if not exists direccion          text;
alter table public.tiendas add column if not exists lat                double precision;
alter table public.tiendas add column if not exists lng                double precision;
alter table public.tiendas add column if not exists logo_url           text;
alter table public.tiendas add column if not exists portada_url        text;
alter table public.tiendas add column if not exists telefono           text;
alter table public.tiendas add column if not exists horario            text;
alter table public.tiendas add column if not exists tiempo_entrega_min integer default 30;
alter table public.tiendas add column if not exists costo_envio_base   integer default 4000;
alter table public.tiendas add column if not exists pedido_minimo      integer default 0;
alter table public.tiendas add column if not exists activa             boolean default true;
alter table public.tiendas add column if not exists destacada          boolean default false;
alter table public.tiendas add column if not exists saldo_por_liquidar integer default 0;

-- ═════════════════════════════════════════════
--  TABLA: productos
-- ═════════════════════════════════════════════
create table if not exists public.productos (
  id           uuid primary key default gen_random_uuid(),
  tienda_id    uuid not null references public.tiendas(id) on delete cascade,
  nombre       text not null,
  descripcion  text,
  precio       integer not null default 0,
  imagen_url   text,
  categoria    text,                 -- categoría DENTRO de la tienda: "Hamburguesas", "Bebidas"...
  disponible   boolean default true,
  orden        integer default 0,    -- para ordenar el menú
  created_at   timestamptz not null default now()
);

alter table public.productos add column if not exists categoria  text;
alter table public.productos add column if not exists disponible boolean default true;
alter table public.productos add column if not exists orden      integer default 0;

create index if not exists idx_productos_tienda on public.productos(tienda_id);

-- ═════════════════════════════════════════════
--  EXTENDER 'pedidos' para soportar pedidos de tienda
--  (los mandados existentes quedan intactos: tipo_pedido = 'mandado')
-- ═════════════════════════════════════════════
alter table public.pedidos add column if not exists tipo_pedido        text default 'mandado';  -- 'mandado' | 'tienda'
alter table public.pedidos add column if not exists tienda_id          uuid;
alter table public.pedidos add column if not exists subtotal_productos integer default 0;
alter table public.pedidos add column if not exists costo_envio        integer default 0;
-- Datos del destinatario (por si la migración anterior usó otro nombre)
alter table public.pedidos add column if not exists recibe_nombre      text;
alter table public.pedidos add column if not exists recibe_telefono    text;

-- ═════════════════════════════════════════════
--  TABLA: pedido_items  (líneas del carrito de un pedido de tienda)
-- ═════════════════════════════════════════════
create table if not exists public.pedido_items (
  id           uuid primary key default gen_random_uuid(),
  pedido_id    uuid not null references public.pedidos(id) on delete cascade,
  producto_id  uuid references public.productos(id) on delete set null,
  nombre       text not null,        -- snapshot del nombre al momento de la compra
  precio_unit  integer not null,     -- snapshot del precio al momento de la compra
  cantidad     integer not null default 1,
  subtotal     integer not null,
  nota         text
);

create index if not exists idx_pedido_items_pedido on public.pedido_items(pedido_id);

-- ============================================================
--  Siguiente archivo: 31_marketplace_rls.sql
-- ============================================================
