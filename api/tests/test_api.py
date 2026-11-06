"""
Pruebas automaticas de la API contra la base real (con la carga de la etapa 3).

Como se corren (desde la carpeta api/, con la base levantada y el .env listo):
    python -m pytest -v

Las que llevan «regla» en el nombre provocan a proposito que la base rechace
algo y verifican el codigo HTTP y que no quede nada guardado.

Ojo: algunas pruebas dejan datos. test_venta_correcta vende 1 botella, la de
estados deja una transferencia terminada y la de auditoria deja un vino con
historial de precios (que ya no se puede borrar). Conviene correrlas sobre la
carga chica.
"""

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from main import app


@pytest.fixture(scope='module')
def api():
    # El with dispara el arranque de la app: abre el pool de conexiones
    with TestClient(app) as cliente:
        yield cliente


@pytest.fixture(scope='module')
def catalogos(api):
    return api.get('/catalogos').json()


def vino_nuevo(catalogos, **cambios):
    """Datos validos para dar de alta un vino. Cada prueba cambia lo que necesita."""
    cepas = catalogos['cepas']
    datos = {
        # Nombre distinto en cada alta: (nombre, aniada, volumen) es UNIQUE
        'nombre': f'Vino de prueba pytest {uuid4().hex[:8]}', 'tipo': 'tinto', 'anada': 2024,
        'volumen_ml': 750, 'graduacion': 13.5, 'precio': 15000,
        'cuit_bodega': catalogos['bodegas'][0]['cuit'],
        'composicion': [{'id_cepa': cepas[0]['id_cepa'], 'porcentaje': 60},
                        {'id_cepa': cepas[1]['id_cepa'], 'porcentaje': 40}],
        'maridajes': [catalogos['maridajes'][0]['id_maridaje']],
    }
    datos.update(cambios)
    return datos


def cantidad_de_vinos_de_prueba(api):
    return api.get('/vinos', params={'nombre': 'Vino de prueba pytest'}).json()['total']


def un_vino_con_stock(api, catalogos):
    """(sala, renglon de stock) de algun vino que la sala tenga."""
    for sala in catalogos['salas']:
        stock = api.get(f'/salas/{sala["id_sala"]}/stock').json()
        if stock:
            return sala['id_sala'], stock[0]
    pytest.skip('Ninguna sala tiene stock')


# ---- Salud y catalogo -------------------------------------------------------

def test_salud_usa_el_rol_de_la_api(api):
    r = api.get('/salud')
    assert r.status_code == 200
    assert r.json()['usuario'] == 'bodegas_api'      # nunca el duenio de las tablas


def test_catalogo_paginado(api):
    r = api.get('/vinos', params={'por_pagina': 5})
    assert r.status_code == 200
    cuerpo = r.json()
    assert len(cuerpo['items']) <= 5
    assert cuerpo['total'] >= len(cuerpo['items'])


def test_catalogo_filtra_por_tipo(api):
    items = api.get('/vinos', params={'tipo': 'blanco', 'por_pagina': 100}).json()['items']
    assert all(v['tipo'] == 'blanco' for v in items)


def test_tipo_invalido_da_400(api):
    # 22P02: el texto no es un valor del ENUM tipo_vino
    r = api.get('/vinos', params={'tipo': 'naranja'})
    assert r.status_code == 400


def test_inyeccion_sql_no_funciona(api):
    # Si el texto se pegara dentro del SQL, el OR 1=1 traeria todos los vinos.
    # Como va como parametro, se busca un vino que se llame literalmente asi.
    r = api.get('/vinos', params={'nombre': "' OR 1=1 --"})
    assert r.status_code == 200
    assert r.json()['total'] == 0
    assert api.get('/vinos').json()['total'] > 0       # la tabla sigue intacta


def test_ficha_del_vino(api):
    cod = api.get('/vinos', params={'por_pagina': 1}).json()['items'][0]['cod_vino']
    ficha = api.get(f'/vinos/{cod}').json()
    assert sum(float(c['porcentaje']) for c in ficha['composicion']) == 100
    assert ficha['stock_total'] == ficha['en_deposito'] + ficha['en_salas']


def test_vino_inexistente_da_404(api):
    assert api.get('/vinos/999999').status_code == 404


# ---- Vinos: alta, cambio de precio auditado y baja --------------------------

def test_alta_y_baja_de_vino(api, catalogos):
    r = api.post('/vinos', json=vino_nuevo(catalogos))
    assert r.status_code == 201
    cod = r.json()['cod_vino']
    assert len(r.json()['composicion']) == 2
    assert api.delete(f'/vinos/{cod}').status_code == 204    # cepas y maridajes en cascada
    assert api.get(f'/vinos/{cod}').status_code == 404


def test_cambio_de_precio_queda_auditado(api, catalogos):
    cod = api.post('/vinos', json=vino_nuevo(catalogos)).json()['cod_vino']
    r = api.put(f'/vinos/{cod}', json=vino_nuevo(catalogos, precio=18000))
    assert r.status_code == 200
    precios = api.get(f'/vinos/{cod}/precios').json()
    assert len(precios) == 1                                 # lo escribio el trigger T6
    assert float(precios[0]['precio_nuevo']) == 18000
    assert precios[0]['usuario'] == 'bodegas_api'
    # Con historial de precios, la FK (RESTRICT) ya no deja borrarlo (RN-13)
    assert api.delete(f'/vinos/{cod}').status_code == 409


