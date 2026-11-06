"""
db.py - Capa de acceso a datos de la API.

Todo el SQL de la API esta en este archivo: una funcion por consulta. main.py
solo recibe el pedido HTTP, llama a una de estas funciones y devuelve el
resultado.

Tres reglas que se cumplen en todas las funciones:
  1. Consultas parametrizadas: los datos del usuario van como %(nombre)s y
     psycopg los manda aparte del texto SQL. Nunca se pegan dentro del SQL,
     asi que no hay inyeccion SQL posible.
  2. La API no calcula totales, descuentos ni stock: inserta las filas y los
     triggers, funciones y procedimientos de la base hacen el resto.
  3. Cuando una operacion tiene mas de una sentencia, va dentro de
     `with conn.transaction():`. Eso ejecuta BEGIN al entrar, COMMIT si todo
     salio bien y ROLLBACK si hubo cualquier error: no quedan datos a medias.
"""

import os
from pathlib import Path

from dotenv import load_dotenv
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

# El .env de la raiz del repo (en Docker las variables ya vienen del compose)
load_dotenv(Path(__file__).resolve().parent.parent / '.env')

# La API se conecta con bodegas_api (007_roles.sql), nunca con postgres:
# puede leer y escribir datos, pero no crear ni borrar tablas.
CONEXION = make_conninfo(
    host=os.getenv('DB_HOST', 'localhost'),
    port=os.getenv('DB_PORT', '5433'),
    dbname=os.getenv('POSTGRES_DB', 'bodegas_atuel'),
    user=os.getenv('API_DB_USER', 'bodegas_api'),
    password=os.getenv('API_DB_PASSWORD', ''),
)

# Pool: unas pocas conexiones abiertas que se reutilizan entre pedidos, en vez
# de abrir y cerrar una conexion por cada pedido (que es lento).
# dict_row hace que cada fila llegue como diccionario {columna: valor}.
pool = ConnectionPool(CONEXION, min_size=1, max_size=5, open=False,
                      kwargs={'row_factory': dict_row})


class NoEncontrado(Exception):
    """El codigo pedido no existe. main.py la convierte en 404."""


class ReglaNoCumplida(Exception):
    """Una regla que la base detecta pero no frena sola (RN-05 por debajo de
    100). main.py la convierte en 409, igual que un RAISE EXCEPTION."""


def abrir():
    pool.open(wait=True, timeout=10)


def cerrar():
    pool.close()


def _todas(sql, params=None):
    with pool.connection() as conn:
        return conn.execute(sql, params).fetchall()


def _una(sql, params=None):
    with pool.connection() as conn:
        fila = conn.execute(sql, params).fetchone()
    if fila is None:
        raise NoEncontrado()
    return fila


def _contar(sql, params):
    return _una(sql, params)['total']


# =============================================================================
# Salud y catalogos
# =============================================================================

def salud():
    return _una('SELECT current_user AS usuario, current_database() AS base, now() AS hora')


def catalogos():
    """Listas para los desplegables del front. enum_range devuelve los valores
    de un ENUM, asi los tipos salen de la base y no se repiten en el front."""
    return {
        'tipos_vino': [f['tipo'] for f in _todas(
            'SELECT unnest(enum_range(NULL::tipo_vino)) AS tipo')],
        'tipos_cliente': [f['tipo'] for f in _todas(
            'SELECT unnest(enum_range(NULL::tipo_cliente)) AS tipo')],
        'tipos_documento': [f['tipo'] for f in _todas(
            'SELECT unnest(enum_range(NULL::tipo_documento)) AS tipo')],
        'cepas': _todas('SELECT id_cepa, nombre, tipo FROM cepa ORDER BY nombre'),
        'bodegas': _todas('SELECT cuit, razon_social FROM bodega ORDER BY razon_social'),
        'maridajes': _todas('SELECT id_maridaje, nombre FROM maridaje ORDER BY nombre'),
        'transportistas': _todas(
            'SELECT cod_transporte, razon_social FROM transportista ORDER BY razon_social'),
        'localidades': _todas('SELECT id_localidad, nombre FROM localidad ORDER BY nombre'),
        'salas': _todas("""
            SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad
              FROM sala_venta s
              JOIN localidad l ON l.id_localidad = s.id_localidad
             ORDER BY s.id_sala"""),
    }


