-- =============================================================================
-- consultas/insert.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Consultas de la seccion 8.2 del enunciado.
-- Los parametros estan en los \set de abajo: cambiar ahi para probar otros valores.
-- Como se corre: ver tareas/manuel.md, seccion 3.
-- Las lineas Resultado son de la carga completa con fecha de referencia 2026-11-06.
--
-- Cada sentencia va en BEGIN / control previo / sentencia / control posterior /
-- ROLLBACK: se ve el antes y el despues, y la base queda igual.
-- :ROW_COUNT es una variable de psql con las filas que afecto la ultima sentencia.
-- \gset guarda el resultado de una consulta en variables de psql (:nombre).
-- =============================================================================
\set QUIET on
\set ON_ERROR_ROLLBACK on
\set loc_i1 'General Alvear'
\set vino 'Malbec Reserva'
\set vol 750
\set sala_i3 1

-- -----------------------------------------------------------------------------
-- I1. Insertar en la relacion transportista-localidad una nueva cobertura que
--     vincule la localidad de General Alvear con el transportista que menos
--     envios (ingresos trasladados) haya realizado en el ultimo trimestre.
-- Estrategia: se cuentan los ingresos por transportista con LEFT JOIN, para que
-- los que no tuvieron ninguno cuenten con 0. La condicion de la fecha va en el ON
-- y no en el WHERE: en el WHERE descartaria a esos transportistas. Si hay empate,
-- gana el de menor cod_transporte.
-- ON CONFLICT DO NOTHING: si ese transportista ya cubria la localidad, el par ya
-- esta en la tabla y no se inserta nada, en vez de dar error por clave duplicada.
-- Resultado: 0 filas. El transportista con menos ingresos (cod 9, con 3 en el
-- trimestre) ya cubria General Alvear, asi que ON CONFLICT DO NOTHING no inserta
-- nada. No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== I1'
BEGIN;
-- Control previo: los transportistas con menos ingresos en el trimestre
SELECT t.cod_transporte, t.razon_social, COUNT(i.cod_ingreso) AS ingresos
  FROM transportista t
  LEFT JOIN ingreso i ON i.cod_transporte = t.cod_transporte
                     AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY t.cod_transporte, t.razon_social
 ORDER BY ingresos, t.cod_transporte
 LIMIT 3;

INSERT INTO transportista_localidad (cod_transporte, id_localidad)
SELECT (SELECT t.cod_transporte
          FROM transportista t
          LEFT JOIN ingreso i ON i.cod_transporte = t.cod_transporte
                             AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
         GROUP BY t.cod_transporte
         ORDER BY COUNT(i.cod_ingreso), t.cod_transporte
         LIMIT 1),
       l.id_localidad
  FROM localidad l
 WHERE l.nombre = :'loc_i1'
ON CONFLICT DO NOTHING;
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior: la cobertura de esa localidad
SELECT tl.cod_transporte, t.razon_social, l.nombre AS localidad
  FROM transportista_localidad tl
  JOIN transportista t ON t.cod_transporte = tl.cod_transporte
  JOIN localidad l ON l.id_localidad = tl.id_localidad
 WHERE l.nombre = :'loc_i1'
 ORDER BY tl.cod_transporte;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- I2. Si existe algun vino tinto con graduacion de 14 grados o mas, crear el
--     maridaje "cordero al disco" y asociarlo a todos los vinos que cumplan esa
--     condicion.
-- Estrategia: dos sentencias. La primera es un INSERT ... SELECT sin FROM: el
-- WHERE EXISTS hace que el SELECT devuelva una fila solo si hay algun vino que
-- cumpla, y asi se resuelve el "si existe". RETURNING guarda el codigo generado
-- para usarlo en la segunda, que asocia todos los vinos que cumplen.
-- Decision: la temperatura de servicio es 16 grados.
-- Resultado: 1 maridaje y 95 vinos asociados. No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== I2'
BEGIN;
-- Control previo: los vinos que cumplen la condicion
SELECT cod_vino, nombre, graduacion
  FROM vino
 WHERE tipo = 'tinto' AND graduacion >= 14
 ORDER BY cod_vino;

INSERT INTO maridaje (nombre, temperatura_servicio)
SELECT 'Cordero al disco', 16
 WHERE EXISTS (SELECT 1 FROM vino WHERE tipo = 'tinto' AND graduacion >= 14)
RETURNING id_maridaje AS mar \gset
\echo '   maridajes creados:' :ROW_COUNT

INSERT INTO vino_maridaje (cod_vino, id_maridaje)
SELECT cod_vino, :mar
  FROM vino
 WHERE tipo = 'tinto' AND graduacion >= 14;
\echo '   vinos asociados:' :ROW_COUNT

-- Control posterior
SELECT m.nombre AS maridaje, m.temperatura_servicio, COUNT(*) AS vinos
  FROM maridaje m
  JOIN vino_maridaje vm ON vm.id_maridaje = m.id_maridaje
 WHERE m.id_maridaje = :mar
 GROUP BY m.nombre, m.temperatura_servicio;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- I3. Crear un nuevo comprobante con tres renglones para un cliente dado, en la
