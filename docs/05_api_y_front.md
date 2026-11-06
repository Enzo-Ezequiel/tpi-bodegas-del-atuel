# Etapas 6 y 7 — API y front

La API (`api/`) y el front (`front/`) son el medio para mostrar que la base funciona dentro de un sistema. **No tienen reglas de negocio propias:** los totales, descuentos, stock y cambios de estado los resuelven los triggers, funciones y procedimientos de la base. La API los llama y devuelve lo que la base responde; el front muestra eso.

## 1. Arquitectura

```
Navegador (front/, HTML + JS)  --fetch JSON-->  API (FastAPI)  --SQL parametrizado-->  PostgreSQL
                                                  main.py: rutas                       triggers, funciones,
                                                  db.py:   una función por consulta    procedimientos, vistas
```

| Pieza | Qué hace | Por qué así |
|---|---|---|
| `api/db.py` | Todo el SQL de la API, una función por consulta | El SQL no queda desparramado por las rutas, y se lee de corrido para el oral |
| `api/main.py` | Rutas, modelos del JSON y traducción de errores | Las rutas solo reciben el pedido, llaman a `db.py` y devuelven el resultado |
| Pool de conexiones (`psycopg_pool`) | Mantiene unas pocas conexiones abiertas y las reutiliza | Abrir una conexión por pedido es lento |
| Rol `bodegas_api` | Usuario con el que se conecta la API | Lee y escribe datos, pero no crea ni borra tablas ni modifica la auditoría (`007_roles.sql`) |
| `front/js/api.js` | Todas las llamadas a la API pasan por ahí; la URL base está en `front/js/config.js` | Si la API cambia de lugar, se toca una sola línea |

## 2. Consultas parametrizadas e inyección SQL

Todos los datos del usuario van como parámetros (`%(nombre)s`). psycopg manda el texto SQL y los valores **por separado**, así que un valor nunca se interpreta como SQL.

Los filtros opcionales del catálogo no arman el SQL pegando pedazos: cada condición es `(%(tipo)s IS NULL OR v.tipo = %(tipo)s)`. Si el filtro no viene, el parámetro es NULL y la condición da verdadero.

**Demostración (prueba `test_inyeccion_sql_no_funciona`):**

```
GET /vinos?nombre=' OR 1=1 --
→ 200, {"items": [], "total": 0}
```

Si el texto se pegara dentro del SQL, quedaría `WHERE v.nombre ILIKE '%' OR 1=1 --%'` y traería todos los vinos. Como va como parámetro, la base busca un vino cuyo nombre contenga literalmente `' OR 1=1 --`, y no hay ninguno.

## 3. Transacciones

Cuando una operación tiene más de una sentencia, va dentro de `with conn.transaction():`. psycopg ejecuta `BEGIN` al entrar, `COMMIT` si todo salió bien y `ROLLBACK` si hubo cualquier error.

| Operación | Sentencias | Si algo falla |
|---|---|---|
| `POST /comprobantes` | Cabecera + un INSERT por renglón (T1 valida stock, T2 descuenta y recalcula) | Un renglón sin stock deshace también la cabecera y los renglones anteriores |
| `POST /vinos`, `PUT /vinos/{cod}` | Vino + composición + maridajes + consulta a `v_vinos_composicion_incompleta` | Si los porcentajes no suman 100, no queda ni el vino |
| `POST /clientes` | Cliente + su fila de subtipo | Un cliente nunca queda sin subtipo (límite de `docs/03`, sección 7) |

Procesar un ingreso o una transferencia es un solo `CALL` al procedimiento: ya es todo o nada dentro de la base.

**RN-05 en la API.** La base solo impide que los porcentajes pasen de 100 (trigger T7), porque las cepas se cargan de a una fila. Que lleguen a 100 se controla al final de la transacción: la API pregunta a la vista `v_vinos_composicion_incompleta` y, si el vino aparece, lanza el error y se hace `ROLLBACK`. El cálculo de la suma lo hace la vista, no la API.

## 4. Traducción de errores

La API devuelve el mensaje de la base tal cual, con el código SQLSTATE y la restricción que falló. El front lo muestra sin cambiarlo.

| SQLSTATE | Qué pasó | HTTP |
|---|---|---|
| `23505` | UNIQUE o PK repetida | 409 |
| `23503` | Clave foránea: el dato relacionado no existe | 409 |
| `23001` | Clave foránea con `ON DELETE RESTRICT`: tiene filas que dependen de él | 409 |
| `23514` | CHECK (por ejemplo, precio ≤ 0) | 422 |
| `23502` | NOT NULL (por ejemplo, distribuidor sin zona) | 422 |
| `P0001` | `RAISE EXCEPTION` de un trigger o procedimiento (stock insuficiente, estado no permitido…) | 409 |
| `22P02` | Texto con formato inválido para el tipo (por ejemplo, un tipo de vino que no está en el ENUM) | 400 |
| `22001`, `22003` | Texto demasiado largo, número fuera de rango | 422 |
| `40001`, `40P01` | Conflicto de concurrencia | 503 |

