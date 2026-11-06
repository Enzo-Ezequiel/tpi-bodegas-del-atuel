"""
main.py - Rutas de la API REST de «Bodegas del Atuel».

Cada ruta recibe el pedido, llama a una funcion de db.py y devuelve el
resultado en JSON. No hay SQL aca ni ningun calculo de importes o stock.

Como se levanta (ver README.md):
    uvicorn main:app --reload        (desde la carpeta api/)
La documentacion Swagger queda en http://localhost:8000/docs
"""

import os
from contextlib import asynccontextmanager
from decimal import Decimal

import psycopg
from fastapi import FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

import db


@asynccontextmanager
async def ciclo_de_vida(app):
    db.abrir()       # abre el pool al arrancar
    yield
    db.cerrar()      # y lo cierra al apagar


app = FastAPI(title='API Bodegas del Atuel',
              description='TPI Bases de Datos, UTN FRSR 2026. Las reglas de negocio '
                          'las controla la base: la API solo llama.',
              lifespan=ciclo_de_vida)

# CORS: el navegador solo deja que el front llame a la API si la API acepta
# su origen. En Docker el front esta en el puerto 8080.
app.add_middleware(CORSMiddleware,
                   allow_origins=os.getenv('CORS_ORIGINS',
                                         'http://localhost:8080,http://127.0.0.1:8080').split(','),
                   allow_methods=['*'], allow_headers=['*'])


# =============================================================================
# Traduccion de errores: SQLSTATE de PostgreSQL -> codigo HTTP
# El mensaje se devuelve tal como lo escribio la base (por ejemplo, el RAISE
# EXCEPTION de un trigger), para que el front lo muestre sin cambiarlo.
# =============================================================================

ERRORES = {
    '23505': (409, 'Ya existe (UNIQUE o clave primaria)'),
    '23503': (409, 'Lo impide una clave foranea'),
    '23001': (409, 'Lo impide una clave foranea con ON DELETE RESTRICT'),
    '23514': (422, 'No cumple una restriccion CHECK'),
    '23502': (422, 'Falta un dato obligatorio (NOT NULL)'),
    'P0001': (409, None),               # RAISE EXCEPTION: el mensaje ya explica la regla
    '22P02': (400, 'Formato invalido para el tipo de dato'),
    '22001': (422, 'Texto demasiado largo'),
    '22003': (422, 'Numero fuera de rango'),
    '40001': (503, 'Conflicto con otra operacion, reintentar'),
    '40P01': (503, 'Conflicto con otra operacion, reintentar'),
}


@app.exception_handler(psycopg.Error)
async def error_de_la_base(request: Request, error: psycopg.Error):
    codigo = error.sqlstate or ''
    http, titulo = ERRORES.get(codigo, (500, 'Error de la base de datos'))
    mensaje = error.diag.message_primary or str(error)
    return JSONResponse(status_code=http, content={
        'detail': f'{titulo}: {mensaje}' if titulo else mensaje,
        'sqlstate': codigo,
        'restriccion': error.diag.constraint_name,
    })


@app.exception_handler(db.NoEncontrado)
async def no_encontrado(request: Request, error: db.NoEncontrado):
    return JSONResponse(status_code=404, content={'detail': 'No existe'})


@app.exception_handler(db.ReglaNoCumplida)
async def regla_no_cumplida(request: Request, error: db.ReglaNoCumplida):
    return JSONResponse(status_code=409, content={'detail': str(error)})


def paginado(filas, total, pagina, por_pagina):
    return {'items': filas, 'total': total, 'pagina': pagina, 'por_pagina': por_pagina}


# Parametros de paginacion que comparten todos los listados
PAGINA = Query(1, ge=1)
POR_PAGINA = Query(20, ge=1, le=100)


# =============================================================================
# Modelos de los pedidos. Solo definen la forma del JSON (que campos y de que
# tipo). Las reglas (precio > 0, suma de 100, stock...) las controla la base.
# =============================================================================

class Corte(BaseModel):
    id_cepa: int
    porcentaje: Decimal


class VinoDatos(BaseModel):
    nombre: str
    tipo: str
    anada: int
    volumen_ml: int
    graduacion: Decimal
    precio: Decimal
    cuit_bodega: str
    composicion: list[Corte]
    maridajes: list[int] = []


class ClienteNuevo(BaseModel):
    nombre_razon_social: str
    tipo_documento: str
    nro_documento: str
    direccion: str
    id_localidad: int
    tipo_cliente: str
    zona_cobertura: str | None = None       # solo distribuidor
    nro_habilitacion: str | None = None     # solo distribuidor
    pais_destino: str | None = None         # solo exportador


