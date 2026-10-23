-- ============================================================
--  MAXIKIA — Aviso push al comercio cuando entra un pedido
--  Ejecutar en Supabase → SQL Editor DESPUÉS de desplegar la
--  Edge Function 'push-comercio' (supabase functions deploy push-comercio).
--
--  Cuando un pedido de tienda entra a 'buscando' (pagado con saldo, o
--  activado por el webhook de Wompi), avisa por push al dueño de la tienda.
--  No toca el push de repartidores.
-- ============================================================

create extension if not exists pg_net;

create or replace function public.notificar_comercio_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dueno  uuid;
  v_nombre text;
begin
  -- Solo pedidos de tienda que ENTRAN a 'buscando'
  if NEW.tipo_pedido = 'tienda'
     and NEW.tienda_id is not null
     and NEW.estado = 'buscando'
     and (TG_OP = 'INSERT' or OLD.estado is distinct from 'buscando') then

    select propietario_id, nombre into v_dueno, v_nombre
    from public.tiendas where id = NEW.tienda_id;

    if v_dueno is not null then
      perform net.http_post(
        url := 'https://dovqezmhdiauhlpichdn.supabase.co/functions/v1/push-comercio',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer sb_publishable_z_KMYtrQ0zxbTWhAa5GUTg___LLx-hk'
        ),
        body := jsonb_build_object(
          'usuario_id', v_dueno,
          'titulo', '¡Nuevo pedido! 🛍️',
          'cuerpo', 'Pedido nuevo en ' || coalesce(v_nombre, 'tu tienda') ||
                    ' por $' || to_char(coalesce(NEW.subtotal_productos,0), 'FM999,999') ||
                    '. Entra a prepararlo.',
          'url', '/'
        )
      );
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_notificar_comercio on public.pedidos;
create trigger trg_notificar_comercio
  after insert or update on public.pedidos
  for each row
  execute function public.notificar_comercio_pedido();

-- ============================================================
--  Listo. Cada pedido de tienda avisa al dueño por push.
--  Requisito: el dueño debe haber aceptado las notificaciones en la app.
-- ============================================================
