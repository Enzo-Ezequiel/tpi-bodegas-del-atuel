-- =============================================================================
-- consultas/update.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Consultas de la seccion 8.1 del enunciado.
-- Los parametros estan en los \set de abajo: cambiar ahi para probar otros valores.
-- Como se corre: ver tareas/manuel.md, seccion 3.
-- Las lineas Resultado son de la carga completa con fecha de referencia 2026-11-06.
--
-- Cada sentencia va en BEGIN / control previo / sentencia / control posterior /
-- ROLLBACK: se ve el antes y el despues, y la base queda igual.
-- :ROW_COUNT es una variable de psql con las filas que afecto la ultima sentencia.
-- =============================================================================
\set QUIET on
\set ON_ERROR_ROLLBACK on
\set bodega 'Bodega Los Tres Vinos'

-- -----------------------------------------------------------------------------
-- U1. Recalcular el total de todos los comprobantes aplicando el descuento que
--     corresponde al tipo de cliente.
-- Estrategia: dos UPDATE. Primero los renglones, uniendo comprobante y cliente
-- para llegar al tipo de cliente; fn_descuento_cliente da el porcentaje del tipo
-- (no se usa cliente.descuento, que puede ser 35 por U6). Despues la cabecera,
-- con las sumas de sus renglones, igual que el trigger T2.
-- La expresion del descuento se repite en subtotal porque, dentro de un SET,
-- las columnas todavia tienen el valor viejo.
-- Decision: la cabecera solo se actualiza si tiene renglones. Un comprobante sin
-- renglones daria SUM = NULL y chocaria con el NOT NULL de subtotal y descuento.
-- Resultado: 125.135 renglones y 50.000 comprobantes actualizados. Ningun importe
-- cambia: la carga ya tenia el descuento de cada tipo de cliente. No dispara
-- triggers: T1 y T2 son de INSERT, no de UPDATE.
-- -----------------------------------------------------------------------------
\echo '== U1'
BEGIN;
-- Control previo: una muestra de 5 comprobantes (afecta a todos)
SELECT c.nro, cl.tipo_cliente, c.subtotal, c.descuento, c.total
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 ORDER BY c.nro
 LIMIT 5;

UPDATE renglon_comprobante r
   SET descuento = ROUND(r.cantidad * r.precio_unitario * fn_descuento_cliente(cl.tipo_cliente) / 100, 2),
       subtotal  = r.cantidad * r.precio_unitario
                 - ROUND(r.cantidad * r.precio_unitario * fn_descuento_cliente(cl.tipo_cliente) / 100, 2)
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.nro = r.nro_comprobante;
\echo '   renglones actualizados:' :ROW_COUNT

UPDATE comprobante c
   SET subtotal  = (SELECT SUM(r.cantidad * r.precio_unitario)
                      FROM renglon_comprobante r
                     WHERE r.nro_comprobante = c.nro),
       descuento = (SELECT SUM(r.descuento)
                      FROM renglon_comprobante r
                     WHERE r.nro_comprobante = c.nro),
       total     = fn_total_comprobante(c.nro)
 WHERE EXISTS (SELECT 1
                 FROM renglon_comprobante r
                WHERE r.nro_comprobante = c.nro);
\echo '   comprobantes actualizados:' :ROW_COUNT

-- Control posterior: los mismos 5 comprobantes
SELECT c.nro, cl.tipo_cliente, c.subtotal, c.descuento, c.total
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 ORDER BY c.nro
 LIMIT 5;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- U2. Aumentar un 20 % el salario de los empleados con mas de 5 anios de
--     antiguedad.
-- Estrategia: la antiguedad no se guarda porque cambia todos los dias: la calcula
-- fn_antiguedad_anios. Cuenta anios completos, asi que > 5 son 6 anios o mas.
-- Resultado: 200 empleados. No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== U2'
BEGIN;
-- Control previo: una muestra de 5 empleados que se van a tocar
SELECT cuit, nombre, fecha_ingreso, fn_antiguedad_anios(fecha_ingreso) AS antiguedad, salario
  FROM empleado
 WHERE fn_antiguedad_anios(fecha_ingreso) > 5
 ORDER BY cuit
 LIMIT 5;

UPDATE empleado
   SET salario = salario * 1.20
 WHERE fn_antiguedad_anios(fecha_ingreso) > 5;
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior: los mismos 5 empleados
SELECT cuit, nombre, fecha_ingreso, fn_antiguedad_anios(fecha_ingreso) AS antiguedad, salario
  FROM empleado
 WHERE fn_antiguedad_anios(fecha_ingreso) > 5
 ORDER BY cuit
 LIMIT 5;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- U3. Incrementar un 13 % el precio de los vinos elaborados por una bodega
--     determinada.
-- Estrategia: la bodega se busca por razon social con una subconsulta, asi no
-- queda un CUIT suelto. Se usa IN porque razon_social no es UNIQUE. ROUND deja
-- el precio con dos decimales.
-- En auditoria_precio se filtra por fecha_hora = now(): dentro de una transaccion
-- now() no cambia, asi que son justo las filas que escribio este UPDATE.
-- Resultado: 3 vinos. Dispara el trigger T6: agrega 3 filas en auditoria_precio.
-- -----------------------------------------------------------------------------
\echo '== U3'
BEGIN;
-- Control previo
SELECT cod_vino, nombre, precio
  FROM vino
 WHERE cuit_bodega IN (SELECT cuit FROM bodega WHERE razon_social = :'bodega')
 ORDER BY cod_vino;