# =============================================================================
# Vinos
# =============================================================================

# Los filtros son opcionales. Cuando uno no viene, el parametro es NULL y la
# condicion "%(x)s IS NULL OR ..." da verdadero: no filtra. Asi el texto SQL
# es siempre el mismo y no hace falta armarlo pegando pedazos.
# El ::tipo le dice a PostgreSQL de que tipo es el parametro cuando es NULL.
FILTRO_VINOS = """
 WHERE (%(tipo)s::tipo_vino IS NULL OR v.tipo = %(tipo)s::tipo_vino)
   AND (%(bodega)s::text IS NULL OR v.cuit_bodega = %(bodega)s::text)
   AND (%(anada)s::integer IS NULL OR v.anada = %(anada)s::integer)
   AND (%(nombre)s::text IS NULL OR v.nombre ILIKE '%%' || %(nombre)s::text || '%%')
   AND (%(cepa)s::integer IS NULL OR EXISTS (SELECT 1
                                                FROM composicion co
                                               WHERE co.cod_vino = v.cod_vino
                                                 AND co.id_cepa = %(cepa)s::integer))
"""


def listar_vinos(filtros, limite, desde):
    params = dict(filtros, limite=limite, desde=desde)
    filas = _todas(f"""
        SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion,
               v.precio, b.razon_social AS bodega
          FROM vino v
          JOIN bodega b ON b.cuit = v.cuit_bodega
        {FILTRO_VINOS}
         ORDER BY v.cod_vino
         LIMIT %(limite)s OFFSET %(desde)s""", params)
    total = _contar(f'SELECT COUNT(*) AS total FROM vino v {FILTRO_VINOS}', params)
    return filas, total


def obtener_vino(cod):
    """Ficha del vino (consulta S9): datos, bodega, cepas, maridajes y stock.
    El stock sale de la vista v_stock_total_vino, no se suma aca."""
    vino = _una("""
        SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion,
               v.precio, v.cuit_bodega, b.razon_social AS bodega,
               st.en_deposito, st.en_salas, st.total AS stock_total
          FROM vino v
          JOIN bodega b ON b.cuit = v.cuit_bodega
          JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino
         WHERE v.cod_vino = %(cod)s""", {'cod': cod})
    vino['composicion'] = _todas("""
        SELECT co.id_cepa, ce.nombre AS cepa, co.porcentaje
          FROM composicion co
          JOIN cepa ce ON ce.id_cepa = co.id_cepa
         WHERE co.cod_vino = %(cod)s
         ORDER BY co.porcentaje DESC""", {'cod': cod})
    vino['maridajes'] = _todas("""
        SELECT m.id_maridaje, m.nombre
          FROM vino_maridaje vm
          JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
         WHERE vm.cod_vino = %(cod)s
         ORDER BY m.nombre""", {'cod': cod})
    return vino


def _guardar_composicion_y_maridajes(conn, cod, composicion, maridajes):
    """Inserta los cortes y los maridajes de un vino. El trigger T7 rechaza
    que la suma pase de 100. Que llegue a 100 no lo puede controlar la base
    fila por fila (las cepas entran de a una), asi que al final se pregunta
    a la vista v_vinos_composicion_incompleta: si el vino aparece, se lanza
    el error y la transaccion entera se deshace."""
    with conn.cursor() as cur:
        cur.executemany(
            'INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, %s)',
            [(cod, c['id_cepa'], c['porcentaje']) for c in composicion])
        cur.executemany(
            'INSERT INTO vino_maridaje (cod_vino, id_maridaje) VALUES (%s, %s)',
            [(cod, m) for m in maridajes])
    fila = conn.execute(
        'SELECT suma_porcentajes FROM v_vinos_composicion_incompleta WHERE cod_vino = %s',
        (cod,)).fetchone()
    if fila:
        raise ReglaNoCumplida(
            f'Los porcentajes de las cepas suman {fila["suma_porcentajes"]}: '
            'tienen que sumar 100 (RN-05)')