--     sala con ID 1, dentro de una transaccion y usando las funciones de calculo.
-- Estrategia: el cliente es el socio de menor id_cliente que tenga compras. Los
-- tres renglones son los 3 vinos con mas stock en la sala, una botella de cada
-- uno. No se cargan precio, descuento ni subtotal: los calculan los triggers T1 y
-- T2, que usan fn_stock_sala y fn_total_comprobante. BEGIN ... ROLLBACK es la
-- transaccion que pide la consigna: si un renglon falla, no queda nada a medias.
-- El control posterior compara el total guardado con fn_total_comprobante.
-- Resultado: 1 comprobante y 3 renglones. Dispara T1 y T2: por cada renglon valida el
-- stock, lo descuenta y recalcula la cabecera. El total guardado (41.760) coincide
-- con fn_total_comprobante.
-- -----------------------------------------------------------------------------
\echo '== I3'
BEGIN;
-- Control previo: los 3 vinos con mas stock en la sala
SELECT cod_vino, cantidad
  FROM stock_sala
 WHERE id_sala = :sala_i3
 ORDER BY cantidad DESC, cod_vino
 LIMIT 3;

INSERT INTO comprobante (fecha, id_cliente, id_sala)
SELECT CURRENT_DATE, MIN(cl.id_cliente), :sala_i3
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente)
RETURNING nro AS nro \gset

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
SELECT :nro, cod_vino, 1
  FROM stock_sala
 WHERE id_sala = :sala_i3
 ORDER BY cantidad DESC, cod_vino
 LIMIT 3;
\echo '   renglones insertados:' :ROW_COUNT

-- Control posterior: los renglones, la cabecera y el total calculado
SELECT cod_vino, cantidad, precio_unitario, descuento, subtotal
  FROM renglon_comprobante
 WHERE nro_comprobante = :nro
 ORDER BY cod_vino;

SELECT nro, id_cliente, subtotal, descuento, total,
       fn_total_comprobante(:nro) AS total_calculado
  FROM comprobante
 WHERE nro = :nro;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- I4. Insertar una nueva bodega.
-- Estrategia: INSERT simple. El CUIT lo escribe el usuario porque es una clave
-- natural; el dominio cuit_dom controla que sean 11 digitos. Es un dato inventado,
-- por eso aca si hay un CUIT literal.
-- Resultado: 1 fila. No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== I4'
BEGIN;
-- Control previo: esa bodega todavia no existe
SELECT COUNT(*) AS bodegas_con_ese_cuit FROM bodega WHERE cuit = '30999999991';

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30999999991', 'Bodega Nueva del Atuel', 'Ruta 143 km 5, San Rafael');
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior
SELECT cuit, razon_social, domicilio FROM bodega WHERE cuit = '30999999991';
ROLLBACK;

-- -----------------------------------------------------------------------------
-- I5. Insertar una nueva sala de venta.
-- Estrategia: INSERT con la localidad buscada por nombre con una subconsulta, asi
-- no queda un codigo suelto. El id_sala lo genera IDENTITY.
-- Resultado: 1 fila. No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== I5'
BEGIN;
-- Control previo: las salas de esa localidad
SELECT s.id_sala, s.calle, s.numero, s.dia_cierre
  FROM sala_venta s
  JOIN localidad l ON l.id_localidad = s.id_localidad
 WHERE l.nombre = :'loc_i1'
 ORDER BY s.id_sala;

INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES ('Av. Alvear Oeste', 1200, 'domingo',
        (SELECT id_localidad FROM localidad WHERE nombre = :'loc_i1'));
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior
SELECT s.id_sala, s.calle, s.numero, s.dia_cierre
  FROM sala_venta s
  JOIN localidad l ON l.id_localidad = s.id_localidad
 WHERE l.nombre = :'loc_i1'
 ORDER BY s.id_sala;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- I6. Crear un ingreso en confeccion de 120 botellas de un vino determinado (por
--     ejemplo "Malbec Reserva" de 750 ml), elaborado por una bodega dada y
--     trasladado por un transportista dado.
-- Estrategia: primero se busca el vino (la aniada mas reciente) y su bodega, y se
-- guardan con \gset. El ingreso no indica el estado: nace en_confeccion por el
-- DEFAULT. El transportista es el de menor cod_transporte.
-- El stock del deposito no cambia: solo impacta al procesarlo (RN-10).
-- Resultado: 1 ingreso y 1 renglon. Dispara el trigger T4 de renglones, que lo deja
-- pasar porque el ingreso esta en confeccion. El deposito sigue en 889 botellas.
-- -----------------------------------------------------------------------------
\echo '== I6'
BEGIN;
-- Control previo: el vino elegido y su stock en el deposito
SELECT cod_vino AS vino_i6, cuit_bodega AS bodega_i6
  FROM vino
 WHERE nombre = :'vino' AND volumen_ml = :vol
 ORDER BY anada DESC
 LIMIT 1 \gset

SELECT v.cod_vino, v.nombre, v.anada, b.razon_social AS bodega,
       COALESCE(d.cantidad, 0) AS en_deposito
  FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega
  LEFT JOIN stock_deposito d ON d.cod_vino = v.cod_vino
 WHERE v.cod_vino = :vino_i6;

INSERT INTO ingreso (fecha, cod_transporte, cuit_bodega)
VALUES (CURRENT_DATE, (SELECT MIN(cod_transporte) FROM transportista), :'bodega_i6')
RETURNING cod_ingreso AS ing \gset

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (:ing, :vino_i6, 120);
\echo '   renglones insertados:' :ROW_COUNT

-- Control posterior: el ingreso, su renglon y el deposito sin cambios
SELECT i.cod_ingreso, i.fecha, i.estado, i.cod_transporte, r.cod_vino, r.cantidad
  FROM ingreso i
  JOIN renglon_ingreso r ON r.cod_ingreso = i.cod_ingreso
 WHERE i.cod_ingreso = :ing;

SELECT COALESCE((SELECT cantidad FROM stock_deposito WHERE cod_vino = :vino_i6), 0) AS en_deposito;
ROLLBACK;
