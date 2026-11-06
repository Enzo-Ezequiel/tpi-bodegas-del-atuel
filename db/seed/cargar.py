"""
cargar.py - Etapa 3: carga de datos de prueba de «Bodegas del Atuel».

Uso (ver db/seed/README.md):
    python db/seed/cargar.py --chico          volumen chico, en segundos
    python db/seed/cargar.py                  volumen completo
    python db/seed/cargar.py --fecha-referencia 2026-11-05
    python db/seed/cargar.py --medir          compara execute fila por fila con executemany

La conexion se toma de las variables de entorno estandar de PostgreSQL
(PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE): no hay contrasenias en el
codigo. Se conecta como postgres porque tiene que deshabilitar triggers, y eso
solo lo puede hacer el duenio de las tablas.

Todo corre en una sola transaccion: si algo falla, psycopg hace ROLLBACK y la
base queda vacia como estaba.

Orden de carga: primero las tablas que no dependen de nadie (catalogos,
bodegas, transportistas), despues las que las referencian. Cada funcion de
abajo dice por que va en ese lugar.
"""

import argparse
import bisect
import csv
import math
import random
import sys
import time
import unicodedata
from datetime import date, timedelta
from decimal import Decimal, ROUND_DOWN
from pathlib import Path

import psycopg
from faker import Faker
from psycopg import sql
from psycopg.pq import TransactionStatus

CARPETA = Path(__file__).resolve().parent
CATALOGOS = CARPETA / 'catalogos'

# Volumenes de la seccion 4.3 de tareas/matias.md (columnas «Completo» y «Chico»)
VOLUMENES = {
    'completo': dict(bodegas=10, transportistas=15, cobertura=(3, 8), salas=30,
                     dias_cierre_min=3, empleados=300, fincas=40, parcelas_por_finca=10,
                     analisis_max=3, vinos=500, clientes=12000, comprobantes=50000,
                     ingresos=2500, transferencias=4000, sala1_con_stock=20,
                     socios_viejos_sin_compras=20, socios_san_rafael_sin_compras=10,
                     aumentos_precio=20),
    'chico': dict(bodegas=3, transportistas=4, cobertura=(2, 3), salas=4,
                  dias_cierre_min=1, empleados=12, fincas=3, parcelas_por_finca=3,
                  analisis_max=1, vinos=12, clientes=60, comprobantes=150,
                  ingresos=25, transferencias=30, sala1_con_stock=5,
                  socios_viejos_sin_compras=3, socios_san_rafael_sin_compras=2,
                  aumentos_precio=3),
}

# Valores fijos que usan las consultas de Manuel y la API de Ezequiel (seccion 5)
BODEGA_TRES_VINOS = 'Bodega Los Tres Vinos'
VINO_FIJO = 'Malbec Reserva'
LOCALIDAD_SAN_RAFAEL = 'San Rafael'
CEPAS_SIN_USAR = ('Petit Verdot', 'Viognier', 'Pinot Gris')

LINEAS = ['Joven', 'Roble', 'Clásico', 'Reserva', 'Gran Reserva', 'Selección', 'Premium']
OTROS_VOLUMENES = [187, 375, 1500, 3000]
DIAS = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo']
PAISES = ['Brasil', 'Chile', 'Estados Unidos', 'China', 'Reino Unido', 'Canadá', 'Países Bajos']
ESTADOS = ['en_confeccion', 'terminado', 'procesado']

# Tablas cuyos triggers se apagan durante la carga de la historia (seccion 4.6)
TABLAS_SIN_TRIGGERS = ['ingreso', 'renglon_ingreso', 'transferencia',
                       'renglon_transferencia', 'renglon_comprobante']


# =============================================================================
# Utilidades
# =============================================================================

class Contexto:
    """Lo que comparten las funciones de carga: el cursor, la fecha de
    referencia, Faker, los volumenes y los codigos que ya se asignaron."""

    def __init__(self, cur, ref, fake, vol):
        self.cur = cur
        self.ref = ref
        self.fake = fake
        self.vol = vol
        self.resumen = []          # (tabla, filas, segundos)
        self.cuits = set()         # todos los CUIT usados, para no repetir


def sumar_anios(d, n):
    """Suma n anios a una fecha. El 29/2 pasa al 28/2 si el anio no es bisiesto."""
    try:
        return d.replace(year=d.year + n)
    except ValueError:
        return d.replace(year=d.year + n, day=28)


def fecha_entre(desde, hasta):
    """Fecha al azar entre dos fechas, las dos incluidas."""
    return desde + timedelta(days=random.randint(0, (hasta - desde).days))


def decimal_entre(desde, hasta, decimales=2):
    """Decimal al azar con la cantidad de decimales pedida (nunca float)."""
    escala = 10 ** decimales
    n = random.randint(round(desde * escala), round(hasta * escala))
    return Decimal(n).scaleb(-decimales)


def sin_acentos(texto):
    normal = unicodedata.normalize('NFKD', texto)
    return ''.join(c for c in normal if c.isascii() and c.isalnum()).lower()


def cuit_nuevo(ctx, prefijo):
    """CUIT de 11 digitos: prefijo de 2 + 9 al azar, sin repetir."""
    while True:
        cuit = prefijo + f'{random.randint(0, 999_999_999):09d}'
        if cuit not in ctx.cuits:
            ctx.cuits.add(cuit)
            return cuit


def leer_csv(nombre):
    with open(CATALOGOS / nombre, encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))


