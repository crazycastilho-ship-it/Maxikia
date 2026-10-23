-- ============================================================
--  MAXIKIA EXPRESS — Tarifa de servicio del marketplace (mitad y mitad)
--  Cada tienda tiene una tarifa de servicio total (por defecto 12%),
--  ajustable una por una desde el admin. Se reparte 50/50:
--    · la mitad la paga el CLIENTE (se suma en el checkout)
--    · la mitad la asume el COMERCIO (se descuenta de su liquidación)
--  Toda la tarifa es ingreso de Maxikia.
--  Ejecutar en Supabase DESPUÉS de 35_producto_unidades.sql. Aditivo.
-- ============================================================

-- 1) Columnas
alter table public.tiendas  add column if not exists tarifa_servicio_pct numeric default 12;
alter table public.pedidos  add column if not exists tarifa_servicio      integer default 0;  -- mitad del cliente (cobrada en el total)
alter table public.pedidos  add column if not exists comision_tienda      integer default 0;  -- mitad del comercio (descontada al liquidar)

-- 2) Crear pedido de tienda con SALDO (incluye unidad + tarifa del cliente)
create or replace function public.crear_pedido_tienda_seguro(
  p_tienda_id uuid, p_items jsonb, p_destino text,
  p_lat_destino double precision default null, p_lng_destino double precision default null,
  p_recibe_nombre text default null, p_recibe_telefono text default null, p_notas text default null
)
returns public.pedidos language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_saldo integer; v_tienda public.tiendas; v_item jsonb; v_prod public.productos;
  v_cant integer; v_subtotal integer := 0; v_envio integer; v_pct numeric;
  v_tarifa integer; v_total integer; v_pedido public.pedidos;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;
  select * into v_tienda from public.tiendas where id = p_tienda_id;
  if v_tienda.id is null then raise exception 'La tienda no existe'; end if;
  if v_tienda.activa is not true then raise exception 'La tienda no está disponible en este momento'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'El carrito está vacío'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int,1), 1 );
    select * into v_prod from public.productos where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;
    if v_prod.id is null then raise exception 'Un producto del carrito no pertenece a esta tienda'; end if;
    if v_prod.disponible is not true then raise exception 'El producto "%" ya no está disponible', v_prod.nombre; end if;
    v_subtotal := v_subtotal + (v_prod.precio * v_cant);
  end loop;

  if v_subtotal < coalesce(v_tienda.pedido_minimo,0) then
    raise exception 'El pedido mínimo de esta tienda es $%', v_tienda.pedido_minimo;
  end if;

  v_pct    := coalesce(v_tienda.tarifa_servicio_pct, 12);
  v_tarifa := floor(v_subtotal * v_pct / 2.0 / 100.0);   -- mitad que paga el cliente
  v_envio  := coalesce(v_tienda.costo_envio_base, 4000);
  v_total  := v_subtotal + v_envio + v_tarifa;

  select saldo into v_saldo from public.perfiles where id = v_uid for update;
  if v_saldo is null then raise exception 'Perfil no encontrado'; end if;
  if v_saldo < v_total then
    raise exception 'Saldo insuficiente: tienes $%, el pedido cuesta $%', v_saldo, v_total using errcode='P0001';
  end if;

  update public.perfiles set saldo = saldo - v_total, updated_at = now() where id = v_uid;

  insert into public.pedidos (
    usuario_id, tipo_pedido, tienda_id, origen, destino, descripcion, tipo_envio,
    lat_origen, lng_origen, lat_destino, lng_destino,
    subtotal_productos, costo_envio, tarifa_servicio, precio, recibe_nombre, recibe_telefono,
    estado, notas, created_at
  ) values (
    v_uid, 'tienda', p_tienda_id, coalesce(v_tienda.direccion, v_tienda.nombre), p_destino,
    'Pedido de ' || v_tienda.nombre, 'express',
    v_tienda.lat, v_tienda.lng, p_lat_destino, p_lng_destino,
    v_subtotal, v_envio, v_tarifa, v_total, p_recibe_nombre, p_recibe_telefono,
    'buscando', p_notas, now()
  ) returning * into v_pedido;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int,1), 1 );
    select * into v_prod from public.productos where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;
    insert into public.pedido_items (pedido_id, producto_id, nombre, unidad, precio_unit, cantidad, subtotal, nota)
    values (v_pedido.id, v_prod.id, v_prod.nombre, coalesce(v_prod.unidad,'unidad'), v_prod.precio, v_cant, v_prod.precio*v_cant, nullif(v_item->>'nota',''));
  end loop;

  return v_pedido;
end; $$;

