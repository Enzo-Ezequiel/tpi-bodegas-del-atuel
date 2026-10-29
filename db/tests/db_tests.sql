-- =============================================================================
-- db_tests.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Pruebas de las reglas de negocio RN-01 a RN-15: para cada regla, casos que
-- deben funcionar y casos que deben fallar. Antes de cada caso, \echo imprime
-- que se prueba y que se espera, asi la salida se lee sola.
-- La tabla regla -> mecanismo -> caso esta en docs/trazabilidad.md.
--
-- Como se corre (sobre la base creada con las migraciones 001 a 007):
--   Con Docker, desde la raiz del repo, en PowerShell:
--     Get-Content db\tests\db_tests.sql | docker compose exec -T db psql -U postgres -d bodegas_atuel
--   Con el PostgreSQL local:
--     psql -U postgres -d bodegas_atuel -f db/tests/db_tests.sql
--
-- La base queda como estaba:
--   - Todo corre dentro de BEGIN ... ROLLBACK, asi que al final se deshace
--     todo lo que se inserto. Se puede correr las veces que haga falta.
--   - ON_ERROR_ROLLBACK hace que un error deshaga solo esa sentencia y no
--     toda la transaccion. Sin esto, el primer caso que debe fallar cortaria
--     el resto de las pruebas.
--
-- \gset guarda el resultado de una consulta en una variable de psql (:nombre)
-- para usarla despues. Asi no dependemos de los codigos que genera IDENTITY,
-- que cambian cada vez que se corre el archivo.
-- =============================================================================

\set ON_ERROR_ROLLBACK on
\set QUIET on
BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Datos base que usan las pruebas
-- -----------------------------------------------------------------------------
\echo '== 0. Datos base'

INSERT INTO localidad (nombre, provincia, codigo_postal, encargado_regional)
VALUES ('San Rafael', 'Mendoza', '5600', 'Laura Perez')
RETURNING id_localidad AS loc \gset

INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES ('Av. Mitre', 100, 'lunes', :loc)
RETURNING id_sala AS sala1 \gset

INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES ('Av. San Martin', 250, 'domingo', :loc)
RETURNING id_sala AS sala2 \gset

INSERT INTO departamento (nombre, provincia)
VALUES ('San Rafael', 'Mendoza')
RETURNING id_departamento AS depto \gset

INSERT INTO cepa (nombre, tipo) VALUES ('Malbec', 'tinta')
RETURNING id_cepa AS malbec \gset
INSERT INTO cepa (nombre, tipo) VALUES ('Cabernet Franc', 'tinta')
RETURNING id_cepa AS cabernet \gset

INSERT INTO finca (nombre, superficie_ha, id_departamento)
VALUES ('Finca El Atuel', 40, :depto)
RETURNING id_finca AS finca \gset

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30711111111', 'Bodega Prueba SA', 'Ruta 143 km 5');

INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
VALUES ('Transportes Prueba', '20333333333', 'prueba@transportes.com', '2604000000', 'Calle 1')
RETURNING cod_transporte AS transp \gset

INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Prueba Malbec', 'tinto', 2022, 750, 13.5, 15000, '30711111111')
RETURNING cod_vino AS vino_a \gset

INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Prueba Blend', 'tinto', 2021, 750, 14.0, 8000, '30711111111')
RETURNING cod_vino AS vino_b \gset

-- Vino que no aparece en ningun documento: se usa en RN-12 para que el
-- rechazo venga del trigger y no de una clave duplicada
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Prueba Torrontes', 'blanco', 2024, 750, 12.5, 9500, '30711111111')
RETURNING cod_vino AS vino_t \gset

-- Stock inicial de la sala 1. En la realidad llega por una transferencia
-- (RN-11); aca se carga directo para poder probar la venta por separado.
INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (:sala1, :vino_a, 10), (:sala1, :vino_b, 5);

-- -----------------------------------------------------------------------------
-- RN-01: el precio de un vino es unico para toda la red de salas y siempre
-- mayor que cero.
-- Mecanismo: el precio es una columna de vino (no de stock_sala ni de la
-- sala), asi que hay un solo precio por vino; y el CHECK ck_vino_precio.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-01 funciona: el precio esta en el vino, uno solo para todas las salas'
SELECT cod_vino, nombre, precio FROM vino WHERE cod_vino IN (:vino_a, :vino_b);