def insertar(ctx, tabla, columnas, filas, identidad=None):
    """Inserta todas las filas de una tabla con un solo executemany y consultas
    parametrizadas (%s). Si la tabla tiene una columna IDENTITY, el script ya
    asigno los numeros: se insertan con OVERRIDING SYSTEM VALUE y al final se
    reinicia la secuencia en maximo + 1, para que la base siga numerando bien."""
    inicio = time.perf_counter()
    consulta = sql.SQL('INSERT INTO {} ({}) {} VALUES ({})').format(
        sql.Identifier(tabla),
        sql.SQL(', ').join(sql.Identifier(c) for c in columnas),
        sql.SQL('OVERRIDING SYSTEM VALUE' if identidad else ''),
        sql.SQL(', ').join([sql.Placeholder()] * len(columnas)))
    if filas:
        ctx.cur.executemany(consulta, filas)
    if identidad:
        i = columnas.index(identidad)
        siguiente = max((f[i] for f in filas), default=0) + 1
        ctx.cur.execute(sql.SQL('ALTER TABLE {} ALTER COLUMN {} RESTART WITH {}').format(
            sql.Identifier(tabla), sql.Identifier(identidad), sql.Literal(siguiente)))
    ctx.resumen.append((tabla, len(filas), time.perf_counter() - inicio))


def cambiar_triggers(cur, accion):
    """ALTER TABLE ... DISABLE/ENABLE TRIGGER USER. USER toca solo los triggers
    escritos por nosotros: las claves foraneas (que por dentro tambien son
    triggers) siguen controlando."""
    for tabla in TABLAS_SIN_TRIGGERS:
        cur.execute(sql.SQL('ALTER TABLE {} {} TRIGGER USER').format(
            sql.Identifier(tabla), sql.SQL(accion)))


# =============================================================================
# 1. Catalogos: no dependen de nadie
# =============================================================================

def cargar_catalogos(ctx):
    """departamento, localidad, cepa y maridaje, desde los CSV con datos reales.
    Van primero porque no tienen claves foraneas y casi todo lo demas los
    referencia (salas, clientes, fincas, parcelas, vinos)."""
    filas = leer_csv('departamentos_localidades.csv')
    ctx.departamentos = []                 # (id, nombre)
    ctx.localidades = []                   # ids
    ctx.localidad_por_nombre = {}
    deptos, locs = [], []
    for i, f in enumerate(filas, start=1):
        deptos.append((i, f['departamento'], 'Mendoza'))
        locs.append((i, f['localidad'], 'Mendoza', f['codigo_postal'], ctx.fake.name()))
        ctx.departamentos.append((i, f['departamento']))
        ctx.localidades.append(i)
        ctx.localidad_por_nombre[f['localidad']] = i
    insertar(ctx, 'departamento', ['id_departamento', 'nombre', 'provincia'], deptos,
             identidad='id_departamento')
    insertar(ctx, 'localidad', ['id_localidad', 'nombre', 'provincia', 'codigo_postal',
                                'encargado_regional'], locs, identidad='id_localidad')
    ctx.san_rafael = ctx.localidad_por_nombre[LOCALIDAD_SAN_RAFAEL]

    # Las 3 cepas «sin usar» se cargan pero nunca se asignan (consulta D2)
    cepas = [(i, f['nombre'], f['tipo']) for i, f in enumerate(leer_csv('cepas.csv'), start=1)]
    insertar(ctx, 'cepa', ['id_cepa', 'nombre', 'tipo'], cepas, identidad='id_cepa')
    ctx.cepas_usadas = [c for c in cepas if c[1] not in CEPAS_SIN_USAR]
    ctx.cepa_por_nombre = {c[1]: c for c in cepas}

    maridajes = [(i, f['nombre'], Decimal(f['temperatura_servicio']))
                 for i, f in enumerate(leer_csv('maridajes.csv'), start=1)]
    insertar(ctx, 'maridaje', ['id_maridaje', 'nombre', 'temperatura_servicio'], maridajes,
             identidad='id_maridaje')
    ctx.maridajes = [m[0] for m in maridajes]


# =============================================================================
# 2. Bodegas y transportistas: tampoco dependen de nadie (salvo la cobertura)
# =============================================================================

def cargar_bodegas(ctx):
    """bodega. Va antes que lotes, vinos e ingresos, que la referencian.
    Una se llama exactamente «Bodega Los Tres Vinos» (U3 y S12)."""
    nombres = set()
    filas = []
    for i in range(ctx.vol['bodegas']):
        if i == ctx.vol['bodegas'] - 1:
            nombre = BODEGA_TRES_VINOS
        else:
            nombre = f'Bodega {ctx.fake.last_name()}'
            while nombre in nombres or nombre == BODEGA_TRES_VINOS:
                nombre = f'Bodega {ctx.fake.last_name()}'
        nombres.add(nombre)
        localidad = random.choice(ctx.departamentos)[1]
        filas.append((cuit_nuevo(ctx, '30'), nombre,
                      f'{ctx.fake.street_address()}, {localidad}, Mendoza'))
    insertar(ctx, 'bodega', ['cuit', 'razon_social', 'domicilio'], filas)
    ctx.bodegas = [f[0] for f in filas]
    ctx.bodega_tres = filas[-1][0]
    ctx.bodegas_comunes = ctx.bodegas[:-1]


def cargar_transportistas(ctx):
    """transportista y transportista_localidad. La cobertura va despues de
    localidad y del transportista, porque referencia a los dos."""
    filas, cobertura = [], []
    for cod in range(1, ctx.vol['transportistas'] + 1):
        apellido = ctx.fake.last_name()
        filas.append((cod, f'Transportes {apellido} {random.choice(["S.A.", "S.R.L."])}',
                      cuit_nuevo(ctx, '33'), f'logistica@{sin_acentos(apellido)}{cod}.com.ar',
                      f'0261 4{random.randint(0, 999_999):06d}',
                      f'{ctx.fake.street_address()}, Mendoza'))
        for loc in random.sample(ctx.localidades, random.randint(*ctx.vol['cobertura'])):
            cobertura.append((cod, loc))
    insertar(ctx, 'transportista', ['cod_transporte', 'razon_social', 'cuit', 'email',
                                    'telefono', 'domicilio'], filas, identidad='cod_transporte')
    insertar(ctx, 'transportista_localidad', ['cod_transporte', 'id_localidad'], cobertura)
    ctx.transportistas = [f[0] for f in filas]