def crear_vino(datos):
    with pool.connection() as conn:
        with conn.transaction():
            cod = conn.execute("""
                INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
                VALUES (%(nombre)s, %(tipo)s, %(anada)s, %(volumen_ml)s, %(graduacion)s,
                        %(precio)s, %(cuit_bodega)s)
                RETURNING cod_vino""", datos).fetchone()['cod_vino']
            _guardar_composicion_y_maridajes(conn, cod, datos['composicion'], datos['maridajes'])
    return obtener_vino(cod)


def actualizar_vino(cod, datos):
    """Si cambia el precio, el trigger T6 lo registra en auditoria_precio
    (RN-13). La composicion y los maridajes se reemplazan enteros."""
    with pool.connection() as conn:
        with conn.transaction():
            fila = conn.execute("""
                UPDATE vino
                   SET nombre = %(nombre)s, tipo = %(tipo)s, anada = %(anada)s,
                       volumen_ml = %(volumen_ml)s, graduacion = %(graduacion)s,
                       precio = %(precio)s, cuit_bodega = %(cuit_bodega)s
                 WHERE cod_vino = %(cod)s
                RETURNING cod_vino""", dict(datos, cod=cod)).fetchone()
            if fila is None:
                raise NoEncontrado()
            conn.execute('DELETE FROM composicion WHERE cod_vino = %s', (cod,))
            conn.execute('DELETE FROM vino_maridaje WHERE cod_vino = %s', (cod,))
            _guardar_composicion_y_maridajes(conn, cod, datos['composicion'], datos['maridajes'])
    return obtener_vino(cod)


def borrar_vino(cod):
    """La composicion y los maridajes se borran en cascada. Si el vino tiene
    ventas, stock o movimientos, la FK (RESTRICT) no deja borrarlo."""
    _una('DELETE FROM vino WHERE cod_vino = %s RETURNING cod_vino', (cod,))


def historial_precios(cod):
    return _todas("""
        SELECT precio_anterior, precio_nuevo, fecha_hora, usuario
          FROM auditoria_precio
         WHERE cod_vino = %s
         ORDER BY fecha_hora DESC""", (cod,))


# =============================================================================
# Clientes
# =============================================================================

def listar_clientes(tipo, nombre, limite, desde):
    params = {'tipo': tipo, 'nombre': nombre, 'limite': limite, 'desde': desde}
    filtro = """
     WHERE (%(tipo)s::tipo_cliente IS NULL OR cl.tipo_cliente = %(tipo)s::tipo_cliente)
       AND (%(nombre)s::text IS NULL
            OR cl.nombre_razon_social ILIKE '%%' || %(nombre)s::text || '%%')"""
    filas = _todas(f"""
        SELECT cl.id_cliente, cl.nombre_razon_social, cl.tipo_cliente, cl.descuento,
               cl.tipo_documento, cl.nro_documento, l.nombre AS localidad
          FROM cliente cl
          JOIN localidad l ON l.id_localidad = cl.id_localidad
        {filtro}
         ORDER BY cl.id_cliente
         LIMIT %(limite)s OFFSET %(desde)s""", params)
    total = _contar(f'SELECT COUNT(*) AS total FROM cliente cl {filtro}', params)
    return filas, total


def obtener_cliente(id_cliente):
    """Supertipo con los datos de su subtipo. LEFT JOIN con las dos tablas
    que tienen columnas propias: solo una de las dos trae datos."""
    cliente = _una("""
        SELECT cl.*, l.nombre AS localidad,
               d.zona_cobertura, d.nro_habilitacion, e.pais_destino
          FROM cliente cl
          JOIN localidad l ON l.id_localidad = cl.id_localidad
          LEFT JOIN distribuidor d ON d.id_cliente = cl.id_cliente
          LEFT JOIN exportador e ON e.id_cliente = cl.id_cliente
         WHERE cl.id_cliente = %s""", (id_cliente,))
    cliente['permisos'] = _todas("""
        SELECT codigo, fecha_emision, fecha_vencimiento
          FROM permiso_exportacion
         WHERE id_cliente = %s
         ORDER BY fecha_emision""", (id_cliente,))
    return cliente