class ClienteCambios(BaseModel):
    nombre_razon_social: str
    tipo_documento: str
    nro_documento: str
    direccion: str
    id_localidad: int
    descuento: Decimal | None = None
    zona_cobertura: str | None = None
    nro_habilitacion: str | None = None
    pais_destino: str | None = None


class Renglon(BaseModel):
    cod_vino: int
    cantidad: int


class VentaNueva(BaseModel):
    id_cliente: int
    id_sala: int
    # Al menos un renglon: un comprobante vacio no es una venta
    renglones: list[Renglon] = Field(min_length=1)


class TransferenciaNueva(BaseModel):
    id_sala: int


class IngresoNuevo(BaseModel):
    cod_transporte: int
    cuit_bodega: str


# =============================================================================
# Rutas
# =============================================================================

@app.get('/salud', tags=['Salud'])
def salud():
    """Verifica que la API llega a la base y con que usuario se conecta."""
    return db.salud()


@app.get('/catalogos', tags=['Salud'])
def catalogos():
    """Cepas, bodegas, salas, etc., para los desplegables del front."""
    return db.catalogos()


# ---- Vinos -------------------------------------------------------------------

@app.get('/vinos', tags=['Vinos'])
def listar_vinos(tipo: str | None = None, cepa: int | None = None,
                 bodega: str | None = None, anada: int | None = None,
                 nombre: str | None = None,
                 pagina: int = PAGINA, por_pagina: int = POR_PAGINA):
    """Catalogo con filtros (tipo, id de cepa, CUIT de bodega, aniada y parte
    del nombre) y paginacion."""
    filtros = {'tipo': tipo, 'cepa': cepa, 'bodega': bodega, 'anada': anada, 'nombre': nombre}
    filas, total = db.listar_vinos(filtros, por_pagina, (pagina - 1) * por_pagina)
    return paginado(filas, total, pagina, por_pagina)


@app.get('/vinos/{cod}', tags=['Vinos'])
def obtener_vino(cod: int):
    """Ficha: datos, bodega, cepas con porcentajes, maridajes y stock."""
    return db.obtener_vino(cod)


@app.post('/vinos', status_code=201, tags=['Vinos'])
def crear_vino(vino: VinoDatos):
    """Alta con composicion y maridajes, en una sola transaccion."""
    return db.crear_vino(vino.model_dump())


@app.put('/vinos/{cod}', tags=['Vinos'])
def actualizar_vino(cod: int, vino: VinoDatos):
    """Modificacion. Un cambio de precio queda en la auditoria (trigger T6)."""
    return db.actualizar_vino(cod, vino.model_dump())


@app.delete('/vinos/{cod}', status_code=204, tags=['Vinos'])
def borrar_vino(cod: int):
    db.borrar_vino(cod)


@app.get('/vinos/{cod}/precios', tags=['Vinos'])
def historial_precios(cod: int):
    """Cambios de precio registrados por el trigger T6 (RN-13)."""
    return db.historial_precios(cod)


# ---- Clientes ----------------------------------------------------------------

@app.get('/clientes', tags=['Clientes'])
def listar_clientes(tipo: str | None = None, nombre: str | None = None,
                    pagina: int = PAGINA, por_pagina: int = POR_PAGINA):
    filas, total = db.listar_clientes(tipo, nombre, por_pagina, (pagina - 1) * por_pagina)
    return paginado(filas, total, pagina, por_pagina)


@app.get('/clientes/{id_cliente}', tags=['Clientes'])
def obtener_cliente(id_cliente: int):
    return db.obtener_cliente(id_cliente)


@app.post('/clientes', status_code=201, tags=['Clientes'])
def crear_cliente(cliente: ClienteNuevo):
    """Alta del cliente y su subtipo juntos. El descuento lo pone la base (T8)."""
    return db.crear_cliente(cliente.model_dump())


@app.put('/clientes/{id_cliente}', tags=['Clientes'])
def actualizar_cliente(id_cliente: int, cliente: ClienteCambios):
    return db.actualizar_cliente(id_cliente, cliente.model_dump())


@app.delete('/clientes/{id_cliente}', status_code=204, tags=['Clientes'])
def borrar_cliente(id_cliente: int):
    db.borrar_cliente(id_cliente)


# ---- Ventas ------------------------------------------------------------------

@app.post('/comprobantes', status_code=201, tags=['Ventas'])
def crear_comprobante(venta: VentaNueva):
    """Venta completa en una transaccion. Los importes y el stock los calculan
    los triggers T1 y T2. Sin stock: 409 y no queda nada guardado."""
    return db.crear_comprobante(venta.id_cliente, venta.id_sala,
                                [r.model_dump() for r in venta.renglones])