# =============================================================================
# 3. Salas y empleados
# =============================================================================

def cargar_salas(ctx):
    """sala_venta. Depende de localidad. Al menos una en San Rafael (D3) y al
    menos k salas que cierran los lunes y k los miercoles (U4)."""
    n = ctx.vol['salas']
    otras = [l for l in ctx.localidades if l != ctx.san_rafael]
    if n <= len(ctx.localidades):
        locs = [ctx.san_rafael] + random.sample(otras, n - 1)
    else:
        locs = ctx.localidades + [random.choice(ctx.localidades)
                                  for _ in range(n - len(ctx.localidades))]
    random.shuffle(locs)

    k = ctx.vol['dias_cierre_min']
    dias = ['lunes'] * k + ['miercoles'] * k + [random.choice(DIAS) for _ in range(n - 2 * k)]
    random.shuffle(dias)

    filas = [(i, ctx.fake.street_name()[:80], random.randint(1, 3000), dias[i - 1], locs[i - 1])
             for i in range(1, n + 1)]
    insertar(ctx, 'sala_venta', ['id_sala', 'calle', 'numero', 'dia_cierre', 'id_localidad'],
             filas, identidad='id_sala')
    ctx.salas = [f[0] for f in filas]
    ctx.sala_san_rafael = next(f[0] for f in filas if f[4] == ctx.san_rafael)


def cargar_empleados(ctx):
    """empleado. Depende de sala_venta. Las antiguedades se reparten a
    proposito: al menos 30 % con mas de 5 anios (U2) y al menos 10 % con menos
    de 2; dos de los nuevos trabajan en la sala de San Rafael (D3)."""
    ref = ctx.ref
    n = ctx.vol['empleados']
    n_nuevos = max(2, math.ceil(0.15 * n))
    n_viejos = math.ceil(0.35 * n)

    # «Nuevo»: entre 18 meses y 1 mes (menos de 2 anios, con margen por si las
    # consultas se corren unos meses despues). «Viejo»: 6 anios o mas.
    def fecha(categoria):
        if categoria == 'nuevo':
            return fecha_entre(ref - timedelta(days=548), ref - timedelta(days=30))
        if categoria == 'viejo':
            return fecha_entre(sumar_anios(ref, -15), sumar_anios(ref, -6))
        return fecha_entre(sumar_anios(ref, -15), ref - timedelta(days=30))

    categorias = ['nuevo'] * (n_nuevos - 2) + ['viejo'] * n_viejos
    categorias += ['libre'] * (n - 2 - len(categorias))
    random.shuffle(categorias)
    salas = [ctx.salas[i % len(ctx.salas)] for i in range(n - 2)]
    random.shuffle(salas)

    plan = [('nuevo', ctx.sala_san_rafael)] * 2 + list(zip(categorias, salas))
    filas = []
    for categoria, sala in plan:
        filas.append((cuit_nuevo(ctx, '20'), ctx.fake.name()[:100], fecha(categoria),
                      Decimal(random.randint(7_000, 25_000) * 100), sala))
    insertar(ctx, 'empleado', ['cuit', 'nombre', 'fecha_ingreso', 'salario', 'id_sala'], filas)


# =============================================================================
# 4. Produccion de uva
# =============================================================================

def cargar_fincas_parcelas(ctx):
    """finca y parcela. La finca depende de departamento; la parcela es debil
    de la finca (nro_parcela 1, 2, 3... dentro de cada una) y usa una de las 12
    cepas en uso. La suma de las parcelas no supera la superficie de la finca.
    Las primeras parcelas recorren las 12 cepas, para que ninguna quede sin
    uso por azar: D2 tiene que encontrar solo las 3 «sin usar»."""
    fincas, parcelas = [], []
    ctx.parcelas = []                      # (id_finca, nro, superficie)
    orden = random.sample(ctx.cepas_usadas, len(ctx.cepas_usadas))
    for id_finca in range(1, ctx.vol['fincas'] + 1):
        superficie = decimal_entre(10, 200)
        fincas.append((id_finca, f'Finca {ctx.fake.last_name()}', superficie,
                       random.choice(ctx.departamentos)[0]))
        # Se reparte entre 60 % y 95 % de la finca, en partes al azar
        a_repartir = superficie * Decimal(random.randint(60, 95)) / 100
        pesos = [random.randint(1, 10) for _ in range(ctx.vol['parcelas_por_finca'])]
        for nro, peso in enumerate(pesos, start=1):
            sup = (a_repartir * peso / sum(pesos)).quantize(Decimal('0.01'), ROUND_DOWN)
            k = len(parcelas)
            cepa = orden[k] if k < len(orden) else random.choice(ctx.cepas_usadas)
            parcelas.append((id_finca, nro, sup, random.randint(1990, 2020), cepa[0]))
            ctx.parcelas.append((id_finca, nro, sup))
    ctx.cepas_en_parcelas = {p[4] for p in parcelas}
    insertar(ctx, 'finca', ['id_finca', 'nombre', 'superficie_ha', 'id_departamento'], fincas,
             identidad='id_finca')
    insertar(ctx, 'parcela', ['id_finca', 'nro_parcela', 'superficie_ha', 'anio_plantacion',
                              'id_cepa'], parcelas)


