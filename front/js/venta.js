// Nueva venta: arma la lista de renglones (vino + cantidad) y la manda entera
// a POST /comprobantes. No muestra ningun importe hasta que responde la API.

const aviso = document.getElementById('aviso');
const selCliente = document.getElementById('cliente');
const selSala = document.getElementById('sala');
const selVino = document.getElementById('vino');
let stockSala = [];
let renglones = [];

async function iniciar() {
  try {
    const c = await get('/catalogos');
    llenarSelect(selSala, c.salas, s => s.id_sala, nombreSala);
    await buscarClientes();
    await cargarStock();
  } catch (e) {
    mensaje(aviso, e.message);
  }
}

async function buscarClientes() {
  const nombre = document.getElementById('buscar-cliente').value;
  const r = await get('/clientes' + query({ nombre, por_pagina: 50 }));
  llenarSelect(selCliente, r.items, c => c.id_cliente,
    c => `${c.nombre_razon_social} · ${c.tipo_cliente} (${c.descuento} %)`);
  if (r.items.length === 0) mensaje(aviso, 'Ningún cliente con ese nombre.');
}

async function cargarStock() {
  stockSala = await get('/salas/' + selSala.value + '/stock');
  llenarSelect(selVino, stockSala, s => s.cod_vino,
    s => `${s.nombre} ${s.anada} · ${s.volumen_ml} ml · hay ${s.cantidad}`);
}

function mostrarRenglones() {
  const cont = document.getElementById('renglones');
  if (renglones.length === 0) {
    cont.replaceChildren(el('p', { class: 'vacio' }, 'Todavía no agregaste vinos.'));
    return;
  }
  cont.replaceChildren(tabla([
    { titulo: 'Vino', valor: r => r.nombre },
    { titulo: 'Cantidad', valor: r => r.cantidad, numero: true },
    { titulo: '', valor: r => el('button', { type: 'button', class: 'peligro', onclick: () => quitar(r.cod_vino) }, 'Quitar') },
  ], renglones));
}

function quitar(codVino) {
  renglones = renglones.filter(r => r.cod_vino !== codVino);
  mostrarRenglones();
}

function mostrarComprobante(c) {
  document.getElementById('comprobante').replaceChildren(
    el('h2', {}, 'Comprobante ' + c.nro),
    el('dl', { class: 'datos' },
      el('dt', {}, 'Fecha'), el('dd', {}, c.fecha),
      el('dt', {}, 'Cliente'), el('dd', {}, `${c.cliente} (${c.tipo_cliente}, ${c.descuento_cliente} % de descuento)`),
      el('dt', {}, 'Sala'), el('dd', {}, c.id_sala + ' · ' + c.localidad_sala)),
    el('div', { class: 'tabla-scroll' }, tabla([
      { titulo: 'Vino', valor: r => `${r.nombre} ${r.anada}` },
      { titulo: 'Cant.', valor: r => r.cantidad, numero: true },
      { titulo: 'Precio', valor: r => pesos(r.precio_unitario), numero: true },
      { titulo: 'Descuento', valor: r => pesos(r.descuento), numero: true },
      { titulo: 'Subtotal', valor: r => pesos(r.subtotal), numero: true },
    ], c.renglones)),
    el('dl', { class: 'datos', style: 'margin-top: 12px' },
      el('dt', {}, 'Subtotal'), el('dd', {}, pesos(c.subtotal)),
      el('dt', {}, 'Descuento'), el('dd', {}, pesos(c.descuento)),
      el('dt', {}, 'Total'), el('dd', {}, el('strong', {}, pesos(c.total)))));
}

document.getElementById('boton-buscar').addEventListener('click', () => buscarClientes().catch(e => mensaje(aviso, e.message)));

selSala.addEventListener('change', () => {
  renglones = [];
  mostrarRenglones();
  cargarStock().catch(e => mensaje(aviso, e.message));
});

document.getElementById('agregar').addEventListener('click', () => {
  const vino = stockSala.find(s => String(s.cod_vino) === selVino.value);
  const cantidad = Number(document.getElementById('cantidad').value);
  if (!vino) return;
  // Un vino va una sola vez por comprobante (es la clave del renglon)
  renglones = renglones.filter(r => r.cod_vino !== vino.cod_vino);
  renglones.push({ cod_vino: vino.cod_vino, nombre: `${vino.nombre} ${vino.anada}`, cantidad });
  mensaje(aviso, '');
  mostrarRenglones();
});

document.getElementById('confirmar').addEventListener('click', async () => {
  try {
    const c = await post('/comprobantes', {
      id_cliente: Number(selCliente.value),
      id_sala: Number(selSala.value),
      renglones: renglones.map(r => ({ cod_vino: r.cod_vino, cantidad: r.cantidad })),
    });
    mensaje(aviso, `Venta guardada: comprobante ${c.nro}.`, 'ok');
    mostrarComprobante(c);
    renglones = [];
    mostrarRenglones();
    await cargarStock();
  } catch (e) {
    mensaje(aviso, e.message + ' — No se guardó nada: ni la cabecera ni los renglones.');
  }
});

mostrarRenglones();
iniciar();