\echo '== RN-01 debe fallar: precio 0 (viola ck_vino_precio)'
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Gratis', 'tinto', 2022, 750, 13, 0, '30711111111');

\echo '== RN-01 debe fallar: precio negativo (viola ck_vino_precio)'
UPDATE vino SET precio = -100 WHERE cod_vino = :vino_a;

-- -----------------------------------------------------------------------------
-- RN-02: una sala pertenece a una sola localidad. Cada localidad tiene un
-- unico encargado regional.
-- Mecanismo: FK NOT NULL sala_venta.id_localidad, y el encargado es una
-- columna de localidad (3FN: no se repite en cada sala).
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-02 funciona: el encargado se obtiene de la localidad de la sala'
SELECT s.id_sala, l.nombre AS localidad, l.encargado_regional
  FROM sala_venta s
  JOIN localidad l ON l.id_localidad = s.id_localidad
 WHERE s.id_sala IN (:sala1, :sala2);

\echo '== RN-02 debe fallar: sala sin localidad (viola NOT NULL de id_localidad)'
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES ('Calle Sin Localidad', 1, 'lunes', NULL);

\echo '== RN-02 debe fallar: sala con una localidad que no existe (viola fk_sala_localidad)'
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES ('Calle Fantasma', 1, 'lunes', -1);

-- -----------------------------------------------------------------------------
-- RN-03: cada empleado trabaja en una sola sala.
-- Mecanismo: FK NOT NULL empleado.id_sala. Como es una columna, el empleado
-- tiene una sola sala; y la PK (cuit) impide cargarlo dos veces.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-03 funciona: empleado en la sala 1'
INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
VALUES ('20111111111', 'Juan Gomez', '2020-03-01', 900000, :sala1);

\echo '== RN-03 debe fallar: empleado sin sala (viola NOT NULL de id_sala)'
INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
VALUES ('20222222222', 'Ana Ruiz', '2021-05-01', 900000, NULL);

\echo '== RN-03 debe fallar: el mismo empleado en otra sala (clave duplicada pk_empleado)'
INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
VALUES ('20111111111', 'Juan Gomez', '2020-03-01', 900000, :sala2);

-- -----------------------------------------------------------------------------
-- RN-04: una parcela tiene una sola cepa y se cosecha como maximo una vez
-- por campania.
-- Mecanismo: FK NOT NULL parcela.id_cepa con PK (id_finca, nro_parcela), y
-- UNIQUE uq_lote_parcela_campania (id_finca, nro_parcela, campania).
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-04 funciona: parcela 1 con Malbec y una cosecha en 2025'
INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
VALUES (:finca, 1, 2.5, 2010, :malbec);

INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
VALUES (:finca, 1, 2025, '2025-03-10', 8000, '30711111111');

\echo '== RN-04 funciona: la misma parcela en otra campania (2026)'
INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
VALUES (:finca, 1, 2026, '2026-03-12', 7500, '30711111111');

\echo '== RN-04 debe fallar: segunda cosecha de la parcela en 2025 (viola uq_lote_parcela_campania)'
INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
VALUES (:finca, 1, 2025, '2025-04-02', 3000, '30711111111');

\echo '== RN-04 debe fallar: la misma parcela con otra cepa (clave duplicada pk_parcela)'
INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
VALUES (:finca, 1, 2.5, 2010, :cabernet);

-- -----------------------------------------------------------------------------
-- RN-05: los porcentajes de corte de un vino suman exactamente 100.
-- Mecanismo: trigger T7 trg_composicion_suma (no deja pasar de 100) y la
-- vista v_vinos_composicion_incompleta (muestra los que no llegan a 100).
-- Limite conocido: no se exige llegar a 100 justo (docs/03, seccion 7).
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-05 funciona: Prueba Malbec con 85 % Malbec y 15 % Cabernet Franc'
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (:vino_a, :malbec, 85);
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (:vino_a, :cabernet, 15);

\echo '== RN-05 debe fallar: subir el Cabernet a 20 % haria sumar 105 (trigger T7)'
UPDATE composicion SET porcentaje = 20 WHERE cod_vino = :vino_a AND id_cepa = :cabernet;