def cargar_lotes(ctx):
    """lote_uva y analisis_calidad. El lote necesita la parcela y la bodega; el
    analisis necesita el lote. Una cosecha por parcela y campania (las ultimas
    5), y campania = anio de la fecha de cosecha."""
    ref = ctx.ref
    lotes, analisis = [], []
    for id_finca, nro, sup in ctx.parcelas:
        for campania in range(ref.year - 4, ref.year + 1):
            if random.random() >= 0.9:
                continue
            cosecha = fecha_entre(date(campania, 2, 1), date(campania, 4, 30))
            if cosecha > ref:
                continue
            kilos = (sup * decimal_entre(5000, 12000)).quantize(Decimal('0.01'))
            nro_lote = len(lotes) + 1
            lotes.append((nro_lote, id_finca, nro, campania, cosecha, kilos,
                          random.choice(ctx.bodegas)))
            for _ in range(random.randint(1, ctx.vol['analisis_max'])):
                fecha = min(cosecha + timedelta(days=random.randint(0, 10)), ref)
                analisis.append((len(analisis) + 1, nro_lote, fecha, decimal_entre(18, 27),
                                 decimal_entre(3, 4), decimal_entre(4, 8.5)))
    insertar(ctx, 'lote_uva', ['nro_lote', 'id_finca', 'nro_parcela', 'campania',
                               'fecha_cosecha', 'kilos', 'cuit_bodega'], lotes,
             identidad='nro_lote')
    insertar(ctx, 'analisis_calidad', ['id_analisis', 'nro_lote', 'fecha', 'brix', 'ph',
                                       'acidez_total'], analisis, identidad='id_analisis')


# =============================================================================
# 5. Vinos
# =============================================================================

def composicion_al_azar(ctx, principal):
    """1 a 3 cepas del mismo color que suman exactamente 100. La primera es la
    principal (la que define el nombre y el tipo del vino)."""
    cantidad = random.choice([1, 2, 3])
    if cantidad == 1:
        porcentajes = [100]
    elif cantidad == 2:
        p = random.choice(range(60, 100, 5))
        porcentajes = [p, 100 - p]
    else:
        p = random.choice(range(50, 85, 5))
        s = random.choice(range(5, 100 - p - 5 + 1, 5))
        porcentajes = [p, max(s, 100 - p - s), min(s, 100 - p - s)]
    otras = [c for c in ctx.cepas_usadas if c[2] == principal[2] and c[0] != principal[0]]
    cepas = [principal] + random.sample(otras, cantidad - 1)
    return [(c[0], Decimal(pct)) for c, pct in zip(cepas, porcentajes)]


def tipo_segun_cepa(principal):
    """Tinta: tinto (90 %) o rosado (10 %). Blanca: blanco. Ademas, 5 % de los
    Chardonnay y Pinot Noir son espumantes."""
    if principal[2] == 'tinta':
        tipo = 'tinto' if random.random() < 0.9 else 'rosado'
    else:
        tipo = 'blanco'
    if principal[1] in ('Chardonnay', 'Pinot Noir') and random.random() < 0.05:
        tipo = 'espumante'
    return tipo


def cargar_vinos(ctx):
    """vino, composicion y vino_maridaje. El vino depende de bodega; las dos
    tablas intermedias dependen del vino, de la cepa y del maridaje.
    Primero van los casos fijos: los 3 «Malbec Reserva» (cod 1 = el de 750 ml
    de Ref - 4, el que buscan las consultas) y los 3 de «Bodega Los Tres
    Vinos». El resto, al azar. El trigger de composicion queda activo."""
    ref = ctx.ref
    vinos = []                             # dicts
    usados = set()                         # (nombre, anada, volumen)

    def agregar(nombre, tipo, anada, volumen, cuit, composicion):
        usados.add((nombre, anada, volumen))
        vinos.append(dict(cod=len(vinos) + 1, nombre=nombre, tipo=tipo, anada=anada,
                          volumen=volumen, graduacion=decimal_entre(11.5, 15.5),
                          precio=Decimal(random.randint(40, 600) * 100), cuit=cuit,
                          composicion=composicion))

    def nombre_al_azar(cepas):
        while True:
            principal = random.choice(cepas)
            nombre = f'{principal[1]} {random.choice(LINEAS)}'
            anada = random.randint(ref.year - 6, ref.year - 1)
            volumen = 750 if random.random() < 0.7 else random.choice(OTROS_VOLUMENES)
            if nombre != VINO_FIJO and (nombre, anada, volumen) not in usados:
                return principal, nombre, anada, volumen

    malbec = ctx.cepa_por_nombre['Malbec']
    bodega_malbec = random.choice(ctx.bodegas_comunes)
    for anada, volumen in [(ref.year - 4, 750), (ref.year - 5, 750), (ref.year - 4, 1500)]:
        agregar(VINO_FIJO, 'tinto', anada, volumen, bodega_malbec, [(malbec[0], Decimal(100))])
    ctx.vino_fijo = 1

    tintas = [c for c in ctx.cepas_usadas if c[2] == 'tinta']
    for _ in range(3):
        principal, nombre, anada, volumen = nombre_al_azar(tintas)
        agregar(nombre, 'tinto', anada, volumen, ctx.bodega_tres,
                composicion_al_azar(ctx, principal))
    ctx.vinos_tres = [4, 5, 6]

    # Si hay pocas parcelas (modo chico), algunas cepas no quedaron plantadas:
    # los primeros vinos al azar las usan como principal, asi ninguna de las 12
    # queda sin uso (D2 solo tiene que encontrar las 3 «sin usar»).
    en_uso = ctx.cepas_en_parcelas | {c for v in vinos for c, _ in v['composicion']}
    pendientes = [c for c in ctx.cepas_usadas if c[0] not in en_uso]
    while len(vinos) < ctx.vol['vinos']:
        cepas = [pendientes.pop(0)] if pendientes else ctx.cepas_usadas
        principal, nombre, anada, volumen = nombre_al_azar(cepas)
        agregar(nombre, tipo_segun_cepa(principal), anada, volumen,
                random.choice(ctx.bodegas_comunes), composicion_al_azar(ctx, principal))

    # Al menos 15 % de los tintos con 14 grados o mas (I2)
    tintos = [v for v in vinos if v['tipo'] == 'tinto']
    faltan = math.ceil(0.15 * len(tintos)) - sum(v['graduacion'] >= 14 for v in tintos)
    if faltan > 0:
        for v in random.sample([v for v in tintos if v['graduacion'] < 14], faltan):
            v['graduacion'] = decimal_entre(14, 15.5)

    insertar(ctx, 'vino', ['cod_vino', 'nombre', 'tipo', 'anada', 'volumen_ml', 'graduacion',
                           'precio', 'cuit_bodega'],
             [(v['cod'], v['nombre'], v['tipo'], v['anada'], v['volumen'], v['graduacion'],
               v['precio'], v['cuit']) for v in vinos], identidad='cod_vino')
    insertar(ctx, 'composicion', ['cod_vino', 'id_cepa', 'porcentaje'],
             [(v['cod'], cepa, pct) for v in vinos for cepa, pct in v['composicion']])
    insertar(ctx, 'vino_maridaje', ['cod_vino', 'id_maridaje'],
             [(v['cod'], m) for v in vinos
              for m in random.sample(ctx.maridajes, random.randint(1, 3))])

    ctx.vinos = [v['cod'] for v in vinos]
    ctx.precio = {v['cod']: v['precio'] for v in vinos}
    ctx.vinos_por_bodega = {}
    for v in vinos:
        ctx.vinos_por_bodega.setdefault(v['cuit'], []).append(v['cod'])