-- 3) Crear pedido de tienda PENDIENTE DE PAGO (tarjeta Wompi)
create or replace function public.crear_pedido_tienda_pendiente_pago(
  p_tienda_id uuid, p_items jsonb, p_destino text,
  p_lat_destino double precision default null, p_lng_destino double precision default null,
  p_recibe_nombre text default null, p_recibe_telefono text default null, p_notas text default null
)
returns public.pedidos language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tienda public.tiendas; v_item jsonb; v_prod public.productos;
  v_cant integer; v_subtotal integer := 0; v_envio integer; v_pct numeric;
  v_tarifa integer; v_pedido public.pedidos;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;
  select * into v_tienda from public.tiendas where id = p_tienda_id;
  if v_tienda.id is null then raise exception 'La tienda no existe'; end if;
  if v_tienda.activa is not true then raise exception 'La tienda no está disponible'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'El carrito está vacío'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int,1), 1 );
    select * into v_prod from public.productos where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;
    if v_prod.id is null then raise exception 'Un producto no pertenece a esta tienda'; end if;
    if v_prod.disponible is not true then raise exception 'El producto "%" ya no está disponible', v_prod.nombre; end if;
    v_subtotal := v_subtotal + (v_prod.precio * v_cant);
  end loop;

  if v_subtotal < coalesce(v_tienda.pedido_minimo,0) then
    raise exception 'El pedido mínimo de esta tienda es $%', v_tienda.pedido_minimo;
  end if;

  v_pct    := coalesce(v_tienda.tarifa_servicio_pct, 12);
  v_tarifa := floor(v_subtotal * v_pct / 2.0 / 100.0);
  v_envio  := coalesce(v_tienda.costo_envio_base, 4000);

  insert into public.pedidos (
    usuario_id, tipo_pedido, tienda_id, origen, destino, descripcion, tipo_envio,
    lat_origen, lng_origen, lat_destino, lng_destino,
    subtotal_productos, costo_envio, tarifa_servicio, precio, recibe_nombre, recibe_telefono,
    estado, notas, created_at
  ) values (
    v_uid, 'tienda', p_tienda_id, coalesce(v_tienda.direccion, v_tienda.nombre), p_destino,
    'Pedido de ' || v_tienda.nombre, 'express',
    v_tienda.lat, v_tienda.lng, p_lat_destino, p_lng_destino,
    v_subtotal, v_envio, v_tarifa, v_subtotal + v_envio + v_tarifa, p_recibe_nombre, p_recibe_telefono,
    'pendiente_pago', p_notas, now()
  ) returning * into v_pedido;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int,1), 1 );
    select * into v_prod from public.productos where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;
    insert into public.pedido_items (pedido_id, producto_id, nombre, unidad, precio_unit, cantidad, subtotal, nota)
    values (v_pedido.id, v_prod.id, v_prod.nombre, coalesce(v_prod.unidad,'unidad'), v_prod.precio, v_cant, v_prod.precio*v_cant, nullif(v_item->>'nota',''));
  end loop;

  return v_pedido;
end; $$;

-- 4) Confirmar entrega: al comercio se le descuenta su mitad de la tarifa
create or replace function public.confirmar_entrega_tienda_segura(
  p_pedido_id uuid, p_foto_url text default null
)
returns public.pedidos language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_pedido public.pedidos; v_ganancia integer; v_pct numeric;
  v_mitad_comercio integer := 0; v_para_tienda integer;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;
  select * into v_pedido from public.pedidos where id = p_pedido_id for update;
  if v_pedido.id is null then raise exception 'Pedido no existe'; end if;
  if v_pedido.tipo_pedido is distinct from 'tienda' then raise exception 'Este pedido no es de tienda; usa la confirmación normal'; end if;
  if v_pedido.repartidor_id is distinct from v_uid then raise exception 'Solo el repartidor asignado puede confirmar la entrega'; end if;
  if v_pedido.estado = 'entregado' then raise exception 'Este pedido ya fue entregado'; end if;
  if v_pedido.estado not in ('recogido','aceptado') then raise exception 'El pedido no está en un estado entregable (estado: %)', v_pedido.estado; end if;
  if p_foto_url is null or length(trim(p_foto_url)) = 0 then raise exception 'La foto de entrega es obligatoria'; end if;

  update public.pedidos
  set estado='entregado', entregado_at=now(), foto_entrega=p_foto_url, calificacion_pendiente=true
  where id = p_pedido_id returning * into v_pedido;

  -- Repartidor: 75% del domicilio
  v_ganancia := floor(coalesce(v_pedido.costo_envio,0) * 0.75);
  update public.perfiles
  set saldo = saldo + v_ganancia, entregas_completadas = coalesce(entregas_completadas,0)+1, updated_at = now()
  where id = v_uid;

  -- Comercio: subtotal menos su mitad de la tarifa de servicio
  if v_pedido.tienda_id is not null and coalesce(v_pedido.subtotal_productos,0) > 0 then
    select coalesce(tarifa_servicio_pct,12) into v_pct from public.tiendas where id = v_pedido.tienda_id;
    v_mitad_comercio := floor(v_pedido.subtotal_productos * v_pct / 2.0 / 100.0);
    v_para_tienda    := v_pedido.subtotal_productos - v_mitad_comercio;
    update public.tiendas set saldo_por_liquidar = coalesce(saldo_por_liquidar,0) + v_para_tienda where id = v_pedido.tienda_id;
    update public.pedidos set comision_tienda = v_mitad_comercio where id = p_pedido_id;
  end if;

  return v_pedido;
end; $$;

-- ============================================================
--  Ingreso de Maxikia por pedido de tienda:
--    (25% del domicilio) + tarifa_servicio (cliente) + comision_tienda (comercio)
-- ============================================================
