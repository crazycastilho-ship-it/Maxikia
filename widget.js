/**
 * Maxikia Express — Widget de integración
 * Versión 1.0
 * 
 * Uso: <script src="https://maxikia.com/widget.js" data-local="Mi Local" data-origen="Cra 15 #93-10, Bogotá"></script>
 */
(function() {
  'use strict';

  const MX_URL = 'https://maxikia.com';
  const MX_COLOR = '#D4001A';

  // Leer configuración del script tag
  const scriptTag = document.currentScript || document.querySelector('script[data-local]');
  const config = {
    local: scriptTag?.getAttribute('data-local') || '',
    origen: scriptTag?.getAttribute('data-origen') || '',
    color: scriptTag?.getAttribute('data-color') || MX_COLOR,
    texto: scriptTag?.getAttribute('data-texto') || '🛵 Pedir domicilio con Maxikia',
    posicion: scriptTag?.getAttribute('data-posicion') || 'inline', // 'inline' | 'flotante'
  };

  // Estilos del widget
  const estilos = `
    .mx-widget-btn {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      background: ${config.color};
      color: white;
      border: none;
      border-radius: 10px;
      padding: 14px 24px;
      font-size: 15px;
      font-weight: 600;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      cursor: pointer;
      text-decoration: none;
      transition: all 0.2s;
      box-shadow: 0 4px 14px rgba(212,0,26,0.3);
    }
    .mx-widget-btn:hover { opacity: 0.9; transform: translateY(-1px); box-shadow: 0 6px 20px rgba(212,0,26,0.4); }
    .mx-widget-btn img { width: 22px; height: 22px; }
    .mx-widget-flotante {
      position: fixed;
      bottom: 24px;
      right: 24px;
      z-index: 9999;
    }
    .mx-widget-modal-bg {
      display: none;
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.6);
      z-index: 99999;
      align-items: center;
      justify-content: center;
    }
    .mx-widget-modal-bg.open { display: flex; }
    .mx-widget-modal {
      background: white;
      border-radius: 16px;
      width: 100%;
      max-width: 480px;
      max-height: 90vh;
      overflow: hidden;
      margin: 1rem;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    }
    .mx-widget-modal iframe {
      width: 100%;
      height: 600px;
      border: none;
    }
    .mx-widget-modal-header {
      background: #0E0D0D;
      padding: 1rem 1.25rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .mx-widget-logo {
      font-family: -apple-system, sans-serif;
      font-weight: 800;
      font-size: 18px;
      color: white;
    }
    .mx-widget-logo span { color: #FF1F38; }
    .mx-widget-close {
      background: none;
      border: none;
      color: rgba(255,255,255,0.5);
      font-size: 22px;
      cursor: pointer;
      padding: 0;
      line-height: 1;
    }
    .mx-badge {
      display: inline-block;
      background: #E1F5EE;
      color: #0F6E56;
      font-size: 11px;
      font-weight: 600;
      padding: 3px 8px;
      border-radius: 20px;
      margin-left: 8px;
    }
  `;

  // Insertar estilos
  const style = document.createElement('style');
  style.textContent = estilos;
  document.head.appendChild(style);

  // Construir URL con parámetros
  function buildUrl() {
    const params = new URLSearchParams();
    if (config.local) params.set('local', config.local);
    if (config.origen) params.set('origen', config.origen);
    params.set('tipo', 'comercial');
    return MX_URL + '?' + params.toString();
  }

  // Crear modal
  function crearModal() {
    const bg = document.createElement('div');
    bg.className = 'mx-widget-modal-bg';
    bg.innerHTML = `
      <div class="mx-widget-modal">
        <div class="mx-widget-modal-header">
          <div class="mx-widget-logo">Maxi<span>⋊</span>ia Express</div>
          <button class="mx-widget-close" onclick="this.closest('.mx-widget-modal-bg').classList.remove('open')">✕</button>
        </div>
        <iframe src="${buildUrl()}" title="Maxikia Express"></iframe>
      </div>
    `;
    bg.addEventListener('click', e => { if (e.target === bg) bg.classList.remove('open'); });
    document.body.appendChild(bg);
    return bg;
  }

  let modal = null;

  function abrirMaxikia() {
    if (!modal) modal = crearModal();
    modal.classList.add('open');
  }

  // Crear botón principal
  function crearBoton() {
    const btn = document.createElement('button');
    btn.className = 'mx-widget-btn';
    btn.innerHTML = `<span>🛵</span> ${config.texto}`;
    btn.addEventListener('click', abrirMaxikia);
    return btn;
  }

  // Insertar según posición
  window.addEventListener('DOMContentLoaded', () => {
    const btn = crearBoton();
    if (config.posicion === 'flotante') {
      const wrap = document.createElement('div');
      wrap.className = 'mx-widget-flotante';
      wrap.appendChild(btn);
      document.body.appendChild(wrap);
    } else {
      // Insertar donde está el script
      if (scriptTag && scriptTag.parentNode) {
        scriptTag.parentNode.insertBefore(btn, scriptTag.nextSibling);
      } else {
        document.body.appendChild(btn);
      }
    }
  });

  // API pública
  window.MaxikiaWidget = { abrir: abrirMaxikia, config };

})();