def test_regla_precio_negativo(api, catalogos):
    antes = cantidad_de_vinos_de_prueba(api)
    r = api.post('/vinos', json=vino_nuevo(catalogos, precio=-10))
    assert r.status_code == 422
    assert r.json()['sqlstate'] == '23514'             # CHECK precio > 0
    assert cantidad_de_vinos_de_prueba(api) == antes   # no quedo nada


def test_regla_composicion_que_no_suma_100(api, catalogos):
    antes = cantidad_de_vinos_de_prueba(api)
    cepa = catalogos['cepas'][0]['id_cepa']
    r = api.post('/vinos', json=vino_nuevo(
        catalogos, composicion=[{'id_cepa': cepa, 'porcentaje': 85}]))
    assert r.status_code == 409
    assert 'RN-05' in r.json()['detail']
    assert cantidad_de_vinos_de_prueba(api) == antes   # ROLLBACK: el vino tampoco quedo


# ---- Ventas -----------------------------------------------------------------

def test_regla_venta_sin_stock(api, catalogos):
    sala, stock = un_vino_con_stock(api, catalogos)
    cliente = api.get('/clientes', params={'por_pagina': 1}).json()['items'][0]['id_cliente']
    r = api.post('/comprobantes', json={
        'id_cliente': cliente, 'id_sala': sala,
        'renglones': [{'cod_vino': stock['cod_vino'], 'cantidad': stock['cantidad'] + 1000}]})
    assert r.status_code == 409
    assert 'Stock insuficiente' in r.json()['detail']   # mensaje del trigger T1
    # El stock no cambio: no quedo nada a medias
    despues = {s['cod_vino']: s['cantidad'] for s in api.get(f'/salas/{sala}/stock').json()}
    assert despues[stock['cod_vino']] == stock['cantidad']


def test_venta_correcta(api, catalogos):
    sala, stock = un_vino_con_stock(api, catalogos)
    cliente = api.get('/clientes', params={'por_pagina': 1}).json()['items'][0]['id_cliente']
    r = api.post('/comprobantes', json={
        'id_cliente': cliente, 'id_sala': sala,
        'renglones': [{'cod_vino': stock['cod_vino'], 'cantidad': 1}]})
    assert r.status_code == 201
    venta = r.json()
    # Los importes los calculo la base: la cabecera coincide con sus renglones
    assert float(venta['total']) == sum(float(x['subtotal']) for x in venta['renglones'])
    assert float(venta['total']) > 0
    despues = {s['cod_vino']: s['cantidad'] for s in api.get(f'/salas/{sala}/stock').json()}
    assert despues.get(stock['cod_vino'], 0) == stock['cantidad'] - 1


def test_venta_sin_renglones_da_422(api):
    r = api.post('/comprobantes', json={'id_cliente': 1, 'id_sala': 1, 'renglones': []})
    assert r.status_code == 422


# ---- Transferencias: los estados solo avanzan -------------------------------

def test_regla_estados_de_la_transferencia(api, catalogos):
    sala = catalogos['salas'][0]['id_sala']
    vino = api.get('/deposito/stock').json()[0]['cod_vino']
    nro = api.post('/transferencias', json={'id_sala': sala}).json()['nro_solicitud']
    assert api.post(f'/transferencias/{nro}/renglones',
                    json={'cod_vino': vino, 'cantidad': 1}).status_code == 201

    # Procesar sin terminar: lo rechaza el procedimiento (RN-11)
    assert api.post(f'/transferencias/{nro}/procesar').status_code == 409

    assert api.post(f'/transferencias/{nro}/terminar').json()['estado'] == 'terminado'

    # Ya no esta en confeccion: el trigger T4 no deja tocar los renglones (RN-12)
    r = api.post(f'/transferencias/{nro}/renglones', json={'cod_vino': vino, 'cantidad': 1})
    assert r.status_code == 409
    assert r.json()['sqlstate'] == 'P0001'


# ---- Clientes ---------------------------------------------------------------

def test_cliente_con_subtipo(api, catalogos):
    base = {'nombre_razon_social': 'Cliente de prueba pytest', 'tipo_documento': 'DNI',
            'nro_documento': '99999991', 'direccion': 'Calle 1',
            'id_localidad': catalogos['localidades'][0]['id_localidad']}

    # Distribuidor sin zona: el NOT NULL de la tabla distribuidor lo rechaza y
    # el ROLLBACK deshace tambien la fila de cliente
    r = api.post('/clientes', json=dict(base, tipo_cliente='distribuidor'))
    assert r.status_code == 422
    assert api.get('/clientes', params={'nombre': 'Cliente de prueba pytest'}).json()['total'] == 0

    r = api.post('/clientes', json=dict(base, tipo_cliente='socio'))
    assert r.status_code == 201
    assert float(r.json()['descuento']) == 10          # lo puso el trigger T8 (RN-06)
    assert api.delete(f'/clientes/{r.json()["id_cliente"]}').status_code == 204