\echo '== RN-05 limite: Prueba Blend con solo 60 % se acepta, pero aparece en la vista de incompletos'
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (:vino_b, :malbec, 60);
SELECT * FROM v_vinos_composicion_incompleta WHERE cod_vino IN (:vino_a, :vino_b);
-- Esperado: solo aparece Prueba Blend con suma 60. Prueba Malbec suma 100.

-- -----------------------------------------------------------------------------
-- RN-06: el descuento depende del tipo de cliente: socio 10 %, distribuidor
-- 20 %, exportador 30 %.
-- Mecanismo: trigger T8 trg_cliente_descuento, que llama a
-- fn_descuento_cliente, y el dominio porcentaje_dom (CHECK entre 0 y 100).
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-06 funciona: se dan de alta tres clientes sin indicar el descuento'
INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo_cliente)
VALUES ('Carlos Socio', 'DNI', '30111222', 'Belgrano 10', :loc, 'socio')
RETURNING id_cliente AS cli_socio \gset
INSERT INTO socio (id_cliente) VALUES (:cli_socio);

INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo_cliente)
VALUES ('Distribuidora Sur', 'CUIT', '30755555555', 'Ruta 40 km 3', :loc, 'distribuidor')
RETURNING id_cliente AS cli_dist \gset
INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
VALUES (:cli_dist, 'Sur de Mendoza', 'HAB-001');

INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo_cliente)
VALUES ('Export Andes SA', 'CUIT', '30744444444', 'Las Heras 500', :loc, 'exportador')
RETURNING id_cliente AS cli_expo \gset
INSERT INTO exportador (id_cliente, pais_destino) VALUES (:cli_expo, 'Brasil');

SELECT id_cliente, nombre_razon_social, tipo_cliente, descuento
  FROM cliente WHERE id_cliente IN (:cli_socio, :cli_dist, :cli_expo)
 ORDER BY descuento;
-- Esperado: socio 10, distribuidor 20, exportador 30.

\echo '== RN-06 funciona: si el descuento viene cargado se respeta (exportador al 35 %, como en U6)'
INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo_cliente, descuento)
VALUES ('Export Premium SA', 'CUIT', '30766666666', 'Mitre 900', :loc, 'exportador', 35)
RETURNING id_cliente, descuento;

\echo '== RN-06 debe fallar: descuento de 150 % (viola el CHECK del dominio porcentaje_dom)'
INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo_cliente, descuento)
VALUES ('Cliente Imposible', 'DNI', '40999888', 'Sin calle 1', :loc, 'socio', 150);

-- -----------------------------------------------------------------------------
-- RN-07: un exportador puede tener varios permisos; el vencimiento es
-- posterior a la emision.
-- Mecanismo: tabla permiso_exportacion con FK a exportador (no a cliente) y
-- CHECK ck_permiso_fechas entre dos columnas.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-07 funciona: el exportador tiene dos permisos'
INSERT INTO permiso_exportacion (codigo, id_cliente, fecha_emision, fecha_vencimiento)
VALUES ('PE-0001', :cli_expo, '2025-01-01', '2025-12-31'),
       ('PE-0002', :cli_expo, '2026-01-01', '2026-12-31');
SELECT codigo, fecha_emision, fecha_vencimiento
  FROM permiso_exportacion WHERE id_cliente = :cli_expo;

\echo '== RN-07 debe fallar: vence antes de emitirse (viola ck_permiso_fechas)'
INSERT INTO permiso_exportacion (codigo, id_cliente, fecha_emision, fecha_vencimiento)
VALUES ('PE-0003', :cli_expo, '2026-06-01', '2026-01-01');

\echo '== RN-07 debe fallar: permiso para un socio, que no es exportador (viola fk_permiso_exportador)'
INSERT INTO permiso_exportacion (codigo, id_cliente, fecha_emision, fecha_vencimiento)
VALUES ('PE-0004', :cli_socio, '2026-01-01', '2026-12-31');