# =============================================================================
# 6. Clientes
# =============================================================================

def cargar_clientes(ctx):
    """cliente, socio, distribuidor, exportador y permiso_exportacion. El
    cliente depende de localidad; cada subtipo depende del cliente y el permiso
    del exportador. El descuento NO se carga: lo pone el trigger T8 segun el
    tipo. 6 % de los socios no compran nunca (D4 y D6)."""
    ref = ctx.ref
    v = ctx.vol
    n = v['clientes']
    n_socios = round(0.7 * n)
    n_dist = round(0.2 * n)
    tipos = (['socio'] * n_socios + ['distribuidor'] * n_dist
             + ['exportador'] * (n - n_socios - n_dist))
    random.shuffle(tipos)

    # Socios que no compran: los primeros, con alta de hace mas de 5 anios (D4);
    # los siguientes, de San Rafael (D6); el resto, comunes.
    socios = [i for i, t in enumerate(tipos) if t == 'socio']
    viejos, de_san_rafael = v['socios_viejos_sin_compras'], v['socios_san_rafael_sin_compras']
    sin_compras = random.sample(socios, max(math.ceil(0.06 * n_socios), viejos + de_san_rafael))
    forzar_viejo = set(sin_compras[:viejos])
    forzar_san_rafael = set(sin_compras[viejos:viejos + de_san_rafael])
    sin_compras = set(sin_compras)

    dnis = set()
    clientes, filas_socio, filas_dist, filas_exp = [], [], [], []
    habilitaciones = set()
    ctx.compradores = []                   # (fecha_alta, id, tipo)
    for i, tipo in enumerate(tipos):
        id_cliente = i + 1
        if tipo == 'socio':
            doc = str(random.randint(10_000_000, 99_999_999))
            while doc in dnis:
                doc = str(random.randint(10_000_000, 99_999_999))
            dnis.add(doc)
            tipo_doc, nombre = 'DNI', ctx.fake.name()
        else:
            tipo_doc, doc = 'CUIT', cuit_nuevo(ctx, '30')
            rubro = 'Distribuciones' if tipo == 'distribuidor' else 'Export'
            nombre = f'{ctx.fake.last_name()} {rubro} {random.choice(["S.A.", "S.R.L."])}'
        if i in forzar_viejo:
            alta = fecha_entre(sumar_anios(ref, -8), sumar_anios(ref, -5) - timedelta(days=90))
        else:
            alta = fecha_entre(sumar_anios(ref, -8), ref - timedelta(days=30))
        localidad = ctx.san_rafael if i in forzar_san_rafael else random.choice(ctx.localidades)
        clientes.append((id_cliente, nombre[:120], tipo_doc, doc,
                         ctx.fake.street_address()[:150], localidad, alta, tipo))

        if tipo == 'socio':
            filas_socio.append((id_cliente,))
        elif tipo == 'distribuidor':
            hab = f'HAB-{random.randint(0, 999_999):06d}'
            while hab in habilitaciones:
                hab = f'HAB-{random.randint(0, 999_999):06d}'
            habilitaciones.add(hab)
            filas_dist.append((id_cliente, random.choice(ctx.departamentos)[1], hab))
        else:
            filas_exp.append((id_cliente, random.choice(PAISES)))
        if i not in sin_compras:
            ctx.compradores.append((alta, id_cliente, tipo))

    insertar(ctx, 'cliente', ['id_cliente', 'nombre_razon_social', 'tipo_documento',
                              'nro_documento', 'direccion', 'id_localidad', 'fecha_alta',
                              'tipo_cliente'], clientes, identidad='id_cliente')
    insertar(ctx, 'socio', ['id_cliente'], filas_socio)
    insertar(ctx, 'distribuidor', ['id_cliente', 'zona_cobertura', 'nro_habilitacion'],
             filas_dist)
    insertar(ctx, 'exportador', ['id_cliente', 'pais_destino'], filas_exp)

    # Permisos: al menos 20 % de los exportadores con 4 o mas (U6)
    exportadores = [f[0] for f in filas_exp]
    random.shuffle(exportadores)
    con_cuatro = math.ceil(0.2 * len(exportadores))
    permisos = []
    for j, id_cliente in enumerate(exportadores):
        cantidad = random.randint(4, 6) if j < con_cuatro else random.randint(1, 6)
        for _ in range(cantidad):
            emision = fecha_entre(sumar_anios(ref, -5), ref)
            permisos.append((f'PE-{len(permisos) + 1:06d}', id_cliente, emision,
                             sumar_anios(emision, random.randint(1, 3))))
    insertar(ctx, 'permiso_exportacion', ['codigo', 'id_cliente', 'fecha_emision',
                                          'fecha_vencimiento'], permisos)

    # Para elegir rapido un cliente dado de alta antes de una fecha
    ctx.compradores.sort()
    ctx.altas = [c[0] for c in ctx.compradores]
    ctx.socios_compradores = [c for c in ctx.compradores if c[2] == 'socio']
    ctx.altas_socios = [c[0] for c in ctx.socios_compradores]