UPDATE vino
   SET precio = ROUND(precio * 1.13, 2)
 WHERE cuit_bodega IN (SELECT cuit FROM bodega WHERE razon_social = :'bodega');
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior: los vinos y las filas nuevas de la auditoria
SELECT cod_vino, nombre, precio
  FROM vino
 WHERE cuit_bodega IN (SELECT cuit FROM bodega WHERE razon_social = :'bodega')
 ORDER BY cod_vino;

SELECT cod_vino, precio_anterior, precio_nuevo, usuario
  FROM auditoria_precio
 WHERE fecha_hora = now()
 ORDER BY cod_vino;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- U4. En las salas cuyo dia de cierre es lunes cambiarlo a miercoles y viceversa,
--     en una sola sentencia.
-- Estrategia: un solo UPDATE con CASE. Con dos UPDATE seguidos no se puede: el
-- primero pasa los lunes a miercoles y el segundo los vuelve a lunes junto con
-- los miercoles originales. El WHERE deja afuera a las demas salas.
-- ::dia_semana hace falta porque, sin el tipo, el CASE devuelve texto y una
-- columna ENUM no acepta texto.
-- Resultado: 9 salas (5 pasan a miercoles y 4 a lunes). No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== U4'
BEGIN;
-- Control previo
SELECT id_sala, dia_cierre
  FROM sala_venta
 WHERE dia_cierre IN ('lunes', 'miercoles')
 ORDER BY id_sala;

UPDATE sala_venta
   SET dia_cierre = CASE dia_cierre
                        WHEN 'lunes'     THEN 'miercoles'::dia_semana
                        WHEN 'miercoles' THEN 'lunes'::dia_semana
                    END
 WHERE dia_cierre IN ('lunes', 'miercoles');
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior
SELECT id_sala, dia_cierre
  FROM sala_venta
 WHERE dia_cierre IN ('lunes', 'miercoles')
 ORDER BY id_sala;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- U5. Aplicar un 15 % de descuento de precio a los 10 vinos menos vendidos de
--     toda la red.
-- Estrategia: la subconsulta arma el ranking. El LEFT JOIN desde vino hace falta
-- para contar a los que nunca se vendieron: con un JOIN comun no aparecerian,
-- y son justamente los menos vendidos. COALESCE convierte su suma NULL en 0, y
-- cod_vino desempata para que siempre sean los mismos 10.
-- Resultado: 10 vinos. Dispara el trigger T6: agrega 10 filas en auditoria_precio.
-- -----------------------------------------------------------------------------
\echo '== U5'
BEGIN;
-- Control previo: los 10 vinos, con lo que vendieron
SELECT v.cod_vino, v.nombre, v.precio, COALESCE(SUM(r.cantidad), 0) AS vendidas
  FROM vino v
  LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
 GROUP BY v.cod_vino, v.nombre, v.precio
 ORDER BY vendidas, v.cod_vino
 LIMIT 10;

UPDATE vino
   SET precio = ROUND(precio * 0.85, 2)
 WHERE cod_vino IN (SELECT v.cod_vino
                      FROM vino v
                      LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
                     GROUP BY v.cod_vino
                     ORDER BY COALESCE(SUM(r.cantidad), 0), v.cod_vino
                     LIMIT 10);
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior: los mismos 10 vinos (las ventas no cambiaron) y la auditoria
SELECT v.cod_vino, v.nombre, v.precio, COALESCE(SUM(r.cantidad), 0) AS vendidas
  FROM vino v
  LEFT JOIN renglon_comprobante r ON r.cod_vino = v.cod_vino
 GROUP BY v.cod_vino, v.nombre, v.precio
 ORDER BY vendidas, v.cod_vino
 LIMIT 10;

SELECT cod_vino, precio_anterior, precio_nuevo, usuario
  FROM auditoria_precio
 WHERE fecha_hora = now()
 ORDER BY cod_vino;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- U6. A los exportadores con mas de 3 permisos de exportacion, subirles el
--     descuento al 35 %.
-- Estrategia: se cuentan los permisos por cliente con GROUP BY y HAVING. No hace
-- falta filtrar por tipo: permiso_exportacion apunta a exportador, asi que ahi
-- solo hay exportadores. El descuento es una columna de cliente porque no es fijo
-- por tipo, justamente por esta consigna.
-- Resultado: 704 clientes. No dispara triggers: T8 es de INSERT. El 35 esta dentro
-- del rango de porcentaje_dom.
-- -----------------------------------------------------------------------------
\echo '== U6'
BEGIN;
-- Control previo
SELECT id_cliente, nombre_razon_social, descuento
  FROM cliente
 WHERE id_cliente IN (SELECT id_cliente
                        FROM permiso_exportacion
                       GROUP BY id_cliente
                      HAVING COUNT(*) > 3)
 ORDER BY id_cliente;

UPDATE cliente
   SET descuento = 35
 WHERE id_cliente IN (SELECT id_cliente
                        FROM permiso_exportacion
                       GROUP BY id_cliente
                      HAVING COUNT(*) > 3);
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior
SELECT id_cliente, nombre_razon_social, descuento
  FROM cliente
 WHERE id_cliente IN (SELECT id_cliente
                        FROM permiso_exportacion
                       GROUP BY id_cliente
                      HAVING COUNT(*) > 3)
 ORDER BY id_cliente;
ROLLBACK;
