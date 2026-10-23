-- ============================================================
--  MAXIKIA EXPRESS — FASE 1: Marketplace (funciones seguras)
--  Ejecutar DESPUÉS de 31_marketplace_rls.sql
--
--  El dinero y los precios NUNCA se confían al navegador:
--  estas funciones recalculan el subtotal leyendo los precios
--  reales de la tabla 'productos' en el servidor.
--
--  IMPORTANTE: NO tocamos confirmar_entrega_segura (mandados).
--  Creamos funciones NUEVAS para no arriesgar lo que ya funciona.
-- ============================================================

-- ─────────────────────────────────────────────
--  1. CREAR PEDIDO DE TIENDA  (pago con SALDO, atómico)
--
--  p_items: jsonb array -> [{"producto_id":"...","cantidad":2,"nota":"sin cebolla"}, ...]
--  El servidor recalcula el subtotal con los precios REALES.
-- ─────────────────────────────────────────────
create or replace function public.crear_pedido_tienda_seguro(
  p_tienda_id     uuid,
  p_items         jsonb,
  p_destino       text,
  p_lat_destino   double precision default null,
  p_lng_destino   double precision default null,
  p_recibe_nombre    text default null,
  p_recibe_telefono  text default null,
  p_notas         text default null
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_saldo     integer;
  v_tienda    public.tiendas;
  v_item      jsonb;
  v_prod      public.productos;
  v_cant      integer;
  v_subtotal  integer := 0;
  v_envio     integer;
  v_total     integer;
  v_pedido    public.pedidos;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;

  -- Tienda válida y activa
  select * into v_tienda from public.tiendas where id = p_tienda_id;
  if v_tienda.id is null then raise exception 'La tienda no existe'; end if;
  if v_tienda.activa is not true then raise exception 'La tienda no está disponible en este momento'; end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'El carrito está vacío';
  end if;

  -- Recalcular subtotal con precios reales del servidor
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int, 1), 1 );

    select * into v_prod
    from public.productos
    where id = (v_item->>'producto_id')::uuid
      and tienda_id = p_tienda_id;

    if v_prod.id is null then
      raise exception 'Un producto del carrito no pertenece a esta tienda';
    end if;
    if v_prod.disponible is not true then
      raise exception 'El producto "%" ya no está disponible', v_prod.nombre;
    end if;

    v_subtotal := v_subtotal + (v_prod.precio * v_cant);
  end loop;

  -- Pedido mínimo de la tienda
  if v_subtotal < coalesce(v_tienda.pedido_minimo, 0) then
    raise exception 'El pedido mínimo de esta tienda es $%', v_tienda.pedido_minimo;
  end if;

  v_envio := coalesce(v_tienda.costo_envio_base, 4000);
  v_total := v_subtotal + v_envio;

  -- Validar y descontar saldo (bloqueando la fila)
  select saldo into v_saldo from public.perfiles where id = v_uid for update;
  if v_saldo is null then raise exception 'Perfil no encontrado'; end if;
  if v_saldo < v_total then
    raise exception 'Saldo insuficiente: tienes $%, el pedido cuesta $%', v_saldo, v_total
      using errcode = 'P0001';
  end if;

  update public.perfiles set saldo = saldo - v_total, updated_at = now() where id = v_uid;

  -- Crear el pedido (reusa el flujo de repartidores: estado 'buscando')
  insert into public.pedidos (
    usuario_id, tipo_pedido, tienda_id,
    origen, destino, descripcion, tipo_envio,
    lat_origen, lng_origen, lat_destino, lng_destino,
    subtotal_productos, costo_envio, precio,
    recibe_nombre, recibe_telefono,
    estado, notas, created_at
  ) values (
    v_uid, 'tienda', p_tienda_id,
    coalesce(v_tienda.direccion, v_tienda.nombre), p_destino,
    'Pedido de ' || v_tienda.nombre, 'express',
    v_tienda.lat, v_tienda.lng, p_lat_destino, p_lng_destino,
    v_subtotal, v_envio, v_total,
    p_recibe_nombre, p_recibe_telefono,
    'buscando', p_notas, now()
  )
  returning * into v_pedido;

  -- Guardar las líneas del carrito (snapshot de nombre y precio)
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int, 1), 1 );
    select * into v_prod from public.productos
      where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;

    insert into public.pedido_items (pedido_id, producto_id, nombre, precio_unit, cantidad, subtotal, nota)
    values (v_pedido.id, v_prod.id, v_prod.nombre, v_prod.precio, v_cant, v_prod.precio * v_cant,
            nullif(v_item->>'nota',''));
  end loop;

  return v_pedido;
end;
$$;

-- ─────────────────────────────────────────────
--  2. CONFIRMAR ENTREGA DE PEDIDO DE TIENDA
--     - Al repartidor se le acredita 75% del COSTO DE ENVÍO (no del total).
--     - A la tienda se le acredita el subtotal de productos (por liquidar).
--     (Función SEPARADA: no toca la de mandados.)
-- ─────────────────────────────────────────────
create or replace function public.confirmar_entrega_tienda_segura(
  p_pedido_id uuid,
  p_foto_url  text default null
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_pedido   public.pedidos;
  v_ganancia integer;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;

  select * into v_pedido from public.pedidos where id = p_pedido_id for update;
  if v_pedido.id is null then raise exception 'Pedido no existe'; end if;
  if v_pedido.tipo_pedido is distinct from 'tienda' then
    raise exception 'Este pedido no es de tienda; usa la confirmación normal';
  end if;
  if v_pedido.repartidor_id is distinct from v_uid then
    raise exception 'Solo el repartidor asignado puede confirmar la entrega';
  end if;
  if v_pedido.estado = 'entregado' then raise exception 'Este pedido ya fue entregado'; end if;
  if v_pedido.estado not in ('recogido','aceptado') then
    raise exception 'El pedido no está en un estado entregable (estado: %)', v_pedido.estado;
  end if;
  if p_foto_url is null or length(trim(p_foto_url)) = 0 then
    raise exception 'La foto de entrega es obligatoria';
  end if;

  update public.pedidos
  set estado = 'entregado', entregado_at = now(),
      foto_entrega = p_foto_url, calificacion_pendiente = true
  where id = p_pedido_id
  returning * into v_pedido;

  -- Repartidor: 75% del costo de envío
  v_ganancia := floor(coalesce(v_pedido.costo_envio,0) * 0.75);
  update public.perfiles
  set saldo = saldo + v_ganancia,
      entregas_completadas = coalesce(entregas_completadas,0) + 1,
      updated_at = now()
  where id = v_uid;

  -- Tienda: se le abona el valor de los productos (para liquidar luego)
  if v_pedido.tienda_id is not null and coalesce(v_pedido.subtotal_productos,0) > 0 then
    update public.tiendas
    set saldo_por_liquidar = coalesce(saldo_por_liquidar,0) + v_pedido.subtotal_productos
    where id = v_pedido.tienda_id;
  end if;

  return v_pedido;
end;
$$;

-- ─────────────────────────────────────────────
--  Permisos de ejecución
-- ─────────────────────────────────────────────
grant execute on function public.crear_pedido_tienda_seguro      to authenticated;
grant execute on function public.confirmar_entrega_tienda_segura to authenticated;

-- ============================================================
--  FIN FASE 1 (backend del marketplace).
--  El pago con SALDO ya queda funcional de punta a punta.
--  (Pago con tarjeta directo para pedidos de tienda = fase 1.5,
--   se integra con tu webhook de Wompi existente.)
-- ============================================================
