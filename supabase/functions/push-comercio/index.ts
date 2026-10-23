// ============================================================
//  MAXIKIA — Edge Function: push-comercio
//  Envía una notificación push a UN usuario específico (el dueño de
//  una tienda) cuando entra un pedido para su tienda.
//  No toca el push de repartidores (función 'enviar-push').
//
//  Desplegar:  supabase functions deploy push-comercio
//  Usa los mismos secretos VAPID que ya configuraste para 'enviar-push'.
// ============================================================

import webpush from 'https://esm.sh/web-push@3.6.7'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const VAPID_PUBLIC  = Deno.env.get('VAPID_PUBLIC_KEY')!
const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE_KEY')!

webpush.setVapidDetails('mailto:soporte@maxikiaexpress.com', VAPID_PUBLIC, VAPID_PRIVATE)

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)
  try {
    const { usuario_id, titulo, cuerpo, url } = await req.json()
    if (!usuario_id) return json({ error: 'Falta usuario_id' }, 400)

    const supabase = createClient(SUPABASE_URL, SERVICE_KEY)
    const { data: subs } = await supabase
      .from('push_subscriptions').select('*').eq('usuario_id', usuario_id)

    if (!subs || subs.length === 0) return json({ ok: true, enviados: 0, nota: 'El comercio no tiene notificaciones activas' })

    const payload = JSON.stringify({
      title: titulo || 'Maxikia Express',
      body:  cuerpo || 'Tienes un pedido nuevo',
      url:   url || '/',
      tipo:  'pedido_tienda',
    })

    let enviados = 0
    for (const s of subs) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload
        )
        enviados++
      } catch (e: any) {
        // Suscripción vencida o inválida → limpiarla
        if (e?.statusCode === 410 || e?.statusCode === 404) {
          await supabase.from('push_subscriptions').delete().eq('endpoint', s.endpoint)
        }
      }
    }
    return json({ ok: true, enviados })
  } catch (e: any) {
    return json({ error: e.message }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}