@app.get('/comprobantes/{nro}', tags=['Ventas'])
def obtener_comprobante(nro: int):
    return db.obtener_comprobante(nro)


@app.get('/salas/{id_sala}/stock', tags=['Ventas'])
def stock_de_sala(id_sala: int):
    """Vinos con stock en la sala, para elegir que vender."""
    return db.stock_de_sala(id_sala)


@app.get('/deposito/stock', tags=['Transferencias'])
def stock_de_deposito():
    """Vinos con stock en el deposito central, para armar transferencias."""
    return db.stock_de_deposito()


# ---- Transferencias ----------------------------------------------------------

@app.get('/transferencias', tags=['Transferencias'])
def listar_transferencias(sala: int | None = None, estado: str | None = None,
                          pagina: int = PAGINA,
                          por_pagina: int = POR_PAGINA):
    filas, total = db.listar_transferencias(sala, estado, por_pagina, (pagina - 1) * por_pagina)
    return paginado(filas, total, pagina, por_pagina)


@app.get('/transferencias/{nro}', tags=['Transferencias'])
def obtener_transferencia(nro: int):
    return db.obtener_transferencia(nro)


@app.post('/transferencias', status_code=201, tags=['Transferencias'])
def crear_transferencia(datos: TransferenciaNueva):
    """Nace en confeccion, con la fecha de hoy (la pone el trigger T5)."""
    return db.crear_transferencia(datos.id_sala)


@app.post('/transferencias/{nro}/renglones', status_code=201, tags=['Transferencias'])
def agregar_renglon_transferencia(nro: int, renglon: Renglon):
    """Solo mientras esta en confeccion (RN-12, trigger T4)."""
    return db.agregar_renglon_transferencia(nro, renglon.cod_vino, renglon.cantidad)


@app.post('/transferencias/{nro}/terminar', tags=['Transferencias'])
def terminar_transferencia(nro: int):
    return db.terminar_transferencia(nro)


@app.post('/transferencias/{nro}/procesar', tags=['Transferencias'])
def procesar_transferencia(nro: int):
    """Llama al procedimiento sp_procesar_transferencia."""
    return db.procesar_transferencia(nro)


# ---- Ingresos ----------------------------------------------------------------

@app.get('/ingresos', tags=['Ingresos'])
def listar_ingresos(estado: str | None = None,
                    pagina: int = PAGINA,
                    por_pagina: int = POR_PAGINA):
    filas, total = db.listar_ingresos(estado, por_pagina, (pagina - 1) * por_pagina)
    return paginado(filas, total, pagina, por_pagina)


@app.get('/ingresos/{cod}', tags=['Ingresos'])
def obtener_ingreso(cod: int):
    return db.obtener_ingreso(cod)


@app.post('/ingresos', status_code=201, tags=['Ingresos'])
def crear_ingreso(datos: IngresoNuevo):
    return db.crear_ingreso(datos.cod_transporte, datos.cuit_bodega)


@app.post('/ingresos/{cod}/renglones', status_code=201, tags=['Ingresos'])
def agregar_renglon_ingreso(cod: int, renglon: Renglon):
    return db.agregar_renglon_ingreso(cod, renglon.cod_vino, renglon.cantidad)


@app.post('/ingresos/{cod}/terminar', tags=['Ingresos'])
def terminar_ingreso(cod: int):
    return db.terminar_ingreso(cod)


@app.post('/ingresos/{cod}/procesar', tags=['Ingresos'])
def procesar_ingreso(cod: int):
    """Llama al procedimiento sp_procesar_ingreso."""
    return db.procesar_ingreso(cod)


# ---- Reportes (consultas de la seccion 8) ------------------------------------

@app.get('/reportes/top-vinos', tags=['Reportes'])
def top_vinos():
    """S1: los 10 vinos mas vendidos."""
    return db.top_vinos()


@app.get('/reportes/ventas-por-sala', tags=['Reportes'])
def ventas_por_sala():
    """S8: ventas por sala en el ultimo trimestre."""
    return db.ventas_por_sala()


@app.get('/reportes/vinos-sin-stock', tags=['Reportes'])
def vinos_sin_stock(sala: int):
    """S6: vinos sin stock en la sala pero con stock en el deposito."""
    return db.vinos_sin_stock(sala)


@app.get('/reportes/transportista-activo', tags=['Reportes'])
def transportista_activo():
    """S7: el transportista con mas ingresos en el ultimo mes."""
    return db.transportista_activo()


@app.get('/reportes/trazabilidad/{cod}', tags=['Reportes'])
def trazabilidad(cod: int):
    """Ficha del vino (S9) y sus ingresos, transferencias y ventas."""
    return db.trazabilidad(cod)