def crear_cliente(datos):
    """El cliente y su fila de subtipo van en la misma transaccion: asi un
    cliente nunca queda sin subtipo (limite de docs/03, seccion 7).
    No se manda el descuento: lo completa el trigger T8 segun el tipo (RN-06).
    Si falta un dato del subtipo, el NOT NULL de la base lo rechaza."""
    with pool.connection() as conn:
        with conn.transaction():
            fila = conn.execute("""
                INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento,
                                     direccion, id_localidad, tipo_cliente)
                VALUES (%(nombre_razon_social)s, %(tipo_documento)s, %(nro_documento)s,
                        %(direccion)s, %(id_localidad)s, %(tipo_cliente)s)
                RETURNING id_cliente, tipo_cliente""", datos).fetchone()
            datos = dict(datos, id_cliente=fila['id_cliente'])
            if fila['tipo_cliente'] == 'socio':
                conn.execute('INSERT INTO socio (id_cliente) VALUES (%(id_cliente)s)', datos)
            elif fila['tipo_cliente'] == 'distribuidor':
                conn.execute("""
                    INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
                    VALUES (%(id_cliente)s, %(zona_cobertura)s, %(nro_habilitacion)s)""", datos)
            else:
                conn.execute("""
                    INSERT INTO exportador (id_cliente, pais_destino)
                    VALUES (%(id_cliente)s, %(pais_destino)s)""", datos)
    return obtener_cliente(fila['id_cliente'])


def actualizar_cliente(id_cliente, datos):
    """El tipo de cliente no se cambia (habria que mover la fila de subtipo).
    El descuento solo cambia si viene en el pedido, como en la consulta U6."""
    with pool.connection() as conn:
        with conn.transaction():
            datos = dict(datos, id_cliente=id_cliente)
            fila = conn.execute("""
                UPDATE cliente
                   SET nombre_razon_social = %(nombre_razon_social)s,
                       tipo_documento = %(tipo_documento)s,
                       nro_documento = %(nro_documento)s,
                       direccion = %(direccion)s,
                       id_localidad = %(id_localidad)s,
                       descuento = COALESCE(%(descuento)s, descuento)
                 WHERE id_cliente = %(id_cliente)s
                RETURNING tipo_cliente""", datos).fetchone()
            if fila is None:
                raise NoEncontrado()
            if fila['tipo_cliente'] == 'distribuidor':
                conn.execute("""
                    UPDATE distribuidor
                       SET zona_cobertura = COALESCE(%(zona_cobertura)s, zona_cobertura),
                           nro_habilitacion = COALESCE(%(nro_habilitacion)s, nro_habilitacion)
                     WHERE id_cliente = %(id_cliente)s""", datos)
            elif fila['tipo_cliente'] == 'exportador':
                conn.execute("""
                    UPDATE exportador
                       SET pais_destino = COALESCE(%(pais_destino)s, pais_destino)
                     WHERE id_cliente = %(id_cliente)s""", datos)
    return obtener_cliente(id_cliente)


def borrar_cliente(id_cliente):
    """La fila del subtipo se borra en cascada. Si el cliente tiene
    comprobantes, la FK (RESTRICT) no deja borrarlo."""
    _una('DELETE FROM cliente WHERE id_cliente = %s RETURNING id_cliente', (id_cliente,))


# =============================================================================
# Ventas (comprobantes)
# =============================================================================

def crear_comprobante(id_cliente, id_sala, renglones):
    """La venta completa en una transaccion. La API solo inserta la cabecera
    (los importes arrancan en 0 por el DEFAULT) y los renglones con vino y
    cantidad. Por cada renglon:
      - T1 (BEFORE) valida el stock de la sala (RN-09) y completa precio,
        descuento y subtotal;
      - T2 (AFTER) descuenta el stock y recalcula los importes de la cabecera.
    Si un renglon no tiene stock, T1 lanza el error y el ROLLBACK deshace
    tambien la cabecera y los renglones anteriores."""
    with pool.connection() as conn:
        with conn.transaction():
            nro = conn.execute("""
                INSERT INTO comprobante (fecha, id_cliente, id_sala)
                VALUES (CURRENT_DATE, %s, %s)
                RETURNING nro""", (id_cliente, id_sala)).fetchone()['nro']
            with conn.cursor() as cur:
                cur.executemany("""
                    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
                    VALUES (%s, %s, %s)""",
                    [(nro, r['cod_vino'], r['cantidad']) for r in renglones])
    return obtener_comprobante(nro)


