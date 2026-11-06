// Catalogo: listado paginado con filtros y ficha del vino.

const POR_PAGINA = 15;
let paginaActual = 1;

const formulario = document.getElementById('filtros');
const aviso = document.getElementById('aviso');

async function iniciar() {
  try {
    const c = await get('/catalogos');
    llenarSelect(formulario.tipo, c.tipos_vino, t => t, t => t, 'Todos');
    llenarSelect(formulario.cepa, c.cepas, x => x.id_cepa, x => x.nombre, 'Todas');
    llenarSelect(formulario.bodega, c.bodegas, x => x.cuit, x => x.razon_social, 'Todas');
    await buscar();
  } catch (e) {
    mensaje(aviso, e.message);
  }
}

async function buscar() {
  const filtros = Object.fromEntries(new FormData(formulario));
  try {
    const r = await get('/vinos' + query({ ...filtros, pagina: paginaActual, por_pagina: POR_PAGINA }));
    mensaje(aviso, '');
    mostrarLista(r);
  } catch (e) {
    mensaje(aviso, e.message);
  }
}

function mostrarLista(r) {
  const lista = document.getElementById('lista');
  if (r.items.length === 0) {
    lista.replaceChildren(el('p', { class: 'vacio' }, 'Ningún vino cumple los filtros.'));
  } else {
    lista.replaceChildren(tabla([
      { titulo: 'Cód.', valor: v => v.cod_vino, numero: true },
      { titulo: 'Nombre', valor: v => v.nombre },
      { titulo: 'Tipo', valor: v => v.tipo },
      { titulo: 'Añada', valor: v => v.anada, numero: true },
      { titulo: 'ml', valor: v => v.volumen_ml, numero: true },
      { titulo: 'Bodega', valor: v => v.bodega },
      { titulo: 'Precio', valor: v => pesos(v.precio), numero: true },
    ], r.items, v => verFicha(v.cod_vino)));
  }
  const paginas = Math.max(1, Math.ceil(r.total / r.por_pagina));
  document.getElementById('pagina').textContent = `Página ${r.pagina} de ${paginas} · ${r.total} vinos`;
  document.getElementById('anterior').disabled = r.pagina <= 1;
  document.getElementById('siguiente').disabled = r.pagina >= paginas;
}

async function verFicha(cod) {
  const ficha = document.getElementById('ficha');
  try {
    const v = await get('/vinos/' + cod);
    ficha.replaceChildren(
      el('h2', {}, v.nombre),
      el('dl', { class: 'datos' },
        el('dt', {}, 'Código'), el('dd', {}, v.cod_vino),
        el('dt', {}, 'Bodega'), el('dd', {}, v.bodega),
        el('dt', {}, 'Tipo'), el('dd', {}, v.tipo),
        el('dt', {}, 'Añada'), el('dd', {}, v.anada),
        el('dt', {}, 'Volumen'), el('dd', {}, v.volumen_ml + ' ml'),
        el('dt', {}, 'Graduación'), el('dd', {}, v.graduacion + ' %'),
        el('dt', {}, 'Precio'), el('dd', {}, pesos(v.precio))),
      el('h2', {}, 'Composición'),
      v.composicion.length
        ? tabla([{ titulo: 'Cepa', valor: c => c.cepa }, { titulo: '%', valor: c => c.porcentaje, numero: true }], v.composicion)
        : el('p', { class: 'vacio' }, 'Sin cepas cargadas.'),
      el('h2', {}, 'Maridajes'),
      el('p', {}, v.maridajes.length ? v.maridajes.map(m => m.nombre).join(', ') : 'Sin maridajes.'),
      el('h2', {}, 'Stock'),
      el('dl', { class: 'datos' },
        el('dt', {}, 'Depósito central'), el('dd', {}, v.en_deposito),
        el('dt', {}, 'Todas las salas'), el('dd', {}, v.en_salas),
        el('dt', {}, 'Total'), el('dd', {}, v.stock_total)),
      el('div', { class: 'botones' }, el('a', { class: 'boton', href: 'vino.html?cod=' + v.cod_vino }, 'Editar')));
  } catch (e) {
    ficha.replaceChildren(el('div', { class: 'aviso error' }, e.message));
  }
}

formulario.addEventListener('submit', e => { e.preventDefault(); paginaActual = 1; buscar(); });
formulario.addEventListener('reset', () => setTimeout(() => { paginaActual = 1; buscar(); }));
document.getElementById('anterior').addEventListener('click', () => { paginaActual--; buscar(); });
document.getElementById('siguiente').addEventListener('click', () => { paginaActual++; buscar(); });

iniciar();
