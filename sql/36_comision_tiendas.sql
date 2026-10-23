-- ============================================================
--  MAXIKIA EXPRESS — Comisión al comercio (marketplace)
--  Cada tienda tiene su % de comisión (por defecto 12%), ajustable
--  una por una desde el admin. Al entregar un pedido de tienda, al
--  comercio se le abona el valor de los productos MENOS la comisión;
--  esa comisión queda como ingreso de Maxikia.
--  Ejecutar en Supabase → SQL Editor. 100% aditivo.
-- ============================================================

-- 1) % de comisión por tienda + registro de la comisión en el pedido
alter table public.tiendas  add column if not exists comision_pct    numeric default 12;
alter table public.pedidos  add column if not exists comision_tienda integer default 0;

-- 2) Recrear la confirmación de entrega de tienda aplicando la comisión
create or replace function public.confirmar_entrega_tienda_segura(
  p_pedido_id uuid,
  p_foto_url  text default null
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_pedido     public.pedidos;
  v_ganancia   integer;
  v_pct        numeric;
  v_comision   integer := 0;
  v_para_tienda integer;
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

  -- Tienda: subtotal de productos MENOS la comisión de Maxikia
  if v_pedido.tienda_id is not null and coalesce(v_pedido.subtotal_productos,0) > 0 then
    select coalesce(comision_pct, 12) into v_pct from public.tiendas where id = v_pedido.tienda_id;
    v_comision    := floor(v_pedido.subtotal_productos * v_pct / 100.0);
    v_para_tienda := v_pedido.subtotal_productos - v_comision;

    update public.tiendas
    set saldo_por_liquidar = coalesce(saldo_por_liquidar,0) + v_para_tienda
    where id = v_pedido.tienda_id;

    update public.pedidos set comision_tienda = v_comision where id = p_pedido_id;
  end if;

  return v_pedido;
end;
$$;

-- ============================================================
--  Maxikia gana ahora por pedido de tienda:
--    (25% del domicilio)  +  (comisión % sobre los productos)
--  La comisión de cada pedido queda guardada en pedidos.comision_tienda.
-- ============================================================