def cliente_antes_de(ctx, fecha, solo_socios=False):
    """Un cliente (que compra) con fecha_alta anterior a la fecha, o None."""
    lista = ctx.socios_compradores if solo_socios else ctx.compradores
    altas = ctx.altas_socios if solo_socios else ctx.altas
    k = bisect.bisect_left(altas, fecha)   # cuantos tienen alta < fecha
    if k == 0:
        return None
    return lista[random.randrange(k)]


# =============================================================================
# 7. Ingresos y transferencias (triggers apagados)
# =============================================================================

def cargar_ingresos(ctx):
    """ingreso y renglon_ingreso. Dependen de transportista, bodega y vino. Se
    cargan con los triggers apagados: el de renglones rechazaria agregar
    renglones a un ingreso ya procesado. En los ultimos 30 dias hay 3 ingresos
    de transportistas distintos (I1, S7)."""
    ref = ctx.ref
    bodegas = [b for b in ctx.bodegas if ctx.vinos_por_bodega.get(b)]
    recientes = random.sample(ctx.transportistas, min(3, len(ctx.transportistas)))
    ingresos = [(fecha_entre(ref - timedelta(days=29), ref), t) for t in recientes]
    while len(ingresos) < ctx.vol['ingresos']:
        ingresos.append((fecha_entre(sumar_anios(ref, -6), ref),
                         random.choice(ctx.transportistas)))
    ingresos.sort(key=lambda x: x[0])      # ordenados por fecha

    corte = ref - timedelta(days=30)
    cabeceras, renglones = [], []
    ciclo = 0
    for cod, (fecha, transportista) in enumerate(ingresos, start=1):
        if fecha < corte:
            estado = 'procesado'
        else:
            estado = ESTADOS[ciclo % 3]
            ciclo += 1
        bodega = random.choice(bodegas)
        cabeceras.append((cod, fecha, estado, transportista, bodega))
        vinos = ctx.vinos_por_bodega[bodega]
        for vino in random.sample(vinos, min(random.randint(1, 5), len(vinos))):
            renglones.append((cod, vino, 6 * random.randint(2, 100)))
    insertar(ctx, 'ingreso', ['cod_ingreso', 'fecha', 'estado', 'cod_transporte',
                              'cuit_bodega'], cabeceras, identidad='cod_ingreso')
    insertar(ctx, 'renglon_ingreso', ['cod_ingreso', 'cod_vino', 'cantidad'], renglones)


def cargar_transferencias(ctx):
    """transferencia y renglon_transferencia. Dependen de sala y vino. Con los
    triggers apagados, porque el de la fecha pisaria la fecha historica con la
    de hoy. En los ultimos 15 dias, 5 salas distintas piden el «Malbec Reserva»
    de 750 ml con cantidades distintas (S4), y 2 salas no tienen ninguna
    pendiente (S5)."""
    ref = ctx.ref
    hace_15 = ref - timedelta(days=15)
    sin_pendientes = set(random.sample(ctx.salas[1:], 2))

    transferencias = []                    # (fecha, sala, [(vino, cantidad)])
    salas_s4 = random.sample(ctx.salas, min(5, len(ctx.salas)))
    cantidades_s4 = random.sample(range(6, 121), len(salas_s4))
    otros = [v for v in ctx.vinos if v != ctx.vino_fijo]
    for sala, cantidad in zip(salas_s4, cantidades_s4):
        renglones = [(ctx.vino_fijo, cantidad)]
        renglones += [(v, random.randint(6, 120))
                      for v in random.sample(otros, random.randint(0, 2))]
        transferencias.append((fecha_entre(ref - timedelta(days=14), ref), sala, renglones))

    while len(transferencias) < ctx.vol['transferencias']:
        fecha = fecha_entre(sumar_anios(ref, -6), ref)
        # Las recientes al azar no piden el vino fijo, para no alterar S4
        candidatos = otros if fecha >= hace_15 else ctx.vinos
        vinos = random.sample(candidatos, min(random.randint(1, 5), len(candidatos)))
        transferencias.append((fecha, random.choice(ctx.salas),
                               [(v, random.randint(6, 120)) for v in vinos]))
    transferencias.sort(key=lambda x: x[0])

    cabeceras, filas = [], []
    ciclo = 0
    for nro, (fecha, sala, renglones) in enumerate(transferencias, start=1):
        if fecha < hace_15 or sala in sin_pendientes:
            estado = 'procesado'
        else:
            estado = ESTADOS[ciclo % 3]
            ciclo += 1
        cabeceras.append((nro, sala, fecha, estado))
        filas.extend((nro, vino, cantidad) for vino, cantidad in renglones)
    insertar(ctx, 'transferencia', ['nro_solicitud', 'id_sala', 'fecha_confeccion', 'estado'],
             cabeceras, identidad='nro_solicitud')
    insertar(ctx, 'renglon_transferencia', ['nro_solicitud', 'cod_vino', 'cantidad'], filas)


# =============================================================================
# 8. Ventas (triggers apagados) e importes
# =============================================================================

