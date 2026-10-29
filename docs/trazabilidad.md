# Etapa 2 — Trazabilidad de las reglas de negocio

Para cada regla del enunciado (sección 4): qué mecanismo de la base la protege, en qué archivo está, por qué se eligió ese mecanismo y qué casos la prueban en `db/tests/db_tests.sql`.

El criterio para elegir el mecanismo es la guía «¿Dónde va cada regla?» del enunciado:

- Si la regla se verifica mirando **una sola fila**, va un `CHECK`, `NOT NULL` o dominio.
- Si exige que **exista otro dato**, va una clave foránea.
- Si exige que algo **no se repita**, va una `UNIQUE` o `PRIMARY KEY`.
- Si **depende de otras filas, de otras tablas o de la fecha actual**, va un trigger.
- Si es una **operación de varios pasos** que tiene que salir toda o nada, va un procedimiento.

## Tabla de trazabilidad

| Regla | Mecanismo | Dónde | Por qué ahí | Casos en `db_tests.sql` |
|---|---|---|---|---|
| **RN-01** Precio único para toda la red y mayor que cero | `precio` es columna de `vino` (no de la sala ni del stock) + `CHECK ck_vino_precio (precio > 0)` | `001`, `002` | Un solo precio por vino es una decisión de diseño: si estuviera en `stock_sala`, cada sala podría tener el suyo. Mayor que cero se ve en una sola fila: CHECK | Funciona: los dos vinos con su precio. Fallan: precio 0 y precio negativo |
| **RN-02** Una sala en una sola localidad; un encargado por localidad | FK `fk_sala_localidad` NOT NULL + `encargado_regional` como columna de `localidad` (3FN) | `001` | La FK obliga a que la localidad exista; al ser una columna, la sala tiene una sola. El encargado depende de la localidad y no de la sala, por eso está ahí y no se repite (`docs/02`, sección 2) | Funciona: las dos salas muestran el encargado de su localidad. Fallan: sala sin localidad y con una localidad que no existe |
| **RN-03** Cada empleado trabaja en una sola sala | FK `fk_empleado_sala` NOT NULL + PK `cuit` | `001` | Una columna admite un solo valor; la PK impide cargar al mismo empleado otra vez con otra sala | Funciona: empleado en la sala 1. Fallan: empleado sin sala y el mismo CUIT en la sala 2 |
| **RN-04** Una parcela tiene una sola cepa y se cosecha como máximo una vez por campaña | FK `fk_parcela_cepa` NOT NULL + PK `(id_finca, nro_parcela)` + `UNIQUE uq_lote_parcela_campania` | `001`, `002` | La cepa es una columna de la parcela, así que hay una sola. «Una cosecha por campaña» es una regla de unicidad: UNIQUE | Funcionan: cosechas 2025 y 2026 de la misma parcela. Fallan: segunda cosecha en 2025 y la misma parcela con otra cepa |
| **RN-05** Los porcentajes de corte suman exactamente 100 | Trigger T7 `trg_composicion_suma` (no deja pasar de 100) + vista `v_vinos_composicion_incompleta` | `005`, `006` | Depende de otras filas (las demás cepas del vino): trigger. Ver diferencias más abajo | Funciona: 85 % + 15 %. Falla: subir a 20 % (suma 105). Límite: un vino con 60 % se acepta y aparece en la vista |
| **RN-06** Descuento según el tipo: socio 10 %, distribuidor 20 %, exportador 30 % | Trigger T8 `trg_cliente_descuento` que llama a `fn_descuento_cliente` + dominio `porcentaje_dom` (0 a 100) | `001`, `003`, `005` | Un DEFAULT no puede leer otra columna (`tipo_cliente`), por eso el valor inicial lo pone un trigger. El rango se verifica en una sola fila: CHECK del dominio | Funcionan: los tres tipos reciben 10, 20 y 30; un exportador con 35 % cargado se respeta (U6). Falla: descuento de 150 % |
| **RN-07** Un exportador tiene varios permisos; vencimiento posterior a la emisión | Tabla `permiso_exportacion` con FK a `exportador` + `CHECK ck_permiso_fechas` | `001`, `002` | Varios permisos por exportador es una relación 1:N: tabla aparte. La FK apunta a `exportador` y no a `cliente`, así que solo los exportadores tienen permisos. Las fechas se comparan en la misma fila: CHECK entre columnas | Funciona: exportador con dos permisos. Fallan: vence antes de emitirse y permiso para un socio |
| **RN-08** El total es la suma de los renglones con el descuento aplicado; no se carga a mano | Trigger T1 `trg_renglon_venta_validar` (completa precio, descuento y subtotal del renglón) + trigger T2 `trg_renglon_venta_actualizar` (recalcula la cabecera) + `fn_total_comprobante` + DEFAULT 0 | `002`, `003`, `005` | Depende de otras filas (todos los renglones del comprobante): trigger. La función escribe el cálculo una sola vez y la usan el trigger y la consulta U1 | Funciona: venta al socio con dos renglones, total 34.200, igual a `fn_total_comprobante`. Caso a mano: precio y subtotal cargados a mano se reemplazan por los correctos |
| **RN-09** No se vende más de lo que hay en la sala; el stock nunca es negativo | Trigger T1 (BEFORE INSERT, usa `fn_stock_sala`) + trigger T2 (descuenta) + `CHECK ck_stock_sala_cantidad` y `ck_stock_deposito_cantidad` (`>= 0`) | `002`, `003`, `005` | Comparar con el stock mira otra tabla: trigger BEFORE, que rechaza antes de guardar. El CHECK es la última barrera si algo se escapa | Funciona: las ventas descuentan el stock (10 → 7). Fallan: vender 50 cuando hay 7, vender en una sala sin ese vino y dejar el stock en −1. Además se verifica que la venta rechazada no cambió nada |
| **RN-10** Solo un ingreso terminado impacta en el depósito; estados sin retroceso | ENUM `estado_documento` + DEFAULT `en_confeccion` + trigger T3 `trg_ingreso_estado` + procedimiento `sp_procesar_ingreso` | `001`, `002`, `004`, `005` | El ENUM limita los valores posibles. Que el cambio sea hacia adelante compara el estado viejo con el nuevo: trigger. Procesar son varios pasos (validar, sumar stock, cambiar estado) que salen todos o ninguno: procedimiento | Funciona: nace en confección; terminar y procesar suma 100 y 50 al depósito. Fallan: procesar en confección, saltear un estado, un estado inexistente, retroceder y procesar dos veces |
| **RN-11** Igual que RN-10 para transferencias; la fecha de confección es la actual y no se modifica | Trigger T3 `trg_transferencia_estado` + trigger T5 `trg_transferencia_fecha` + procedimiento `sp_procesar_transferencia` | `004`, `005` | La fecha actual no puede ir en un CHECK, porque dejaría de cumplirse al otro día y se rompería al restaurar un backup: trigger. El procedimiento valida el stock del depósito antes de tocar nada | Funcionan: fecha 2020-01-01 reemplazada por la de hoy; transferencia de 30 botellas (depósito 70, sala 37). Fallan: cambiar la fecha, retroceder y transferir 500 cuando hay 50. Además se verifica que la transferencia rechazada no dejó nada a medias |
| **RN-12** Un documento que no está en confección no admite agregar, modificar ni quitar renglones | Trigger T4 `trg_renglon_ingreso_bloqueo` y `trg_renglon_transf_bloqueo` (BEFORE INSERT OR UPDATE OR DELETE) | `005` | El estado está en otra tabla (la cabecera): trigger. BEFORE, para rechazar antes de guardar o borrar | Funcionan: en confección se agrega, modifica y quita; borrar el documento entero borra sus renglones en cascada. Fallan: agregar, modificar y quitar en un ingreso procesado, y agregar en una transferencia procesada |
| **RN-13** Todo cambio de precio queda auditado | Trigger T6 `trg_vino_auditar_precio` (AFTER UPDATE, solo si cambió el precio) + tabla `auditoria_precio` + `REVOKE UPDATE, DELETE` a la API | `001`, `005`, `007` | Escribir en otra tabla después de guardar el cambio: trigger AFTER. El REVOKE impide que la API borre o corrija el historial | Funcionan: dos cambios de precio quedan registrados con el usuario (`postgres` y `bodegas_api`); cambiar la graduación no genera fila. Fallan: la API intenta borrar y modificar la auditoría |
| **RN-14** No se borra un transportista, una bodega ni un vino con movimientos | FK con `ON DELETE RESTRICT` hacia `vino`, `bodega` y `transportista` | `001` | Es integridad referencial: la FK ya sabe si hay filas que apuntan. CASCADE solo donde la fila hija no tiene sentido sola (`docs/03`, sección 5) | Funciona: un vino sin movimientos se borra y su composición se va en cascada. Fallan: borrar el vino, la bodega y el transportista con movimientos |
| **RN-15** Cantidades, superficies, kilos y precios positivos; graduación entre 5 y 20 | `CHECK` `ck_vino_graduacion`, `ck_vino_precio`, `ck_renglon_comprobante_cantidad`, `ck_renglon_ingreso_cantidad`, `ck_renglon_transferencia_cantidad`, `ck_lote_kilos`, `ck_finca_superficie`, `ck_parcela_superficie` | `002` | Todas se verifican mirando una sola fila: CHECK | Funciona: graduación 5 y 20 (los límites). Fallan: graduación 25 y 3, cantidad 0 o negativa en los tres tipos de renglón, kilos negativos, finca y parcela de 0 ha |