-- -----------------------------------------------------------------------------
-- RN-08: el total del comprobante es la suma de sus renglones con el
-- descuento aplicado. No se carga a mano.
-- Mecanismo: DEFAULT 0 en los importes, trigger T1 (completa precio,
-- descuento y subtotal del renglon), trigger T2 (recalcula la cabecera) y
-- la funcion fn_total_comprobante.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-08 funciona: venta al socio (10 %) de 2 Prueba Malbec a 15000 y 1 Prueba Blend a 8000'
INSERT INTO comprobante (fecha, id_cliente, id_sala)
VALUES (CURRENT_DATE, :cli_socio, :sala1)
RETURNING nro AS comp1 \gset

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:comp1, :vino_a, 2);
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:comp1, :vino_b, 1);

SELECT cod_vino, cantidad, precio_unitario, descuento, subtotal
  FROM renglon_comprobante WHERE nro_comprobante = :comp1 ORDER BY cod_vino;
-- Esperado: Malbec 2 x 15000, descuento 3000, subtotal 27000
--           Blend  1 x 8000,  descuento 800,  subtotal 7200
SELECT nro, subtotal, descuento, total FROM comprobante WHERE nro = :comp1;
-- Esperado: subtotal 38000, descuento 3800, total 34200
SELECT fn_total_comprobante(:comp1) AS total_calculado;
-- Esperado: 34200, igual al total guardado

\echo '== RN-08 caso a mano: se intenta cargar precio 1 y subtotal 1 en el renglon'
\echo '   No da error, pero el trigger T1 pisa los valores con los correctos.'
INSERT INTO comprobante (fecha, id_cliente, id_sala)
VALUES (CURRENT_DATE, :cli_expo, :sala1)
RETURNING nro AS comp2 \gset

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
VALUES (:comp2, :vino_a, 1, 1, 0, 1);

SELECT r.precio_unitario, r.descuento, r.subtotal, c.total AS total_comprobante
  FROM renglon_comprobante r
  JOIN comprobante c ON c.nro = r.nro_comprobante
 WHERE r.nro_comprobante = :comp2;
-- Esperado: precio 15000, descuento 4500 (exportador 30 %), subtotal 10500, total 10500

-- -----------------------------------------------------------------------------
-- RN-09: no se puede vender mas de lo que hay en stock de la sala. El stock
-- nunca es negativo.
-- Mecanismo: trigger T1 trg_renglon_venta_validar (BEFORE INSERT, usa
-- fn_stock_sala), trigger T2 (descuenta el stock) y CHECK
-- ck_stock_sala_cantidad / ck_stock_deposito_cantidad (cantidad >= 0).
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-09 funciona: las ventas de RN-08 descontaron el stock de la sala 1'
SELECT cod_vino, cantidad FROM stock_sala WHERE id_sala = :sala1 ORDER BY cod_vino;
-- Esperado: Prueba Malbec 10 - 2 - 1 = 7; Prueba Blend 5 - 1 = 4

INSERT INTO comprobante (fecha, id_cliente, id_sala)
VALUES (CURRENT_DATE, :cli_socio, :sala1)
RETURNING nro AS comp3 \gset

\echo '== RN-09 debe fallar: vender 50 Prueba Malbec cuando hay 7 (trigger T1: Stock insuficiente)'
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:comp3, :vino_a, 50);

INSERT INTO comprobante (fecha, id_cliente, id_sala)
VALUES (CURRENT_DATE, :cli_socio, :sala2)
RETURNING nro AS comp4 \gset

\echo '== RN-09 debe fallar: vender en la sala 2, que nunca tuvo ese vino (trigger T1: hay 0)'
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:comp4, :vino_a, 1);

\echo '== RN-09 la venta rechazada no dejo nada a medias: stock igual y comprobante en 0'
SELECT cantidad AS stock_malbec_sala1 FROM stock_sala WHERE id_sala = :sala1 AND cod_vino = :vino_a;
SELECT nro, total FROM comprobante WHERE nro = :comp3;
-- Esperado: stock 7 y total 0

\echo '== RN-09 debe fallar: dejar el stock en negativo a mano (viola ck_stock_sala_cantidad)'
UPDATE stock_sala SET cantidad = -1 WHERE id_sala = :sala1 AND cod_vino = :vino_a;