def cargar_ventas(ctx):
    """comprobante y renglon_comprobante. Dependen de cliente, sala y vino.
    Con los triggers apagados: los de venta descontarian un stock que todavia
    no existe. Los importes quedan en 0 y se calculan despues en SQL
    (calcular_importes). Se insertan ordenados por fecha (indice BRIN)."""
    ref = ctx.ref
    hace_6_anios = sumar_anios(ref, -6)

    def nuevo(fecha, cliente, sala, vinos_fijos=()):
        k = max(len(vinos_fijos), random.randint(1, 4))
        resto = [v for v in ctx.vinos if v not in vinos_fijos]
        vinos = list(vinos_fijos) + random.sample(resto, k - len(vinos_fijos))
        return (fecha, cliente, sala, vinos)

    def con_cliente(desde, hasta, solo_socios=False):
        while True:
            fecha = fecha_entre(desde, hasta)
            cliente = cliente_antes_de(ctx, fecha, solo_socios)
            if cliente:
                return fecha, cliente

    comprobantes = []
    # S2: el «Malbec Reserva» de 750 ml se vendio en todas las salas
    for sala in ctx.salas:
        fecha, cliente = con_cliente(hace_6_anios, ref)
        comprobantes.append(nuevo(fecha, cliente, sala, [ctx.vino_fijo]))
    # S12: un cliente compro los 3 vinos de «Bodega Los Tres Vinos»
    fecha, cliente = con_cliente(hace_6_anios, ref)
    comprobantes.append(nuevo(fecha, cliente, random.choice(ctx.salas), ctx.vinos_tres))
    # S3: al menos 10 en los ultimos 7 dias, uno en la sala 1
    for j in range(10):
        fecha, cliente = con_cliente(ref - timedelta(days=6), ref)
        comprobantes.append(nuevo(fecha, cliente, 1 if j == 0 else random.choice(ctx.salas)))
    # D1: comprobantes de socios con mas de 5 anios
    for _ in range(3):
        fecha, cliente = con_cliente(hace_6_anios, sumar_anios(ref, -5) - timedelta(days=30),
                                     solo_socios=True)
        comprobantes.append(nuevo(fecha, cliente, random.choice(ctx.salas)))
    # El resto: 85 % en los ultimos 6 anios, 15 % en los ultimos 90 dias
    while len(comprobantes) < ctx.vol['comprobantes']:
        desde = hace_6_anios if random.random() < 0.85 else ref - timedelta(days=89)
        fecha, cliente = con_cliente(desde, ref)
        comprobantes.append(nuevo(fecha, cliente, random.choice(ctx.salas)))
    comprobantes.sort(key=lambda x: x[0])

    cabeceras, renglones = [], []
    for nro, (fecha, (_, id_cliente, tipo), sala, vinos) in enumerate(comprobantes, start=1):
        cabeceras.append((nro, fecha, id_cliente, sala))
        for vino in vinos:
            cantidad = random.randint(1, 6) if tipo == 'socio' else random.randint(6, 24)
            renglones.append((nro, vino, cantidad, ctx.precio[vino], Decimal(0), Decimal(0)))
    insertar(ctx, 'comprobante', ['nro', 'fecha', 'id_cliente', 'id_sala'], cabeceras,
             identidad='nro')
    insertar(ctx, 'renglon_comprobante', ['nro_comprobante', 'cod_vino', 'cantidad',
                                          'precio_unitario', 'descuento', 'subtotal'],
             renglones)


def calcular_importes(ctx):
    """Con los triggers todavia apagados, calcula en SQL los importes de
    renglones y comprobantes con la misma formula que el trigger
    trg_renglon_venta_validar. Dos UPDATE masivos en vez de 120.000 disparos."""
    inicio = time.perf_counter()
    ctx.cur.execute("""
        UPDATE renglon_comprobante r
           SET descuento = ROUND(r.cantidad * r.precio_unitario * cl.descuento / 100, 2),
               subtotal  = r.cantidad * r.precio_unitario
                           - ROUND(r.cantidad * r.precio_unitario * cl.descuento / 100, 2)
          FROM comprobante c
          JOIN cliente cl ON cl.id_cliente = c.id_cliente
         WHERE c.nro = r.nro_comprobante""")
    ctx.cur.execute("""
        UPDATE comprobante c
           SET subtotal  = s.subtotal,
               descuento = s.descuento,
               total     = s.subtotal - s.descuento
          FROM (SELECT nro_comprobante,
                       SUM(cantidad * precio_unitario) AS subtotal,
                       SUM(descuento) AS descuento
                  FROM renglon_comprobante
                 GROUP BY nro_comprobante) s
         WHERE c.nro = s.nro_comprobante""")
    ctx.resumen.append(('(importes de ventas)', ctx.cur.rowcount, time.perf_counter() - inicio))


# =============================================================================
# 9. Stock: foto actual
# =============================================================================

def cargar_stock(ctx):
    """stock_deposito y stock_sala, como foto del dia de referencia (no se
    deduce de la historia). Van al final porque dependen de vino y sala.
    Casos: el «Malbec Reserva» tiene stock en el deposito (I6, S4); la sala 1
    tiene al menos k vinos con 10 o mas botellas (I3) y le faltan al menos 5
    que si hay en el deposito (S6)."""
    deposito = {v: random.randint(0, 2000) for v in ctx.vinos}
    deposito[ctx.vino_fijo] = random.randint(200, 2000)

    def cantidad_comun():
        return 0 if random.random() < 0.05 else random.randint(1, 150)

    n = len(ctx.vinos)
    por_sala = round(0.6 * n)
    filas_sala = []
    for sala in ctx.salas:
        if sala == 1:
            presentes_n = min(por_sala, n - 5)
            faltan = random.sample(ctx.vinos, n - presentes_n)
            for v in faltan[:5]:
                if deposito[v] == 0:
                    deposito[v] = random.randint(1, 2000)
            presentes = [v for v in ctx.vinos if v not in set(faltan)]
            con_stock = set(random.sample(presentes, min(ctx.vol['sala1_con_stock'],
                                                         len(presentes))))
            for v in presentes:
                cantidad = random.randint(10, 150) if v in con_stock else cantidad_comun()
                filas_sala.append((sala, v, cantidad))
        else:
            for v in random.sample(ctx.vinos, por_sala):
                filas_sala.append((sala, v, cantidad_comun()))

    insertar(ctx, 'stock_deposito', ['cod_vino', 'cantidad'], sorted(deposito.items()))
    insertar(ctx, 'stock_sala', ['id_sala', 'cod_vino', 'cantidad'], filas_sala)


# =============================================================================
# 10. Auditoria de precios (con el trigger activo)
# =============================================================================