## Diferencias con el mecanismo que pide el enunciado

| Regla | El enunciado espera | Lo que hicimos | Por qué |
|---|---|---|---|
| RN-05 | Constraint trigger diferido, que verifica la suma al cerrar la transacción | Trigger común que no deja pasar de 100, más una vista con los vinos que no llegan a 100 | El trigger diferido no lo vimos en clase. Mientras se cargan las cepas de a una, la suma pasa por valores intermedios (85, después 100), así que no se puede exigir 100 en cada fila |
| RN-10, RN-11 | Procedimientos que bloquean las filas con `SELECT … FOR UPDATE` | Procedimientos sin bloqueo | Concurrencia y transacciones son opcionales según el profesor. El `CHECK cantidad >= 0` evita que el stock quede negativo si dos personas procesan lo mismo a la vez |

## Límites

Los límites conocidos están en `docs/03_decisiones_de_diseno.md`, sección 7. Al escribir las pruebas apareció uno más, que todavía no está en esa lista:

- **RN-08: el total del comprobante se puede modificar a mano.** Los triggers recalculan los importes cada vez que se agrega un renglón, pero nada impide un `UPDATE comprobante SET total = …` directo, ni dar de alta un comprobante con un total distinto de 0. Para cerrarlo haría falta un trigger `BEFORE UPDATE` sobre `comprobante` que rechace cambios en los importes que no vengan del trigger T2. Hoy lo cubre que la API no modifique la cabecera.

## Cómo correr las pruebas

Sobre la base creada con las migraciones 001 a 007, desde la raíz del repo.

Con Docker, en PowerShell:

```powershell
Get-Content db\tests\db_tests.sql | docker compose exec -T db psql -U postgres -d bodegas_atuel
```

Con el PostgreSQL local:

```bash
psql -U postgres -d bodegas_atuel -f db/tests/db_tests.sql
```

Antes de cada caso se imprime una línea que dice qué se prueba y si debe funcionar o fallar. Todo corre dentro de `BEGIN … ROLLBACK`, así que la base queda como estaba y el archivo se puede correr las veces que haga falta.

**Resultado (28/10/2026, PostgreSQL 18 en Docker):** los 40 casos que deben fallar fallan, cada uno con el mensaje esperado, y todos los que deben funcionar funcionan.
