-- ============================================================
--  MAXIKIA EXPRESS — Unidad de venta de los productos
--  (unidad, libra, kilo, gramo, litro...) para fruver, carnicería,
--  mercado, etc. Un restaurante seguirá vendiendo por 'unidad'.
--  Ejecutar en Supabase → SQL Editor. 100% aditivo.
-- ============================================================

-- 1) Columna nueva en productos y en las líneas del pedido
alter table public.productos   add column if not exists unidad text default 'unidad';
alter table public.pedido_items add column if not exists unidad text default 'unidad';

-- 2) Recrear las funciones de creación de pedido para que guarden la unidad
--    (idénticas a las actuales, solo se agrega 'unidad' al snapshot del item)

-- ── Pedido de tienda pagado con SALDO ──
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
  v_uid uuid := auth.uid();
  v_saldo integer; v_tienda public.tiendas; v_item jsonb; v_prod public.productos;
  v_cant integer; v_subtotal integer := 0; v_envio integer; v_total integer; v_pedido public.pedidos;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;
  select * into v_tienda from public.tiendas where id = p_tienda_id;
  if v_tienda.id is null then raise exception 'La tienda no existe'; end if;
  if v_tienda.activa is not true then raise exception 'La tienda no está disponible en este momento'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'El carrito está vacío'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int, 1), 1 );
    select * into v_prod from public.productos where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;
    if v_prod.id is null then raise exception 'Un producto del carrito no pertenece a esta tienda'; end if;
    if v_prod.disponible is not true then raise exception 'El producto "%" ya no está disponible', v_prod.nombre; end if;
    v_subtotal := v_subtotal + (v_prod.precio * v_cant);
  end loop;

  if v_subtotal < coalesce(v_tienda.pedido_minimo, 0) then
    raise exception 'El pedido mínimo de esta tienda es $%', v_tienda.pedido_minimo;
  end if;

  v_envio := coalesce(v_tienda.costo_envio_base, 4000);
  v_total := v_subtotal + v_envio;

  select saldo into v_saldo from public.perfiles where id = v_uid for update;
  if v_saldo is null then raise exception 'Perfil no encontrado'; end if;
  if v_saldo < v_total then
    raise exception 'Saldo insuficiente: tienes $%, el pedido cuesta $%', v_saldo, v_total using errcode = 'P0001';
  end if;

  update public.perfiles set saldo = saldo - v_total, updated_at = now() where id = v_uid;

  insert into public.pedidos (
    usuario_id, tipo_pedido, tienda_id, origen, destino, descripcion, tipo_envio,
    lat_origen, lng_origen, lat_destino, lng_destino,
    subtotal_productos, costo_envio, precio, recibe_nombre, recibe_telefono,
    estado, notas, created_at
  ) values (
    v_uid, 'tienda', p_tienda_id, coalesce(v_tienda.direccion, v_tienda.nombre), p_destino,
    'Pedido de ' || v_tienda.nombre, 'express',
    v_tienda.lat, v_tienda.lng, p_lat_destino, p_lng_destino,
    v_subtotal, v_envio, v_total, p_recibe_nombre, p_recibe_telefono,
    'buscando', p_notas, now()
  ) returning * into v_pedido;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int, 1), 1 );
    select * into v_prod from public.productos where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;
    insert into public.pedido_items (pedido_id, producto_id, nombre, unidad, precio_unit, cantidad, subtotal, nota)
    values (v_pedido.id, v_prod.id, v_prod.nombre, coalesce(v_prod.unidad,'unidad'), v_prod.precio, v_cant, v_prod.precio * v_cant, nullif(v_item->>'nota',''));
  end loop;

  return v_pedido;
end;
$$;

-- ── Pedido de tienda pendiente de pago (tarjeta Wompi) ──
create or replace function public.crear_pedido_tienda_pendiente_pago(
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
  v_uid uuid := auth.uid();
  v_tienda public.tiendas; v_item jsonb; v_prod public.productos;
  v_cant integer; v_subtotal integer := 0; v_envio integer; v_pedido public.pedidos;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;
  select * into v_tienda from public.tiendas where id = p_tienda_id;
  if v_tienda.id is null then raise exception 'La tienda no existe'; end if;
  if v_tienda.activa is not true then raise exception 'La tienda no está disponible'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'El carrito está vacío'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int, 1), 1 );
    select * into v_prod from public.productos where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;
    if v_prod.id is null then raise exception 'Un producto no pertenece a esta tienda'; end if;
    if v_prod.disponible is not true then raise exception 'El producto "%" ya no está disponible', v_prod.nombre; end if;
    v_subtotal := v_subtotal + (v_prod.precio * v_cant);
  end loop;

  if v_subtotal < coalesce(v_tienda.pedido_minimo, 0) then
    raise exception 'El pedido mínimo de esta tienda es $%', v_tienda.pedido_minimo;
  end if;

  v_envio := coalesce(v_tienda.costo_envio_base, 4000);

  insert into public.pedidos (
    usuario_id, tipo_pedido, tienda_id, origen, destino, descripcion, tipo_envio,
    lat_origen, lng_origen, lat_destino, lng_destino,
    subtotal_productos, costo_envio, precio, recibe_nombre, recibe_telefono,
    estado, notas, created_at
  ) values (
    v_uid, 'tienda', p_tienda_id, coalesce(v_tienda.direccion, v_tienda.nombre), p_destino,
    'Pedido de ' || v_tienda.nombre, 'express',
    v_tienda.lat, v_tienda.lng, p_lat_destino, p_lng_destino,
    v_subtotal, v_envio, v_subtotal + v_envio, p_recibe_nombre, p_recibe_telefono,
    'pendiente_pago', p_notas, now()
  ) returning * into v_pedido;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := greatest( coalesce((v_item->>'cantidad')::int, 1), 1 );
    select * into v_prod from public.productos where id = (v_item->>'producto_id')::uuid and tienda_id = p_tienda_id;
    insert into public.pedido_items (pedido_id, producto_id, nombre, unidad, precio_unit, cantidad, subtotal, nota)
    values (v_pedido.id, v_prod.id, v_prod.nombre, coalesce(v_prod.unidad,'unidad'), v_prod.precio, v_cant, v_prod.precio * v_cant, nullif(v_item->>'nota',''));
  end loop;

  return v_pedido;
end;
$$;

-- ============================================================
--  Listo. Cada producto ahora tiene su unidad de venta y el pedido
--  guarda esa unidad en cada línea.
-- ============================================================