-- -----------------------------------------------------------------------------
-- RN-10: solo un ingreso terminado impacta en el deposito y pasa a
-- procesado. Las transiciones son en_confeccion -> terminado -> procesado y
-- no retroceden.
-- Mecanismo: ENUM estado_documento con DEFAULT en_confeccion, trigger T3
-- trg_ingreso_estado y procedimiento sp_procesar_ingreso.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-10 funciona: ingreso nuevo, nace en_confeccion (DEFAULT)'
INSERT INTO ingreso (fecha, cod_transporte, cuit_bodega)
VALUES (CURRENT_DATE, :transp, '30711111111')
RETURNING cod_ingreso AS ing1, estado \gset
\echo '   estado inicial:' :estado
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (:ing1, :vino_a, 100), (:ing1, :vino_b, 50);

\echo '== RN-10 debe fallar: procesar el ingreso en confeccion (sp_procesar_ingreso: solo si esta terminado)'
CALL sp_procesar_ingreso(:ing1);

\echo '== RN-10 debe fallar: saltear terminado y pasar directo a procesado (trigger T3)'
UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = :ing1;

\echo '== RN-10 debe fallar: un estado que no existe (valor invalido para el ENUM estado_documento)'
UPDATE ingreso SET estado = 'anulado' WHERE cod_ingreso = :ing1;

\echo '== RN-10 funciona: terminar y procesar; el deposito recibe 100 Malbec y 50 Blend'
UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = :ing1;
CALL sp_procesar_ingreso(:ing1);
SELECT cod_ingreso, estado FROM ingreso WHERE cod_ingreso = :ing1;
SELECT cod_vino, cantidad FROM stock_deposito WHERE cod_vino IN (:vino_a, :vino_b) ORDER BY cod_vino;
-- Esperado: estado procesado; deposito Malbec 100, Blend 50

\echo '== RN-10 debe fallar: volver de procesado a en_confeccion (trigger T3)'
UPDATE ingreso SET estado = 'en_confeccion' WHERE cod_ingreso = :ing1;

\echo '== RN-10 debe fallar: procesar dos veces el mismo ingreso (ya esta procesado)'
CALL sp_procesar_ingreso(:ing1);

-- -----------------------------------------------------------------------------
-- RN-11: igual que RN-10 para transferencias. La fecha de confeccion es la
-- actual y no se puede modificar.
-- Mecanismo: trigger T3 trg_transferencia_estado, trigger T5
-- trg_transferencia_fecha y procedimiento sp_procesar_transferencia.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-11 funciona: se intenta crear con fecha 2020-01-01 y el trigger T5 pone la de hoy'
INSERT INTO transferencia (id_sala, fecha_confeccion)
VALUES (:sala1, '2020-01-01')
RETURNING nro_solicitud AS transf1 \gset
SELECT nro_solicitud, fecha_confeccion = CURRENT_DATE AS es_la_fecha_de_hoy, estado
  FROM transferencia WHERE nro_solicitud = :transf1;
-- Esperado: es_la_fecha_de_hoy = t, estado en_confeccion

\echo '== RN-11 debe fallar: modificar la fecha de confeccion (trigger T5)'
UPDATE transferencia SET fecha_confeccion = CURRENT_DATE - 1 WHERE nro_solicitud = :transf1;

\echo '== RN-11 funciona: transferir 30 Malbec del deposito a la sala 1'
INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad) VALUES (:transf1, :vino_a, 30);
UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = :transf1;
CALL sp_procesar_transferencia(:transf1);
SELECT cantidad AS deposito_malbec FROM stock_deposito WHERE cod_vino = :vino_a;
SELECT cantidad AS sala1_malbec FROM stock_sala WHERE id_sala = :sala1 AND cod_vino = :vino_a;
-- Esperado: deposito 100 - 30 = 70; sala 1: 7 + 30 = 37

\echo '== RN-11 debe fallar: volver de procesado a terminado (trigger T3)'
UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = :transf1;

\echo '== RN-11 debe fallar: transferir 500 Blend cuando el deposito tiene 50 (sp_procesar_transferencia)'
INSERT INTO transferencia (id_sala) VALUES (:sala2)
RETURNING nro_solicitud AS transf2 \gset
INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
VALUES (:transf2, :vino_a, 20), (:transf2, :vino_b, 500);
UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = :transf2;
CALL sp_procesar_transferencia(:transf2);