def obtener_comprobante(nro):
    comprobante = _una("""
        SELECT c.nro, c.fecha, c.id_cliente, cl.nombre_razon_social AS cliente,
               cl.tipo_cliente, cl.descuento AS descuento_cliente,
               c.id_sala, l.nombre AS localidad_sala,
               c.subtotal, c.descuento, c.total
          FROM comprobante c
          JOIN cliente cl ON cl.id_cliente = c.id_cliente
          JOIN sala_venta s ON s.id_sala = c.id_sala
          JOIN localidad l ON l.id_localidad = s.id_localidad
         WHERE c.nro = %s""", (nro,))
    comprobante['renglones'] = _todas("""
        SELECT r.cod_vino, v.nombre, v.anada, r.cantidad, r.precio_unitario, r.descuento, r.subtotal
          FROM renglon_comprobante r
          JOIN vino v ON v.cod_vino = r.cod_vino
         WHERE r.nro_comprobante = %s
         ORDER BY r.cod_vino""", (nro,))
    return comprobante


def stock_de_sala(id_sala):
    """Vinos con stock en una sala, para elegir que vender. Solo lee
    stock_sala: no calcula nada."""
    return _todas("""
        SELECT s.cod_vino, v.nombre, v.anada, v.volumen_ml, v.precio, s.cantidad
          FROM stock_sala s
          JOIN vino v ON v.cod_vino = s.cod_vino
         WHERE s.id_sala = %s AND s.cantidad > 0
         ORDER BY v.nombre, v.anada""", (id_sala,))


def stock_de_deposito():
    return _todas("""
        SELECT d.cod_vino, v.nombre, v.anada, v.volumen_ml, d.cantidad
          FROM stock_deposito d
          JOIN vino v ON v.cod_vino = d.cod_vino
         WHERE d.cantidad > 0
         ORDER BY v.nombre, v.anada""")


# =============================================================================
# Transferencias e ingresos
# Los dos documentos siguen el mismo circuito (RN-10, RN-11, RN-12):
#   en_confeccion -> se cargan renglones (T4 los bloquea despues)
#   terminado     -> lo controla T3: los estados solo avanzan
#   procesado     -> solo con el procedimiento, que mueve el stock
# =============================================================================

def listar_transferencias(id_sala, estado, limite, desde):
    params = {'sala': id_sala, 'estado': estado, 'limite': limite, 'desde': desde}
    filtro = """
     WHERE (%(sala)s::integer IS NULL OR t.id_sala = %(sala)s::integer)
       AND (%(estado)s::estado_documento IS NULL OR t.estado = %(estado)s::estado_documento)"""
    filas = _todas(f"""
        SELECT t.nro_solicitud, t.id_sala, t.fecha_confeccion, t.estado
          FROM transferencia t
        {filtro}
         ORDER BY t.nro_solicitud DESC
         LIMIT %(limite)s OFFSET %(desde)s""", params)
    total = _contar(f'SELECT COUNT(*) AS total FROM transferencia t {filtro}', params)
    return filas, total


def obtener_transferencia(nro):
    transferencia = _una("""
        SELECT t.nro_solicitud, t.id_sala, l.nombre AS localidad_sala,
               t.fecha_confeccion, t.estado
          FROM transferencia t
          JOIN sala_venta s ON s.id_sala = t.id_sala
          JOIN localidad l ON l.id_localidad = s.id_localidad
         WHERE t.nro_solicitud = %s""", (nro,))
    transferencia['renglones'] = _todas("""
        SELECT r.cod_vino, v.nombre, r.cantidad,
               COALESCE(d.cantidad, 0) AS en_deposito
          FROM renglon_transferencia r
          JOIN vino v ON v.cod_vino = r.cod_vino
          LEFT JOIN stock_deposito d ON d.cod_vino = r.cod_vino
         WHERE r.nro_solicitud = %s
         ORDER BY r.cod_vino""", (nro,))
    return transferencia


