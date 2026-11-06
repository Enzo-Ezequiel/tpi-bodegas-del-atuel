# Carga de datos (etapa 3)

Script: [`db/seed/cargar.py`](../db/seed/cargar.py). Catálogos reales en
`db/seed/catalogos/`. Controles en [`db/seed/control.sql`](../db/seed/control.sql).

## 1. Cómo correr la carga

Los pasos completos están en [`db/seed/README.md`](../db/seed/README.md). En resumen:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r db\seed\requirements.txt
# base vacía: .\scripts\recrear_bd.ps1  (local)  o  docker compose down -v; docker compose up -d
$env:PGHOST='localhost'; $env:PGPORT='5432'; $env:PGUSER='postgres'
$env:PGPASSWORD='...'; $env:PGDATABASE='bodegas_atuel'      # PGPORT 5433 con Docker
.\.venv\Scripts\python.exe db\seed\cargar.py --chico     # o sin --chico para el volumen completo
```

## 2. Orden de carga

Primero las tablas que no dependen de nadie y después las que las referencian:
una fila solo se puede insertar si ya existe la fila a la que apunta su clave foránea.

1. `departamento`, `localidad`, `cepa`, `maridaje`: catálogos sin claves foráneas.
2. `bodega`: no depende de nadie; la usan lotes, vinos e ingresos.
3. `transportista` y `transportista_localidad`: la cobertura necesita al transportista y a la localidad.
4. `sala_venta`: depende de `localidad`.
5. `empleado`: depende de `sala_venta`.
6. `finca` y `parcela`: la finca depende de `departamento`; la parcela es débil de la finca y usa una `cepa`.
7. `lote_uva` y `analisis_calidad`: el lote necesita la parcela y la bodega; el análisis, el lote.
8. `vino`, `composicion` y `vino_maridaje`: el vino depende de `bodega`; las intermedias, del vino, la cepa y el maridaje.
9. `cliente`, `socio`, `distribuidor`, `exportador` y `permiso_exportacion`: primero el supertipo, después cada subtipo y al final los permisos del exportador.
10. `ingreso` y `renglon_ingreso` *(triggers apagados)*.
11. `transferencia` y `renglon_transferencia` *(triggers apagados)*.
12. `comprobante` y `renglon_comprobante` *(triggers apagados)*, ordenados por fecha. Después se calculan los importes en SQL.
13. `stock_deposito` y `stock_sala`: foto actual del día de referencia.
14. Se rehabilitan los triggers y se sube 5 % el precio de 20 vinos. Las filas de `auditoria_precio` las escribe el trigger T6.

Los códigos autogenerados (`id_localidad`, `cod_vino`, `nro`…) los asigna el
script desde 1. Así sabe qué número tiene cada fila sin leerlo de vuelta. Se
insertan con `OVERRIDING SYSTEM VALUE` y al terminar cada tabla se corre
`ALTER TABLE … ALTER COLUMN … RESTART WITH (máximo + 1)`, para que la base siga
numerando bien.

Todo corre en **una sola transacción**: si algo falla, psycopg hace `ROLLBACK` y
la base queda vacía. Cada tabla se inserta con un único `executemany` y
parámetros `%s` (nunca SQL armado concatenando valores).

## 3. Triggers durante la carga

Los triggers están pensados para el uso diario y molestan para cargar historia:

| Tabla | Trigger | Por qué molesta |
|---|---|---|
| `transferencia` | `trg_transferencia_fecha` | Pisa la fecha con la de hoy: todas las transferencias quedarían con la misma fecha |
| `renglon_ingreso`, `renglon_transferencia` | `trg_renglon_*_bloqueo` | Rechazan renglones de documentos ya procesados, y la historia está casi toda procesada |
| `renglon_comprobante` | `trg_renglon_venta_validar` y `_actualizar` | Validan y descuentan un stock que todavía no existe |
| `ingreso`, `transferencia` | `trg_*_estado` | Son de UPDATE: no molestan, pero se apagan junto con su tabla |

Por eso, antes de cargar ingresos, transferencias y ventas se corre
`ALTER TABLE x DISABLE TRIGGER USER` en esas cinco tablas. `USER` apaga solo los
triggers escritos por nosotros: las claves foráneas siguen controlando. Los
`ENABLE TRIGGER USER` van en un `finally`. Si la transacción falló, el
`ROLLBACK` deshace también el `DISABLE`, porque en PostgreSQL el `ALTER TABLE`
es transaccional.

Quedan **activos** los de `cliente` (pone el descuento según el tipo),
`composicion` (no deja pasar de 100) y `vino` (audita los cambios de precio).

**Riesgo:** mientras están apagados, la base no controla esas reglas. Si el
generador tuviera un error, por ejemplo un total mal calculado, entraría igual.

**Cómo se cubre:**
- Los importes se calculan en SQL con la misma fórmula que `trg_renglon_venta_validar`.
- Al final se corren los controles de `control.sql`. El 3 compara cada total con
  `fn_total_comprobante`, la misma función que usa el trigger. El 2 confirma que
  no hay stock negativo.

## 4. Semilla y fecha de referencia

- **Semilla fija:** `random.seed(2026)` y `Faker.seed(2026)` (Faker en `es_AR`).
- **Fecha de referencia** (`--fecha-referencia`, por defecto hoy): todas las fechas
  se generan relativas a ella («los últimos 7 días», «hace más de 5 años»).
- **Reproducible** quiere decir: misma semilla **y** misma fecha de referencia dan
  exactamente los mismos datos. Lo verificamos con dos cargas sobre bases nuevas:
  dieron el mismo `md5` en `comprobante`, `cliente` y `renglon_comprobante`.
- **Por qué la fecha es relativa:** las consultas usan `CURRENT_DATE` (S3 «la
  última semana», D1 «más de 5 años»…). Si las fechas fueran fijas, con el paso
  del tiempo las consultas dejarían de encontrar filas. Basta con recargar con la
  fecha del día.

## 5. Volúmenes

Carga completa del 06/11/2026 (fecha de referencia 2026-11-06):

| Tabla | Filas | | Tabla | Filas |
|---|---:|---|---|---:|
| renglon_comprobante | 125.135 | | vino_maridaje | 1.008 |
| comprobante | 50.000 | | composicion | 980 |
| cliente | 12.000 | | stock_deposito | 500 |
| renglon_transferencia | 11.992 | | vino | 500 |
| stock_sala | 9.000 | | parcela | 400 |
| socio | 8.400 | | empleado | 300 |
| renglon_ingreso | 7.267 | | transportista_localidad | 79 |
| permiso_exportacion | 4.488 | | finca | 40 |
| transferencia | 4.000 | | sala_venta | 30 |
| analisis_calidad | 3.621 | | auditoria_precio | 20 |
| ingreso | 2.500 | | departamento | 18 |
| distribuidor | 2.400 | | localidad | 18 |
| lote_uva | 1.804 | | cepa | 15 |
| exportador | 1.200 | | transportista | 15 |
| | | | bodega | 10 |
| | | | maridaje | 8 |

Todas las tablas tienen filas, cuatro superan las 10.000 y una las 100.000. El
modo `--chico` carga lo mismo en pequeño (60 clientes, 150 comprobantes,
369 renglones).

## 6. Tiempos

Carga completa en Docker (PostgreSQL 18) sobre Windows 11: **38,9 s en total**.
Tiempo de inserción de cada tabla, en el orden de carga, como lo imprime el script:

| Tabla | Filas | Segundos |
|---|---:|---:|
| departamento | 18 | 0,05 |
| localidad | 18 | 0,05 |
| cepa | 15 | 0,05 |
| maridaje | 8 | 0,05 |
| bodega | 10 | 0,05 |
| transportista | 15 | 0,05 |
| transportista_localidad | 79 | 0,06 |
| sala_venta | 30 | 0,05 |
| empleado | 300 | 0,07 |
| finca | 40 | 0,05 |
| parcela | 400 | 0,07 |
| lote_uva | 1.804 | 0,25 |
| analisis_calidad | 3.621 | 0,55 |
| vino | 500 | 0,11 |
| composicion | 980 | 0,21 |
| vino_maridaje | 1.008 | 0,09 |
| cliente | 12.000 | 1,31 |
| socio | 8.400 | 0,70 |
| distribuidor | 2.400 | 0,26 |
| exportador | 1.200 | 0,14 |
| permiso_exportacion | 4.488 | 0,40 |
| ingreso | 2.500 | 0,24 |
| renglon_ingreso | 7.267 | 0,66 |
| transferencia | 4.000 | 0,44 |
| renglon_transferencia | 11.992 | 0,99 |
| comprobante | 50.000 | 4,89 |
| renglon_comprobante | 125.135 | 12,28 |
| *(importes de ventas: dos `UPDATE` masivos)* | 50.000 | 7,99 |
| stock_deposito | 500 | 0,08 |
| stock_sala | 9.000 | 0,80 |
| auditoria_precio (aumento de 20 precios) | 20 | 0,05 |

El resto del total (unos 6 s) es la generación de los datos en Python: sorteos,
nombres y direcciones con Faker. Las tablas chicas tardan siempre unos 0,05 s:
es el costo fijo de cada viaje a la base. El modo `--chico` tarda 1,7 s.

**Medición (`--medir`):** 5.000 filas en una tabla temporal con las columnas de `renglon_comprobante`.

| Forma | Segundos |
|---|---:|
| Un `execute` por fila | 9,71 |
| `executemany` | 0,38 |

`executemany` fue unas 25 veces más rápido. Con un `execute` por fila, cada fila
es un viaje de ida y vuelta a la base. `executemany` (en psycopg 3, en modo
*pipeline*) manda las filas seguidas sin esperar cada respuesta.

**Volcado:** con la carga completa se generó `dump_completo.dump` (formato
custom, `-Fc`, 2,9 MB, con las 30 tablas). No se sube: `*.dump` está en el
`.gitignore`. El volcado ya trae el esquema y los datos: para recrear la base sin
correr el script, se crea una base nueva con `CREATE DATABASE` (sin correr las
migraciones) y se ejecuta `pg_restore -U postgres -d bodegas_atuel dump_completo.dump`.

```powershell
# PostgreSQL local
& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -U postgres -d bodegas_atuel -Fc -f dump_completo.dump
# Docker (se genera adentro del contenedor y se copia, para que PowerShell no altere el binario)
docker compose exec -T db pg_dump -U postgres -d bodegas_atuel -Fc -f /tmp/dump_completo.dump
docker cp tpi-bodegas-del-atuel-db-1:/tmp/dump_completo.dump .\dump_completo.dump
```

## 7. Resultado de los controles

Con la carga completa y con la chica, todos dan 0:

| Control | Resultado |
|---|---:|
| 2. Filas con stock negativo (`stock_sala` / `stock_deposito`) | 0 / 0 |
| 3. Comprobantes con `total` distinto de `fn_total_comprobante(nro)` | 0 |
| 4. Comprobantes sin renglones | 0 |
| 5. Vinos con la composición incompleta | 0 |
| 6. Clientes sin fila en su subtipo | 0 |
| 7. Lotes con `campania` distinta del año de `fecha_cosecha` | 0 |

Además se verificaron los casos que usan las consultas de la etapa 5, en los dos
modos, y se cumplen todos: el «Malbec Reserva» vendido en todas las salas (S2) y
pedido por 5 salas en los últimos 15 días con cantidades distintas (S4), un
cliente con los 3 vinos de «Bodega Los Tres Vinos» (S12), exactamente 3 cepas
sin uso (D2), socios sin compras viejos (D4) y de San Rafael (D6), etc.

## Decisiones extra

Lo que la especificación no resolvía, resuelto con la opción más simple:

1. **`--medir` corre solo:** no carga datos ni exige la base vacía. Usa una tabla
   temporal (`CREATE TEMP TABLE … (LIKE renglon_comprobante)`) y termina con
   `ROLLBACK`, así que no toca nada.
2. **S4 en modo chico:** hay 4 salas, así que «al menos 5 salas» no se puede.
   Piden el «Malbec Reserva» todas las salas.
3. **Las 12 cepas en uso se usan todas:** las primeras parcelas recorren las 12
   cepas. Si hay pocas parcelas (modo chico), los primeros vinos al azar usan como
   principal las que faltan. Así D2 encuentra solo las 3 «sin usar».
4. **Antigüedades con margen:** 35 % de los empleados con 6 años o más y 15 %
   con entre 1 y 18 meses. Los dos de San Rafael son de este grupo. El margen hace
   que U2 y D3 sigan encontrando filas aunque las consultas se corran unos meses
   después de la carga. «Ref − 1 mes» se tomó como 30 días.
5. **Socios sin compras:** son el máximo entre el 6 % de los socios y 20 + 10
   (chico 3 + 2). Los dos grupos forzados (alta de hace más de 5 años y 90 días,
   y San Rafael) son disjuntos.
6. **Los 3 «Malbec Reserva»** son 100 % Malbec, de la misma bodega (una
   distinta de «Bodega Los Tres Vinos»). Son los `cod_vino` 1, 2 y 3; el que
   buscan las consultas (750 ml, Ref − 4) es el 1. Los de «Bodega Los Tres Vinos»
   son el 4, el 5 y el 6, y esa bodega es la última que se carga.
7. **Composición:** las cepas secundarias son del mismo color que la principal y
   los porcentajes van de 5 en 5 (100; 85/15; 70/20/10…).
8. **Transferencias:** las de los últimos 15 días que se generan al azar no
   incluyen el «Malbec Reserva», para no alterar las cantidades distintas de S4.
   Las 2 salas sin pendientes (S5) se eligen al azar sin contar la sala 1, y sus
   transferencias recientes quedan `procesado`.
9. **Ingresos:** se fuerzan 3 en los últimos 30 días con transportistas
   distintos, así hay ingresos en los 3 estados y 3 transportistas en el
   trimestre (I1, S7). La bodega de cada ingreso se elige entre las que tienen
   vinos.
10. **Stock:** el «Malbec Reserva» tiene entre 200 y 2.000 botellas en el
    depósito. En la sala 1 se carga el 60 % de los vinos, pero siempre le faltan
    al menos 5, que tienen stock en el depósito (S6).
11. **Fechas:** los análisis de calidad no pasan de la fecha de referencia. Los
    vencimientos de los permisos son la emisión más 1 a 3 años exactos.
12. **Nombres generados:** los distribuidores son «Apellido Distribuciones S.A.»,
    los exportadores «Apellido Export S.R.L.» y los transportistas «Transportes
    Apellido S.A.». El email y el teléfono del transportista siguen un patrón fijo
    (`logistica@…com.ar`, `0261 4xxxxxx`).
13. **Aumento de precios:** `ROUND(precio * 1.05, 2)`, con un `UPDATE` por vino.
14. **Controles:** se corren después del `COMMIT`, en modo solo lectura.
