// Alta y edicion de vino. Con ?cod=N en la direccion, edita ese vino.

const formulario = document.getElementById('vino');
const aviso = document.getElementById('aviso');
const cortes = document.getElementById('cortes');
const cod = new URLSearchParams(location.search).get('cod');
let cepas = [];

function agregarCorte(idCepa = '', porcentaje = '') {
  const select = el('select', { class: 'cepa' });
  llenarSelect(select, cepas, c => c.id_cepa, c => c.nombre + ' (' + c.tipo + ')', 'Elegí una cepa');
  select.value = idCepa;
  const fila = el('div', { class: 'fila-form', style: 'margin-bottom: 8px' },
    el('label', {}, 'Cepa', select),
    el('label', {}, '%', el('input', { class: 'porcentaje', type: 'number', step: '0.01', value: porcentaje, style: 'width: 90px' })),
    el('button', { type: 'button', class: 'peligro', onclick: () => fila.remove() }, 'Quitar'));
  cortes.append(fila);
}

async function iniciar() {
  try {
    const c = await get('/catalogos');
    cepas = c.cepas;
    llenarSelect(formulario.tipo, c.tipos_vino, t => t, t => t);
    llenarSelect(formulario.cuit_bodega, c.bodegas, b => b.cuit, b => b.razon_social);
    document.getElementById('maridajes').replaceChildren(...c.maridajes.map(m =>
      el('label', { style: 'flex-direction: row; gap: 6px; align-items: center' },
        el('input', { type: 'checkbox', value: m.id_maridaje }), m.nombre)));

    if (cod) {
      const v = await get('/vinos/' + cod);
      document.getElementById('titulo').textContent = 'Editar vino ' + v.cod_vino;
      for (const campo of ['nombre', 'tipo', 'anada', 'volumen_ml', 'graduacion', 'precio', 'cuit_bodega']) {
        formulario[campo].value = v[campo];
      }
      v.composicion.forEach(x => agregarCorte(x.id_cepa, x.porcentaje));
      const elegidos = new Set(v.maridajes.map(m => String(m.id_maridaje)));
      document.querySelectorAll('#maridajes input').forEach(i => { i.checked = elegidos.has(i.value); });
      document.getElementById('borrar').hidden = false;
    } else {
      agregarCorte();
    }
  } catch (e) {
    mensaje(aviso, e.message);
  }
}

// Arma el JSON tal como lo escribio el usuario. Los campos vacios van como
// null, asi el error (NOT NULL, CHECK...) lo da la base y no esta pantalla.
function leerFormulario() {
  const numero = v => (v === '' ? null : Number(v));
  return {
    nombre: formulario.nombre.value,
    tipo: formulario.tipo.value,
    anada: numero(formulario.anada.value),
    volumen_ml: numero(formulario.volumen_ml.value),
    graduacion: numero(formulario.graduacion.value),
    precio: numero(formulario.precio.value),
    cuit_bodega: formulario.cuit_bodega.value,
    composicion: [...cortes.children].map(f => ({
      id_cepa: numero(f.querySelector('.cepa').value),
      porcentaje: numero(f.querySelector('.porcentaje').value),
    })),
    maridajes: [...document.querySelectorAll('#maridajes input:checked')].map(i => Number(i.value)),
  };
}

formulario.addEventListener('submit', async e => {
  e.preventDefault();
  try {
    const v = cod ? await put('/vinos/' + cod, leerFormulario()) : await post('/vinos', leerFormulario());
    mensaje(aviso, `Vino ${v.cod_vino} guardado.`, 'ok');
    setTimeout(() => { location.href = 'vino.html?cod=' + v.cod_vino; }, 900);
  } catch (err) {
    mensaje(aviso, err.message + ' — No se guardó nada.');
  }
});

document.getElementById('agregar-corte').addEventListener('click', () => agregarCorte());

document.getElementById('borrar').addEventListener('click', async () => {
  if (!confirm('¿Borrar el vino ' + cod + '?')) return;
  try {
    await borrar('/vinos/' + cod);
    location.href = 'index.html';
  } catch (err) {
    mensaje(aviso, err.message);
  }
});

iniciar();