def crear_transferencia(id_sala):
    """Solo se manda la sala. La fecha la pone el trigger T5 (RN-11) y el
    estado en_confeccion el DEFAULT."""
    with pool.connection() as conn:
        nro = conn.execute("""
            INSERT INTO transferencia (id_sala) VALUES (%s)
            RETURNING nro_solicitud""", (id_sala,)).fetchone()['nro_solicitud']
    return obtener_transferencia(nro)


def agregar_renglon_transferencia(nro, cod_vino, cantidad):
    """Si la transferencia ya no esta en confeccion, el trigger T4 lo rechaza
    (RN-12)."""
    with pool.connection() as conn:
        conn.execute("""
            INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
            VALUES (%s, %s, %s)""", (nro, cod_vino, cantidad))
    return obtener_transferencia(nro)


def terminar_transferencia(nro):
    """Si el paso no es en_confeccion -> terminado, el trigger T3 lo rechaza."""
    _una("""
        UPDATE transferencia SET estado = 'terminado'
         WHERE nro_solicitud = %s
        RETURNING nro_solicitud""", (nro,))
    return obtener_transferencia(nro)


def procesar_transferencia(nro):
    """El procedimiento valida el estado y el stock del deposito, resta del
    deposito, suma a la sala y pasa a procesado, todo o nada (RN-11)."""
    with pool.connection() as conn:
        conn.execute('CALL sp_procesar_transferencia(%s)', (nro,))
    return obtener_transferencia(nro)


def listar_ingresos(estado, limite, desde):
    params = {'estado': estado, 'limite': limite, 'desde': desde}
    filtro = """
     WHERE (%(estado)s::estado_documento IS NULL OR i.estado = %(estado)s::estado_documento)"""
    filas = _todas(f"""
        SELECT i.cod_ingreso, i.fecha, i.estado, b.razon_social AS bodega,
               t.razon_social AS transportista
          FROM ingreso i
          JOIN bodega b ON b.cuit = i.cuit_bodega
          JOIN transportista t ON t.cod_transporte = i.cod_transporte
        {filtro}
         ORDER BY i.cod_ingreso DESC
         LIMIT %(limite)s OFFSET %(desde)s""", params)
    total = _contar(f'SELECT COUNT(*) AS total FROM ingreso i {filtro}', params)
    return filas, total


def obtener_ingreso(cod):
    ingreso = _una("""
        SELECT i.cod_ingreso, i.fecha, i.estado, i.cuit_bodega, b.razon_social AS bodega,
               i.cod_transporte, t.razon_social AS transportista
          FROM ingreso i
          JOIN bodega b ON b.cuit = i.cuit_bodega
          JOIN transportista t ON t.cod_transporte = i.cod_transporte
         WHERE i.cod_ingreso = %s""", (cod,))
    ingreso['renglones'] = _todas("""
        SELECT r.cod_vino, v.nombre, r.cantidad
          FROM renglon_ingreso r
          JOIN vino v ON v.cod_vino = r.cod_vino
         WHERE r.cod_ingreso = %s
         ORDER BY r.cod_vino""", (cod,))
    return ingreso


def crear_ingreso(cod_transporte, cuit_bodega):
    with pool.connection() as conn:
        cod = conn.execute("""
            INSERT INTO ingreso (fecha, cod_transporte, cuit_bodega)
            VALUES (CURRENT_DATE, %s, %s)
            RETURNING cod_ingreso""", (cod_transporte, cuit_bodega)).fetchone()['cod_ingreso']
    return obtener_ingreso(cod)


def agregar_renglon_ingreso(cod, cod_vino, cantidad):
    with pool.connection() as conn:
        conn.execute("""
            INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
            VALUES (%s, %s, %s)""", (cod, cod_vino, cantidad))
    return obtener_ingreso(cod)


def terminar_ingreso(cod):
    _una("""
        UPDATE ingreso SET estado = 'terminado'
         WHERE cod_ingreso = %s
        RETURNING cod_ingreso""", (cod,))
    return obtener_ingreso(cod)


