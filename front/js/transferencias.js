// Transferencias: listado, alta, carga de renglones y cambios de estado.

const POR_PAGINA = 12;
let paginaActual = 1;

const aviso = document.getElementById('aviso');
const filtroEstado = document.getElementById('filtro-estado');

async function iniciar() {
  try {
    const c = await get('/catalogos');
    llenarSelect(document.getElementById('sala-nueva'), c.salas, s => s.id_sala, nombreSala);
    await listar();
  } catch (e) {
    mensaje(aviso, e.message);
  }
}

async function listar() {
  const r = await get('/transferencias' + query({ estado: filtroEstado.value, pagina: paginaActual, por_pagina: POR_PAGINA }));
  document.getElementById('lista').replaceChildren(r.items.length
    ? tabla([
        { titulo: 'Nro.', valor: t => t.nro_solicitud, numero: true },
        { titulo: 'Sala', valor: t => t.id_sala, numero: true },
        { titulo: 'Fecha', valor: t => t.fecha_confeccion },
        { titulo: 'Estado', valor: t => etiquetaEstado(t.estado) },
      ], r.items, t => ver(t.nro_solicitud))
    : el('p', { class: 'vacio' }, 'No hay transferencias.'));
  const paginas = Math.max(1, Math.ceil(r.total / r.por_pagina));
  document.getElementById('pagina').textContent = `Página ${r.pagina} de ${paginas} · ${r.total} transferencias`;
  document.getElementById('anterior').disabled = r.pagina <= 1;
  document.getElementById('siguiente').disabled = r.pagina >= paginas;
}

function etiquetaEstado(estado) {
  return el('span', { class: 'estado ' + estado }, estado);
}

async function ver(nro) {
  mensaje(aviso, '');
  try {
    mostrar(await get('/transferencias/' + nro));
  } catch (e) {
    mensaje(aviso, e.message);
  }
}

async function mostrar(t) {
  const enConfeccion = t.estado === 'en_confeccion';
  const selVino = el('select', { style: 'max-width: 100%' });
  const cantidad = el('input', { type: 'number', min: '1', value: '1', style: 'width: 90px' });
  if (enConfeccion) {
    const deposito = await get('/deposito/stock');
    llenarSelect(selVino, deposito, d => d.cod_vino, d => `${d.nombre} ${d.anada} · ${d.volumen_ml} ml · depósito ${d.cantidad}`);
  }

  // Cada accion llama a la API y vuelve a dibujar con lo que responde
  const accion = async (promesa, textoOk) => {
    try {
      mostrar(await promesa());
      mensaje(aviso, textoOk, 'ok');
      listar();
    } catch (e) {
      mensaje(aviso, e.message);
    }
  };

  document.getElementById('detalle').replaceChildren(
    el('h2', {}, 'Transferencia ' + t.nro_solicitud),
    el('dl', { class: 'datos' },
      el('dt', {}, 'Sala'), el('dd', {}, t.id_sala + ' · ' + t.localidad_sala),
      el('dt', {}, 'Fecha'), el('dd', {}, t.fecha_confeccion),
      el('dt', {}, 'Estado'), el('dd', {}, etiquetaEstado(t.estado))),
    t.renglones.length
      ? el('div', { class: 'tabla-scroll' }, tabla([
          { titulo: 'Vino', valor: r => r.nombre },
          { titulo: 'Cantidad', valor: r => r.cantidad, numero: true },
          { titulo: 'En depósito', valor: r => r.en_deposito, numero: true },
        ], t.renglones))
      : el('p', { class: 'vacio' }, 'Sin renglones.'),
    el('div', { class: 'fila-form', style: 'margin-top: 12px' },
      el('label', { style: 'flex: 1 1 220px' }, 'Vino del depósito', selVino),
      el('label', {}, 'Cantidad', cantidad),
      el('button', {
        type: 'button', class: 'secundario', disabled: !enConfeccion,
        onclick: () => accion(() => post(`/transferencias/${t.nro_solicitud}/renglones`,
          { cod_vino: Number(selVino.value), cantidad: Number(cantidad.value) }), 'Renglón agregado.'),
      }, 'Agregar renglón')),
    el('div', { class: 'botones' },
      el('button', {
        type: 'button', disabled: !enConfeccion,
        onclick: () => accion(() => post(`/transferencias/${t.nro_solicitud}/terminar`), 'Transferencia terminada.'),
      }, 'Terminar'),
      el('button', {
        type: 'button', disabled: t.estado !== 'terminado',
        onclick: () => accion(() => post(`/transferencias/${t.nro_solicitud}/procesar`),
          'Procesada: el procedimiento restó del depósito y sumó a la sala.'),
      }, 'Procesar')));
}

document.getElementById('nueva').addEventListener('click', async () => {
  try {
    const t = await post('/transferencias', { id_sala: Number(document.getElementById('sala-nueva').value) });
    mensaje(aviso, `Transferencia ${t.nro_solicitud} creada en confección.`, 'ok');
    await mostrar(t);
    listar();
  } catch (e) {
    mensaje(aviso, e.message);
  }
});

filtroEstado.addEventListener('change', () => { paginaActual = 1; listar(); });
document.getElementById('anterior').addEventListener('click', () => { paginaActual--; listar(); });
document.getElementById('siguiente').addEventListener('click', () => { paginaActual++; listar(); });

iniciar();
