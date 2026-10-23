-- ============================================================
--  MAXIKIA EXPRESS — FASE 1: Marketplace (RLS)
--  Ejecutar DESPUÉS de 30_marketplace_esquema.sql
--
--  Define quién puede ver / crear / editar tiendas y productos.
--  El catálogo es público (cualquier usuario logueado puede verlo);
--  solo el dueño de la tienda y el admin pueden editarlo.
-- ============================================================

-- ═════════════════════════════════════════════
--  TIENDAS
-- ═════════════════════════════════════════════
alter table public.tiendas enable row level security;

drop policy if exists "tiendas_select_publico"   on public.tiendas;
drop policy if exists "tiendas_insert_dueno"      on public.tiendas;
drop policy if exists "tiendas_update_dueno_admin" on public.tiendas;
drop policy if exists "tiendas_delete_admin"      on public.tiendas;

-- LEER: cualquier usuario logueado ve las tiendas ACTIVAS.
--   El dueño ve siempre la suya (activa o no) y el admin ve todas.
create policy "tiendas_select_publico"
  on public.tiendas for select
  using ( activa = true or propietario_id = auth.uid() or public.es_admin() );

-- INSERT: un usuario puede crear una tienda a su nombre; el admin a cualquiera.
create policy "tiendas_insert_dueno"
  on public.tiendas for insert
  with check ( propietario_id = auth.uid() or public.es_admin() );

-- UPDATE: solo el dueño o el admin.
--   Nota: saldo_por_liquidar solo lo cambian funciones seguras (security definer),
--   que ignoran RLS; el dueño NO puede inflarse ese campo desde el navegador
--   porque la política de abajo solo permite cambiarlo si es admin.
create policy "tiendas_update_dueno_admin"
  on public.tiendas for update
  using ( propietario_id = auth.uid() or public.es_admin() )
  with check (
    public.es_admin()
    or (
      propietario_id = auth.uid()
      and saldo_por_liquidar = (select t.saldo_por_liquidar from public.tiendas t where t.id = tiendas.id)
    )
  );

-- DELETE: solo admin (evita que un dueño borre con pedidos en curso por accidente).
create policy "tiendas_delete_admin"
  on public.tiendas for delete
  using ( public.es_admin() );

-- ═════════════════════════════════════════════
--  PRODUCTOS
-- ═════════════════════════════════════════════
alter table public.productos enable row level security;

drop policy if exists "productos_select_publico"    on public.productos;
drop policy if exists "productos_insert_dueno_admin" on public.productos;
drop policy if exists "productos_update_dueno_admin" on public.productos;
drop policy if exists "productos_delete_dueno_admin" on public.productos;

-- LEER: catálogo público (productos disponibles de tiendas activas).
--   El dueño y el admin ven todos los de su tienda.
create policy "productos_select_publico"
  on public.productos for select
  using (
    exists (
      select 1 from public.tiendas t
      where t.id = productos.tienda_id
        and ( t.activa = true or t.propietario_id = auth.uid() or public.es_admin() )
    )
  );

-- INSERT / UPDATE / DELETE: solo el dueño de la tienda o el admin.
create policy "productos_insert_dueno_admin"
  on public.productos for insert
  with check (
    public.es_admin()
    or exists ( select 1 from public.tiendas t
                where t.id = productos.tienda_id and t.propietario_id = auth.uid() )
  );

create policy "productos_update_dueno_admin"
  on public.productos for update
  using (
    public.es_admin()
    or exists ( select 1 from public.tiendas t
                where t.id = productos.tienda_id and t.propietario_id = auth.uid() )
  );

create policy "productos_delete_dueno_admin"
  on public.productos for delete
  using (
    public.es_admin()
    or exists ( select 1 from public.tiendas t
                where t.id = productos.tienda_id and t.propietario_id = auth.uid() )
  );

-- ═════════════════════════════════════════════
--  PEDIDO_ITEMS
--  (se CREAN solo vía función segura; aquí solo permitimos LEER
--   a quienes participan en el pedido)
-- ═════════════════════════════════════════════
alter table public.pedido_items enable row level security;

drop policy if exists "items_select_involucrado" on public.pedido_items;

create policy "items_select_involucrado"
  on public.pedido_items for select
  using (
    public.es_admin()
    or exists (
      select 1 from public.pedidos pe
      where pe.id = pedido_items.pedido_id
        and ( pe.usuario_id = auth.uid() or pe.repartidor_id = auth.uid() )
    )
    -- el dueño de la tienda también puede ver los items de sus pedidos:
    or exists (
      select 1 from public.pedidos pe
      join public.tiendas t on t.id = pe.tienda_id
      where pe.id = pedido_items.pedido_id
        and t.propietario_id = auth.uid()
    )
  );

-- (No creamos políticas de INSERT/UPDATE: las filas solo las escribe
--  la función crear_pedido_tienda_seguro, que corre como security definer.)

-- ============================================================
--  Siguiente archivo: 32_marketplace_funciones.sql
-- ============================================================