def procesar_ingreso(cod):
    """El procedimiento suma los renglones al deposito y pasa a procesado (RN-10)."""
    with pool.connection() as conn:
        conn.execute('CALL sp_procesar_ingreso(%s)', (cod,))
    return obtener_ingreso(cod)


# =============================================================================
# Reportes: consultas de la seccion 8 (consultas/select.sql), solo lectura
# =============================================================================

def top_vinos():
    """S1: los 10 vinos con mas botellas vendidas en toda la red."""
    return _todas("""
        SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, SUM(r.cantidad) AS botellas
          FROM renglon_comprobante r
          JOIN vino v ON v.cod_vino = r.cod_vino
         GROUP BY v.cod_vino, v.nombre, v.anada, v.volumen_ml
         ORDER BY botellas DESC, v.cod_vino
         LIMIT 10""")


def ventas_por_sala():
    """S8: monto vendido por sala en el ultimo trimestre, de mayor a menor."""
    return _todas("""
        SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad,
               SUM(c.total) AS total_ventas
          FROM comprobante c
          JOIN sala_venta s ON s.id_sala = c.id_sala
          JOIN localidad l ON l.id_localidad = s.id_localidad
         WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
         GROUP BY s.id_sala, s.calle, s.numero, l.nombre
         ORDER BY total_ventas DESC""")


def vinos_sin_stock(id_sala):
    """S6: vinos sin stock en la sala pero con stock en el deposito."""
    return _todas("""
        SELECT v.cod_vino, v.nombre, d.cantidad AS en_deposito
          FROM stock_deposito d
          JOIN vino v ON v.cod_vino = d.cod_vino
         WHERE d.cantidad > 0
           AND NOT EXISTS (SELECT 1
                             FROM stock_sala s
                            WHERE s.id_sala = %s
                              AND s.cod_vino = d.cod_vino
                              AND s.cantidad > 0)
         ORDER BY v.cod_vino""", (id_sala,))


def transportista_activo():
    """S7: el transportista con mas ingresos en el ultimo mes (con empates)."""
    return _todas("""
        SELECT t.cod_transporte, t.razon_social, COUNT(*) AS ingresos
          FROM transportista t
          JOIN ingreso i ON i.cod_transporte = t.cod_transporte
         WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
         GROUP BY t.cod_transporte, t.razon_social
        HAVING COUNT(*) = (SELECT MAX(x.ingresos)
                             FROM (SELECT COUNT(*) AS ingresos
                                     FROM ingreso
                                    WHERE fecha >= CURRENT_DATE - INTERVAL '1 month'
                                    GROUP BY cod_transporte) x)
         ORDER BY t.cod_transporte""")


def trazabilidad(cod):
    """Recorrido de un vino: la ficha (S9) y sus movimientos, de donde vinieron
    las botellas (ingresos), a que salas fueron (transferencias) y donde se
    vendieron. UNION ALL junta las tres listas con las mismas columnas."""
    ficha = obtener_vino(cod)
    ficha['movimientos'] = _todas("""
        SELECT 'ingreso' AS movimiento, i.cod_ingreso AS numero, i.fecha,
               i.estado::text AS estado, NULL::integer AS id_sala, r.cantidad
          FROM renglon_ingreso r
          JOIN ingreso i ON i.cod_ingreso = r.cod_ingreso
         WHERE r.cod_vino = %(cod)s
        UNION ALL
        SELECT 'transferencia', t.nro_solicitud, t.fecha_confeccion,
               t.estado::text, t.id_sala, r.cantidad
          FROM renglon_transferencia r
          JOIN transferencia t ON t.nro_solicitud = r.nro_solicitud
         WHERE r.cod_vino = %(cod)s
        UNION ALL
        SELECT 'venta', c.nro, c.fecha, NULL, c.id_sala, r.cantidad
          FROM renglon_comprobante r
          JOIN comprobante c ON c.nro = r.nro_comprobante
         WHERE r.cod_vino = %(cod)s
         ORDER BY fecha DESC, movimiento
         LIMIT 100""", {'cod': cod})
    return ficha
