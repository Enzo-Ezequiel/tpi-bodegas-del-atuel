// Tablero: muestra los reportes de la API. Los montos ya vienen sumados por la
// base; aca solo se dibujan.

const aviso = document.getElementById('aviso');
const selSala = document.getElementById('sala');

// Grafico de barras con divs: el ancho de cada barra es su monto respecto del
// mayor (escala del dibujo, no un calculo del negocio).
function graficoVentas(filas) {
  const cont = document.getElementById('ventas');
  if (filas.length === 0) {
    cont.replaceChildren(el('p', { class: 'vacio' }, 'No hubo ventas en el último trimestre.'));
    return;
  }
  const mayor = Math.max(...filas.map(f => Number(f.total_ventas)));
  cont.replaceChildren(...filas.map(f => el('div', { class: 'barra' },
    el('span', {}, `Sala ${f.id_sala} · ${f.localidad}`),
    el('div', { class: 'pista' }, el('div', { class: 'relleno', style: `width: ${(Number(f.total_ventas) / mayor) * 100}%` })),
    el('span', { class: 'num' }, pesos(f.total_ventas)))));
}

async function sinStock() {
  const filas = await get('/reportes/vinos-sin-stock?sala=' + selSala.value);
  document.getElementById('sin-stock').replaceChildren(filas.length
    ? tabla([
        { titulo: 'Cód.', valor: v => v.cod_vino, numero: true },
        { titulo: 'Vino', valor: v => v.nombre },
        { titulo: 'En depósito', valor: v => v.en_deposito, numero: true },
      ], filas)
    : el('p', { class: 'vacio' }, 'Ninguno: la sala tiene todo lo que hay en el depósito.'));
}

async function iniciar() {
  try {
    const [c, ventas, top, transp] = await Promise.all([
      get('/catalogos'), get('/reportes/ventas-por-sala'), get('/reportes/top-vinos'),
      get('/reportes/transportista-activo')]);

    graficoVentas(ventas);

    document.getElementById('top').replaceChildren(tabla([
      { titulo: '#', valor: v => top.indexOf(v) + 1, numero: true },
      { titulo: 'Vino', valor: v => `${v.nombre} ${v.anada} · ${v.volumen_ml} ml` },
      { titulo: 'Botellas', valor: v => v.botellas, numero: true },
    ], top));

    document.getElementById('transportista').replaceChildren(transp.length
      ? tabla([
          { titulo: 'Transportista', valor: t => t.razon_social },
          { titulo: 'Ingresos', valor: t => t.ingresos, numero: true },
        ], transp)
      : el('p', { class: 'vacio' }, 'Ningún ingreso en el último mes.'));

    llenarSelect(selSala, c.salas, s => s.id_sala, nombreSala);
    await sinStock();
  } catch (e) {
    mensaje(aviso, e.message);
  }
}

selSala.addEventListener('change', () => sinStock().catch(e => mensaje(aviso, e.message)));

iniciar();
