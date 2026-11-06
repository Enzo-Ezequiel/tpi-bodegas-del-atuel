// Capa de llamadas a la API: todas las pantallas pasan por aca.
// El front no calcula importes, descuentos ni stock: muestra lo que devuelve la API.

async function api(metodo, ruta, cuerpo) {
  const opciones = { method: metodo, headers: {} };
  if (cuerpo !== undefined) {
    opciones.headers['Content-Type'] = 'application/json';
    opciones.body = JSON.stringify(cuerpo);
  }
  let respuesta;
  try {
    respuesta = await fetch(API_URL + ruta, opciones);
  } catch {
    throw new Error('No se pudo conectar con la API en ' + API_URL + '. ¿Está levantada?');
  }
  if (respuesta.status === 204) return null;
  const datos = await respuesta.json();
  if (!respuesta.ok) throw new Error(mensajeDeError(respuesta.status, datos));
  return datos;
}

// El mensaje se muestra tal como lo manda la API (que a su vez es el de la base).
// FastAPI devuelve una lista cuando el JSON no tiene la forma esperada.
function mensajeDeError(status, datos) {
  let texto = datos.detail;
  if (Array.isArray(texto)) texto = texto.map(e => e.loc.slice(1).join('.') + ': ' + e.msg).join(' · ');
  return 'Error ' + status + ': ' + texto;
}

const get = ruta => api('GET', ruta);
const post = (ruta, cuerpo) => api('POST', ruta, cuerpo);
const put = (ruta, cuerpo) => api('PUT', ruta, cuerpo);
const borrar = ruta => api('DELETE', ruta);

// Arma una query string sin los parametros vacios: { tipo: 'tinto', cepa: '' } -> ?tipo=tinto
function query(parametros) {
  const limpios = Object.entries(parametros).filter(([, v]) => v !== '' && v !== null && v !== undefined);
  return limpios.length ? '?' + new URLSearchParams(limpios) : '';
}

// ---- Ayudas para armar la pantalla ----------------------------------------

// Crea un elemento. El texto va con textContent, nunca como HTML, asi un dato
// con < o > no puede inyectar codigo en la pagina.
function el(etiqueta, atributos = {}, ...hijos) {
  const nodo = document.createElement(etiqueta);
  for (const [clave, valor] of Object.entries(atributos)) {
    if (clave.startsWith('on')) nodo.addEventListener(clave.slice(2), valor);
    else if (valor === true) nodo.setAttribute(clave, '');
    else if (valor !== false && valor !== null && valor !== undefined) nodo.setAttribute(clave, valor);
  }
  for (const hijo of hijos.flat()) {
    if (hijo === null || hijo === undefined) continue;
    nodo.append(hijo instanceof Node ? hijo : document.createTextNode(String(hijo)));
  }
  return nodo;
}

function tabla(columnas, filas, alHacerClic) {
  return el('table', {},
    el('thead', {}, el('tr', {}, columnas.map(c => el('th', {}, c.titulo)))),
    el('tbody', {}, filas.map(f => el('tr', alHacerClic ? { class: 'clic', onclick: () => alHacerClic(f) } : {},
      columnas.map(c => el('td', c.numero ? { class: 'num' } : {}, c.valor(f)))))));
}

function llenarSelect(select, lista, valor, texto, primera) {
  select.replaceChildren(primera ? el('option', { value: '' }, primera) : []);
  for (const item of lista) select.append(el('option', { value: valor(item) }, texto(item)));
}

function mensaje(contenedor, texto, tipo = 'error') {
  contenedor.replaceChildren(texto ? el('div', { class: 'aviso ' + tipo }, texto) : []);
}

// Solo da formato a un numero que ya viene calculado
function pesos(n) {
  return '$ ' + Number(n).toLocaleString('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function nombreSala(s) {
  return 'Sala ' + s.id_sala + ' · ' + s.localidad + ' (' + s.calle + ' ' + s.numero + ')';
}