El `23001` no está en la tabla del enunciado: PostgreSQL lo usa en vez del `23503` cuando la FK es `RESTRICT` (las nuestras lo son, `docs/03`, sección 5). Apareció al probar el borrado de un vino con historial de precios.

Ejemplo de respuesta (venta sin stock):

```json
{
  "detail": "Stock insuficiente del vino 2 en la sala 1: hay 56, se piden 99999 (RN-09)",
  "sqlstate": "P0001",
  "restriccion": null
}
```

## 5. Endpoints

La documentación interactiva (Swagger) está en `http://localhost:8000/docs` y la genera FastAPI con las rutas reales.

| Recurso | Rutas | Qué hace en la base |
|---|---|---|
| Salud | `GET /salud`, `GET /catalogos` | Usuario conectado; listas para los desplegables |
| Vinos | `GET /vinos` (filtros `tipo`, `cepa`, `bodega`, `anada`, `nombre`; `pagina`, `por_pagina`), `GET /vinos/{cod}`, `POST`, `PUT`, `DELETE`, `GET /vinos/{cod}/precios` | El PUT con otro precio dispara T6 (auditoría). El DELETE con movimientos lo frena la FK |
| Clientes | `GET /clientes`, `GET /clientes/{id}`, `POST`, `PUT`, `DELETE` | El descuento inicial lo pone T8. El tipo no se cambia |
| Ventas | `POST /comprobantes`, `GET /comprobantes/{nro}`, `GET /salas/{id}/stock` | T1 y T2 calculan importes y stock |
| Transferencias | `GET /transferencias`, `GET /transferencias/{nro}`, `POST /transferencias`, `POST …/{nro}/renglones`, `…/terminar`, `…/procesar` | T5 pone la fecha, T4 bloquea renglones, T3 controla los estados, `sp_procesar_transferencia` mueve el stock |
| Ingresos | Las mismas rutas en `/ingresos` | Igual, con `sp_procesar_ingreso` |
| Depósito | `GET /deposito/stock` | Vinos con stock para armar transferencias |
| Reportes | `/reportes/top-vinos` (S1), `/ventas-por-sala` (S8), `/vinos-sin-stock?sala=` (S6), `/transportista-activo` (S7), `/trazabilidad/{cod}` | La trazabilidad es la ficha del vino (S9) más sus ingresos, transferencias y ventas |

**Decisión:** `POST /ingresos/{cod}/terminar` no está en la lista del enunciado, pero hace falta: el procedimiento solo procesa ingresos terminados.

## 6. Pruebas automáticas

`api/tests/test_api.py`: 16 pruebas con pytest contra la base real. Siete provocan a propósito que la base rechace algo y verifican el código HTTP y que no haya quedado nada guardado:

| Prueba | Regla | Espera |
|---|---|---|
| `test_regla_precio_negativo` | RN-01, CHECK | 422 y el vino no existe |
| `test_regla_composicion_que_no_suma_100` | RN-05 | 409 y el vino no existe |
| `test_regla_venta_sin_stock` | RN-09, trigger T1 | 409 y el stock no cambió |
| `test_regla_estados_de_la_transferencia` | RN-11 y RN-12 | 409 al procesar sin terminar y al agregar renglones después |
| `test_cambio_de_precio_queda_auditado` | RN-13 y RN-14 | La fila de auditoría con usuario `bodegas_api`; 409 al borrar el vino |
| `test_cliente_con_subtipo` | NOT NULL del subtipo | 422 y el cliente no existe |
| `test_tipo_invalido_da_400` | ENUM | 400 |

Las demás verifican la conexión con el rol de la API, la paginación, los filtros, la inyección SQL, la ficha, el 404, el alta y baja de un vino y una venta correcta (el total devuelto coincide con sus renglones y el stock baja).

Se corren sobre la carga chica (algunas dejan datos: una venta de 1 botella, una transferencia terminada y un vino con historial de precios):

```powershell
cd api
python -m pytest -v
```

## 7. Front

Cinco pantallas en HTML y JavaScript sin framework, servidas como archivos estáticos:

| Pantalla | Archivo | Qué muestra de la base |
|---|---|---|
| Catálogo | `index.html` | Listado paginado con filtros y ficha con composición, maridajes y stock |
| Alta y edición de vino | `vino.html` | El error de RN-05 cuando las cepas no suman 100, y el de los CHECK |
| Nueva venta | `venta.html` | El comprobante con los importes calculados por la base, y el error de stock insuficiente |
| Transferencias | `transferencias.html` | Botones que se habilitan según el estado; los errores de T3 y T4 si se fuerza un paso |
| Tablero | `tablero.html` | S1, S8 en un gráfico de barras, S7 y S6 por sala |

El front **no calcula importes, descuentos ni stock**: la pantalla de venta no muestra ningún precio hasta que la API devuelve el comprobante. Los datos se insertan en la página con `textContent`, nunca como HTML, para que un dato con `<script>` no se ejecute.