\echo '== RN-11 la transferencia rechazada no dejo nada a medias'
SELECT cod_vino, cantidad FROM stock_deposito WHERE cod_vino IN (:vino_a, :vino_b) ORDER BY cod_vino;
SELECT estado FROM transferencia WHERE nro_solicitud = :transf2;
SELECT COUNT(*) AS filas_stock_sala2 FROM stock_sala WHERE id_sala = :sala2;
-- Esperado: deposito Malbec 70 (no se restaron los 20) y Blend 50;
--           la transferencia sigue terminado; la sala 2 no recibio nada (0 filas)

-- -----------------------------------------------------------------------------
-- RN-12: un ingreso o una transferencia que no esta en confeccion no admite
-- agregar, modificar ni quitar renglones.
-- Mecanismo: trigger T4 trg_renglon_ingreso_bloqueo y
-- trg_renglon_transf_bloqueo (BEFORE INSERT OR UPDATE OR DELETE).
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-12 debe fallar: agregar un renglon al ingreso procesado (trigger T4)'
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (:ing1, :vino_t, 5);

\echo '== RN-12 debe fallar: modificar un renglon del ingreso procesado (trigger T4)'
UPDATE renglon_ingreso SET cantidad = 999 WHERE cod_ingreso = :ing1 AND cod_vino = :vino_a;

\echo '== RN-12 debe fallar: quitar un renglon del ingreso procesado (trigger T4)'
DELETE FROM renglon_ingreso WHERE cod_ingreso = :ing1 AND cod_vino = :vino_b;

\echo '== RN-12 debe fallar: agregar un renglon a la transferencia procesada (trigger T4)'
INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad) VALUES (:transf1, :vino_t, 1);

\echo '== RN-12 funciona: en un ingreso en confeccion se puede agregar, modificar y quitar'
INSERT INTO ingreso (fecha, cod_transporte, cuit_bodega)
VALUES (CURRENT_DATE, :transp, '30711111111')
RETURNING cod_ingreso AS ing2 \gset
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (:ing2, :vino_a, 10), (:ing2, :vino_b, 10);
UPDATE renglon_ingreso SET cantidad = 12 WHERE cod_ingreso = :ing2 AND cod_vino = :vino_a;
DELETE FROM renglon_ingreso WHERE cod_ingreso = :ing2 AND cod_vino = :vino_b;
SELECT cod_vino, cantidad FROM renglon_ingreso WHERE cod_ingreso = :ing2;
-- Esperado: un solo renglon, Prueba Malbec con 12

\echo '== RN-12 funciona: borrar la transferencia terminada entera borra sus renglones en cascada'
DELETE FROM transferencia WHERE nro_solicitud = :transf2;
SELECT COUNT(*) AS renglones_que_quedan FROM renglon_transferencia WHERE nro_solicitud = :transf2;
-- Esperado: 0

-- -----------------------------------------------------------------------------
-- RN-13: todo cambio de precio de un vino queda auditado (fecha, usuario,
-- precio anterior y nuevo).
-- Mecanismo: trigger T6 trg_vino_auditar_precio (AFTER UPDATE) y la tabla
-- auditoria_precio; 007_roles.sql le quita a la API UPDATE y DELETE sobre ella.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-13 funciona: subir el precio de Prueba Malbec de 15000 a 16000'
UPDATE vino SET precio = 16000 WHERE cod_vino = :vino_a;

\echo '== RN-13 funciona: cambiar otra columna (graduacion) no se audita'
UPDATE vino SET graduacion = 13.8 WHERE cod_vino = :vino_a;

\echo '== RN-13 funciona: el rol de la API tambien cambia el precio y queda su usuario'
SET ROLE bodegas_api;
UPDATE vino SET precio = 16500 WHERE cod_vino = :vino_a;
RESET ROLE;

SELECT precio_anterior, precio_nuevo, usuario, fecha_hora IS NOT NULL AS tiene_fecha
  FROM auditoria_precio WHERE cod_vino = :vino_a ORDER BY id_auditoria;
-- Esperado: dos filas (el cambio de graduacion no genera ninguna)
--           15000 -> 16000 por postgres; 16000 -> 16500 por bodegas_api

\echo '== RN-13 debe fallar: la API intenta borrar la auditoria (permiso denegado, 007_roles.sql)'
SET ROLE bodegas_api;
DELETE FROM auditoria_precio WHERE cod_vino = :vino_a;

