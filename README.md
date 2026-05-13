# Maxikia — Plataforma de entregas express

> Rápido como tú lo necesitas.

## Estructura del proyecto

```
maxikia/
├── index.html          ← Landing page principal
├── vercel.json         ← Configuración de Vercel
├── css/
│   └── main.css        ← Estilos globales
├── js/
│   └── main.js         ← Scripts globales
└── pages/
    ├── login.html      ← Inicio de sesión
    ├── register.html   ← Registro multi-paso (3 pasos)
    └── dashboard.html  ← App principal (cliente + repartidor)
```

## Cómo publicar en Vercel (GRATIS) — 5 minutos

### Opción A: Subir la carpeta directamente (más fácil)

1. Ve a https://vercel.com y crea una cuenta gratis (con tu correo o GitHub)
2. En el dashboard de Vercel, haz clic en **"Add New → Project"**
3. Elige **"Deploy from your computer"** o arrastra la carpeta `maxikia`
4. Vercel detecta automáticamente que es un sitio estático
5. Clic en **Deploy** — en 30 segundos tienes tu URL: `maxikia.vercel.app`

### Opción B: Con GitHub (recomendado para actualizar fácil)

1. Crea cuenta en https://github.com (gratis)
2. Crea un repositorio nuevo llamado `maxikia`
3. Sube esta carpeta al repositorio
4. Ve a https://vercel.com → conecta tu GitHub → importa el repo
5. Deploy automático — cada vez que cambies algo en GitHub, Vercel actualiza solo

### Dominio personalizado (opcional, ~$12/año)

Una vez desplegado en Vercel:
- Settings → Domains → Add domain: `maxikia.com` o `.co`
- Vercel te da las instrucciones de DNS

---

## Próximos pasos para hacerlo real

### 1. Backend y base de datos — Supabase (gratis hasta cierto uso)
- https://supabase.com
- Registro de usuarios, almacenamiento de fotos de ID, pedidos

### 2. Autenticación real
- Supabase Auth (incluido) — email/password y magic links
- Para huella biométrica: Web Authentication API (WebAuthn) — nativo en el navegador

### 3. Pagos — Wompi (Colombia)
- https://wompi.com — pasarela de pagos colombiana
- Acepta tarjetas, PSE, Nequi, Bancolombia
- Sin mensualidad, solo comisión por transacción (~2.95%)

### 4. Mapas y distancias
- Google Maps API (tiene capa gratuita) para calcular distancias y precios

### 5. Notificaciones en tiempo real
- Supabase Realtime — para actualizar estados de pedidos en vivo

---

## Modelo de negocio sugerido

- **Comisión por entrega**: 15-20% del valor del pedido
- **Precio mínimo de envío**: $8.000 COP
- **Precio base de cálculo**: $2.500/km + tarifa base

---

Construido con HTML, CSS y JavaScript puro. Sin frameworks, sin dependencias pesadas.
Diseño por Claude — Maxikia 2025.