def aumentar_precios(ctx):
    """Sube 5 % el precio de algunos vinos. No se inserta en auditoria_precio a
    mano: las filas las escribe el trigger T6, que nunca se apago. Va al final
    para que los precios historicos de las ventas sean los de antes."""
    inicio = time.perf_counter()
    vinos = random.sample(ctx.vinos, ctx.vol['aumentos_precio'])
    ctx.cur.executemany('UPDATE vino SET precio = ROUND(precio * 1.05, 2) WHERE cod_vino = %s',
                        [(v,) for v in vinos])
    ctx.cur.execute('SELECT count(*) FROM auditoria_precio')
    ctx.resumen.append(('auditoria_precio', ctx.cur.fetchone()[0], time.perf_counter() - inicio))


# =============================================================================
# Salida: resumen, controles y medicion
# =============================================================================

def imprimir_tabla(columnas, filas):
    textos = [[str(c) for c in columnas]] + [[str(x) for x in f] for f in filas]
    anchos = [max(len(t[i]) for t in textos) for i in range(len(columnas))]
    for j, t in enumerate(textos):
        print('  ' + ' | '.join(x.rjust(a) if j and x.replace('.', '').isdigit() else x.ljust(a)
                                for x, a in zip(t, anchos)))
        if j == 0:
            print('  ' + '-+-'.join('-' * a for a in anchos))


def correr_controles(conn):
    """Corre las consultas de control.sql. Cada \\echo es un titulo; cada
    sentencia termina en ';'."""
    print('\n=== Controles (control.sql) ===')
    sentencia = []
    with conn.cursor() as cur:
        for linea in (CARPETA / 'control.sql').read_text(encoding='utf-8').splitlines():
            limpia = linea.strip()
            if not limpia or limpia.startswith('--'):
                continue
            if limpia.startswith('\\echo'):
                print('\n' + limpia[len('\\echo'):].strip().strip("'"))
                continue
            sentencia.append(linea)
            if limpia.endswith(';'):
                cur.execute('\n'.join(sentencia))
                imprimir_tabla([d.name for d in cur.description], cur.fetchall())
                sentencia = []
    conn.rollback()                        # solo lectura


def medir(conn):
    """--medir: 5.000 filas de a una (un execute por fila, un viaje a la base
    por fila) contra 5.000 filas con executemany, en una tabla temporal con las
    mismas columnas que renglon_comprobante. No toca las tablas reales."""
    filas = [(i, 1, 1, Decimal('1000.00'), Decimal('100.00'), Decimal('900.00'))
             for i in range(1, 5001)]
    consulta = 'INSERT INTO medicion VALUES (%s, %s, %s, %s, %s, %s)'
    with conn.cursor() as cur:
        cur.execute('CREATE TEMP TABLE medicion (LIKE renglon_comprobante)')
        inicio = time.perf_counter()
        for f in filas:
            cur.execute(consulta, f)
        de_a_una = time.perf_counter() - inicio
        cur.execute('TRUNCATE medicion')
        inicio = time.perf_counter()
        cur.executemany(consulta, filas)
        por_lotes = time.perf_counter() - inicio
    conn.rollback()
    print(f'5.000 filas con un execute por fila: {de_a_una:.2f} s')
    print(f'5.000 filas con executemany:         {por_lotes:.2f} s')
    print(f'executemany fue {de_a_una / por_lotes:.1f} veces mas rapido')


# =============================================================================
# Programa principal
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description='Carga de datos de prueba (etapa 3).')
    parser.add_argument('--chico', action='store_true', help='volumen chico, en segundos')
    parser.add_argument('--fecha-referencia', type=date.fromisoformat, default=date.today(),
                        metavar='AAAA-MM-DD', help='el «hoy» de los datos (por defecto, hoy)')
    parser.add_argument('--medir', action='store_true',
                        help='solo mide execute fila por fila contra executemany')
    args = parser.parse_args()

    random.seed(2026)
    Faker.seed(2026)
    fake = Faker('es_AR')
    modo = 'chico' if args.chico else 'completo'

    with psycopg.connect() as conn:
        if args.medir:
            medir(conn)
            return

        cur = conn.cursor()
        cur.execute('SELECT count(*) FROM vino')
        if cur.fetchone()[0] > 0:
            print('La base ya tiene datos: recreala antes de cargar')
            sys.exit(1)

        print(f'Carga {modo}, fecha de referencia {args.fecha_referencia}')
        ctx = Contexto(cur, args.fecha_referencia, fake, VOLUMENES[modo])
        inicio = time.perf_counter()

        cargar_catalogos(ctx)
        cargar_bodegas(ctx)
        cargar_transportistas(ctx)
        cargar_salas(ctx)
        cargar_empleados(ctx)
        cargar_fincas_parcelas(ctx)
        cargar_lotes(ctx)
        cargar_vinos(ctx)
        cargar_clientes(ctx)

        cambiar_triggers(cur, 'DISABLE')
        try:
            cargar_ingresos(ctx)
            cargar_transferencias(ctx)
            cargar_ventas(ctx)
            calcular_importes(ctx)
            cargar_stock(ctx)
        finally:
            # Si la transaccion fallo, no se puede ejecutar nada mas: el ROLLBACK
            # deshace tambien el DISABLE (en PostgreSQL el ALTER TABLE es
            # transaccional), asi que los triggers quedan activos igual.
            if conn.info.transaction_status == TransactionStatus.INTRANS:
                cambiar_triggers(cur, 'ENABLE')

        aumentar_precios(ctx)
        conn.commit()
        total = time.perf_counter() - inicio

        print('\n=== Filas cargadas y tiempo por tabla ===')
        imprimir_tabla(['tabla', 'filas', 'segundos'],
                       [(t, f, f'{s:.2f}') for t, f, s in ctx.resumen])
        print(f'\nTiempo total: {total:.1f} s')

        correr_controles(conn)


if __name__ == '__main__':
    main()