\echo '== RN-13 debe fallar: la API intenta corregir un precio auditado (permiso denegado)'
UPDATE auditoria_precio SET precio_anterior = 1 WHERE cod_vino = :vino_a;
RESET ROLE;

-- -----------------------------------------------------------------------------
-- RN-14: no se puede borrar un transportista, una bodega ni un vino que
-- tengan movimientos asociados.
-- Mecanismo: claves foraneas con ON DELETE RESTRICT hacia vino, bodega y
-- transportista.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-14 debe fallar: borrar Prueba Malbec, que tiene ventas, stock e ingresos (FK RESTRICT)'
DELETE FROM vino WHERE cod_vino = :vino_a;

\echo '== RN-14 debe fallar: borrar la bodega, que tiene vinos, lotes e ingresos (FK RESTRICT)'
DELETE FROM bodega WHERE cuit = '30711111111';

\echo '== RN-14 debe fallar: borrar el transportista, que tiene ingresos (fk_ingreso_transportista)'
DELETE FROM transportista WHERE cod_transporte = :transp;

\echo '== RN-14 funciona: un vino sin movimientos se borra, y su composicion se va en cascada'
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Sin Movimientos', 'rosado', 2024, 750, 12, 9000, '30711111111')
RETURNING cod_vino AS vino_c \gset
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (:vino_c, :malbec, 100);
DELETE FROM vino WHERE cod_vino = :vino_c;
SELECT COUNT(*) AS composicion_que_queda FROM composicion WHERE cod_vino = :vino_c;
-- Esperado: 0

-- -----------------------------------------------------------------------------
-- RN-15: cantidades, superficies, kilos y precios son siempre positivos. La
-- graduacion esta entre 5 y 20.
-- Mecanismo: CHECK ck_vino_graduacion, ck_vino_precio (RN-01),
-- ck_renglon_*_cantidad, ck_lote_kilos, ck_finca_superficie y
-- ck_parcela_superficie.
-- -----------------------------------------------------------------------------
\echo ''
\echo '== RN-15 funciona: graduacion en los limites, 5 y 20'
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Liviano', 'blanco', 2024, 750, 5, 7000, '30711111111'),
       ('Vino Fortificado', 'tinto', 2024, 500, 20, 12000, '30711111111');

\echo '== RN-15 debe fallar: graduacion 25 (viola ck_vino_graduacion)'
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Imposible', 'tinto', 2024, 750, 25, 10000, '30711111111');

\echo '== RN-15 debe fallar: graduacion 3 (viola ck_vino_graduacion)'
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Aguado', 'blanco', 2024, 750, 3, 10000, '30711111111');

\echo '== RN-15 debe fallar: renglon de ingreso con cantidad 0 (viola ck_renglon_ingreso_cantidad)'
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (:ing2, :vino_b, 0);

\echo '== RN-15 debe fallar: renglon de transferencia con cantidad negativa (viola ck_renglon_transferencia_cantidad)'
INSERT INTO transferencia (id_sala) VALUES (:sala1)
RETURNING nro_solicitud AS transf3 \gset
INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad) VALUES (:transf3, :vino_a, -5);

\echo '== RN-15 debe fallar: renglon de venta con cantidad 0 (viola ck_renglon_comprobante_cantidad)'
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:comp3, :vino_b, 0);

\echo '== RN-15 debe fallar: cosecha de -10 kilos (viola ck_lote_kilos)'
INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
VALUES (:finca, 1, 2024, '2024-03-01', -10, '30711111111');

\echo '== RN-15 debe fallar: finca de 0 hectareas (viola ck_finca_superficie)'
INSERT INTO finca (nombre, superficie_ha, id_departamento) VALUES ('Finca Vacia', 0, :depto);

\echo '== RN-15 debe fallar: parcela de 0 hectareas (viola ck_parcela_superficie)'
INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
VALUES (:finca, 2, 0, 2015, :malbec);

-- -----------------------------------------------------------------------------
-- Fin: se deshace todo lo que se cargo en las pruebas
-- -----------------------------------------------------------------------------
ROLLBACK;
\echo ''
\echo '== Fin de las pruebas. ROLLBACK: la base quedo como estaba.'
