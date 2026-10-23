-- ============================================================
--  MAXIKIA EXPRESS — El dueño de una tienda puede ver SUS pedidos
--  Agrega una política de lectura en 'pedidos' para que el comerciante
--  vea los pedidos dirigidos a su tienda (y así prepararlos).
--  No afecta las demás políticas (se suman con OR). Ejecutar en Supabase.
-- ============================================================

drop policy if exists "pedidos_select_dueno_tienda" on public.pedidos;

create policy "pedidos_select_dueno_tienda"
  on public.pedidos for select
  using (
    tienda_id is not null
    and exists (
      select 1 from public.tiendas t
      where t.id = pedidos.tienda_id
        and t.propietario_id = auth.uid()
    )
  );

-- ============================================================
--  Con esto, en "Mi negocio" el dueño ve los pedidos de su tienda.
--  (Los pedido_items ya eran visibles para el dueño desde el archivo 31.)
-- ============================================================
