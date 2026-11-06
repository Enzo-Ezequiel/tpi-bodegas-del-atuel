-- =============================================================================
-- consultas/select.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Consultas de la seccion 8.4 y 8.5 del enunciado.
-- Los parametros estan en los \set de abajo: cambiar ahi para probar otros valores.
-- Como se corre: ver tareas/manuel.md, seccion 3.
-- =============================================================================
\set QUIET on
\set ON_ERROR_ROLLBACK on
\set vino 'Malbec Reserva'
\set vol 750
\set bodega 'Bodega Los Tres Vinos'
\set sala_s 1

-- -----------------------------------------------------------------------------
-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas en toda la
--     red de salas.
-- Estrategia: se suman las cantidades de renglon_comprobante por vino, y el JOIN
-- con vino trae sus datos. No hace falta pasar por comprobante porque es toda la
-- red. cod_vino desempata para que el resultado sea siempre el mismo.
-- -----------------------------------------------------------------------------
\echo '== S1'
SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, SUM(r.cantidad) AS botellas
  FROM renglon_comprobante r
  JOIN vino v ON v.cod_vino = r.cod_vino
 GROUP BY v.cod_vino, v.nombre, v.anada, v.volumen_ml
 ORDER BY botellas DESC, v.cod_vino
 LIMIT 10;

-- -----------------------------------------------------------------------------
-- S2. Listar codigos y nombres de los vinos que se vendieron en todas las salas
--     (division relacional).
-- Estrategia: SQL no tiene un "para todas", asi que se dice al reves con doble
-- NOT EXISTS: un vino va en el resultado si NO existe una sala en la que NO se
-- haya vendido. El NOT EXISTS de adentro busca una venta de ese vino en esa sala.
-- -----------------------------------------------------------------------------
\echo '== S2'
SELECT v.cod_vino, v.nombre
  FROM vino v
 WHERE NOT EXISTS (SELECT 1
                     FROM sala_venta s
                    WHERE NOT EXISTS (SELECT 1
                                        FROM comprobante c
                                        JOIN renglon_comprobante r ON r.nro_comprobante = c.nro
                                       WHERE c.id_sala = s.id_sala
                                         AND r.cod_vino = v.cod_vino))
 ORDER BY v.cod_vino;

-- -----------------------------------------------------------------------------
-- S3. Cantidad de clientes de cada tipo que compraron en una sala determinada en
--     la ultima semana.
-- Estrategia: comprobante unido con cliente para llegar al tipo, y GROUP BY por
-- tipo. COUNT(DISTINCT) hace falta porque un cliente puede tener varios
-- comprobantes en la semana y tiene que contar una sola vez.
-- -----------------------------------------------------------------------------
\echo '== S3'
SELECT cl.tipo_cliente, COUNT(DISTINCT c.id_cliente) AS clientes
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.id_sala = :sala_s
   AND c.fecha >= CURRENT_DATE - 7
 GROUP BY cl.tipo_cliente
 ORDER BY cl.tipo_cliente;

-- -----------------------------------------------------------------------------
-- S4. Top 5 de las salas que solicitaron mayor cantidad de un vino determinado
--     mediante transferencias en los ultimos 15 dias.
-- Estrategia: transferencia con sus renglones, filtrando por fecha y por vino, y
-- suma por sala. Cuenta cualquier estado porque la consigna habla de lo solicitado,
-- aunque todavia no se haya procesado. El vino se busca por nombre y volumen, en
-- su aniada mas reciente.
-- -----------------------------------------------------------------------------
\echo '== S4'
SELECT t.id_sala, SUM(r.cantidad) AS botellas
  FROM transferencia t
  JOIN renglon_transferencia r ON r.nro_solicitud = t.nro_solicitud
 WHERE t.fecha_confeccion >= CURRENT_DATE - 15
   AND r.cod_vino = (SELECT cod_vino
                       FROM vino
                      WHERE nombre = :'vino' AND volumen_ml = :vol
                      ORDER BY anada DESC
                      LIMIT 1)
 GROUP BY t.id_sala
 ORDER BY botellas DESC, t.id_sala
 LIMIT 5;

-- -----------------------------------------------------------------------------
-- S5. Listado de las salas con menor cantidad de transferencias pendientes (no
--     procesadas).
-- Estrategia: LEFT JOIN desde sala_venta, porque una sala sin pendientes es
-- justamente la que tiene menos: con un JOIN comun desapareceria. El filtro del
-- estado va en el ON y no en el WHERE, que descartaria esas salas. COUNT cuenta
-- una columna de transferencia, asi da 0 y no 1. HAVING contra el MIN muestra
-- todas las empatadas.
-- -----------------------------------------------------------------------------
\echo '== S5'
SELECT s.id_sala, s.calle, s.numero, COUNT(t.nro_solicitud) AS pendientes
  FROM sala_venta s
  LEFT JOIN transferencia t ON t.id_sala = s.id_sala
                           AND t.estado <> 'procesado'
 GROUP BY s.id_sala, s.calle, s.numero
HAVING COUNT(t.nro_solicitud) = (SELECT MIN(x.pendientes)
                                   FROM (SELECT COUNT(t2.nro_solicitud) AS pendientes
                                           FROM sala_venta s2
                                           LEFT JOIN transferencia t2 ON t2.id_sala = s2.id_sala
                                                                     AND t2.estado <> 'procesado'
                                          GROUP BY s2.id_sala) x)
 ORDER BY s.id_sala;

-- -----------------------------------------------------------------------------
-- S6. Para una sala determinada, los vinos sin stock en la sala pero con stock
--     en el deposito central.
-- Estrategia: se parte del deposito (cantidad > 0) y se usa NOT EXISTS de una fila
-- de la sala con cantidad > 0. Asi entran los dos casos de "sin stock": que no
-- haya fila en stock_sala o que la fila este en 0.
-- -----------------------------------------------------------------------------
\echo '== S6'
SELECT v.cod_vino, v.nombre, d.cantidad AS en_deposito
  FROM stock_deposito d
  JOIN vino v ON v.cod_vino = d.cod_vino
 WHERE d.cantidad > 0
   AND NOT EXISTS (SELECT 1
                     FROM stock_sala s
                    WHERE s.id_sala = :sala_s
                      AND s.cod_vino = d.cod_vino
                      AND s.cantidad > 0)
 ORDER BY v.cod_vino;

-- -----------------------------------------------------------------------------
-- S7. Cual es la empresa de transporte con mayor actividad en el ultimo mes?
-- Estrategia: se cuentan los ingresos del mes por transportista. HAVING contra el
-- MAX muestra todos los empatados: no se puede poner MAX(COUNT(*)) directo, asi
-- que el conteo va en una subconsulta en el FROM.
-- -----------------------------------------------------------------------------
\echo '== S7'
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
 ORDER BY t.cod_transporte;

-- -----------------------------------------------------------------------------
-- S8. Monto total de ventas por sala en el ultimo trimestre, en orden descendente.
-- Estrategia: suma de comprobante.total por sala, sin tocar los renglones: para eso
-- se guarda el total en la cabecera. Los JOIN traen la direccion y la localidad.
-- Con JOIN comun solo aparecen las salas que vendieron.
-- -----------------------------------------------------------------------------
\echo '== S8'
SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad, SUM(c.total) AS total_ventas
  FROM comprobante c
  JOIN sala_venta s ON s.id_sala = c.id_sala
  JOIN localidad l ON l.id_localidad = s.id_localidad
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY s.id_sala, s.calle, s.numero, l.nombre
 ORDER BY total_ventas DESC;

-- -----------------------------------------------------------------------------
-- S9. Ficha de un vino: cepas con sus porcentajes, bodega elaboradora, maridajes
--     y stock total (deposito mas salas).
-- Estrategia: cepas y maridajes van en subconsultas con string_agg. Si fueran
-- JOIN en la consulta principal se multiplicarian entre si (2 cepas por 3
-- maridajes darian 6 filas). El stock sale de la vista v_stock_total_vino, para no
-- repetir ese calculo. \x muestra las columnas una debajo de la otra.
-- -----------------------------------------------------------------------------
\echo '== S9'
\x on
SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion, v.precio,
       b.razon_social AS bodega,
       (SELECT string_agg(ce.nombre || ' ' || co.porcentaje || '%', ', ')
          FROM composicion co
          JOIN cepa ce ON ce.id_cepa = co.id_cepa
         WHERE co.cod_vino = v.cod_vino) AS cepas,
       (SELECT string_agg(m.nombre, ', ')
          FROM vino_maridaje vm
          JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
         WHERE vm.cod_vino = v.cod_vino) AS maridajes,
       st.en_deposito, st.en_salas, st.total AS stock_total
  FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega
  JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino
 WHERE v.nombre = :'vino' AND v.volumen_ml = :vol
 ORDER BY v.anada DESC
 LIMIT 1;
\x off

-- -----------------------------------------------------------------------------
-- S10. Rendimiento en kg por hectarea de cada parcela y campania, e identificar
--      las parcelas que rinden menos que el promedio de su finca.
-- Estrategia: el rendimiento no se guarda: es kilos / superficie, por eso se une
-- lote_uva con parcela. La subconsulta correlacionada calcula el promedio de la
-- misma finca en la misma campania, para cada fila de afuera. Se compara dentro
-- de la campania porque el clima cambia de un anio a otro.
-- -----------------------------------------------------------------------------
\echo '== S10'
SELECT l.id_finca, l.nro_parcela, l.campania,
       ROUND(l.kilos / p.superficie_ha, 2) AS rendimiento,
       ROUND((SELECT AVG(l2.kilos / p2.superficie_ha)
                FROM lote_uva l2
                JOIN parcela p2 ON p2.id_finca = l2.id_finca
                               AND p2.nro_parcela = l2.nro_parcela
               WHERE l2.id_finca = l.id_finca
                 AND l2.campania = l.campania), 2) AS promedio_finca
  FROM lote_uva l
  JOIN parcela p ON p.id_finca = l.id_finca
                AND p.nro_parcela = l.nro_parcela
 WHERE l.kilos / p.superficie_ha < (SELECT AVG(l2.kilos / p2.superficie_ha)
                                      FROM lote_uva l2
                                      JOIN parcela p2 ON p2.id_finca = l2.id_finca
                                                     AND p2.nro_parcela = l2.nro_parcela
                                     WHERE l2.id_finca = l.id_finca
                                       AND l2.campania = l.campania)
 ORDER BY l.id_finca, l.campania, l.nro_parcela;

-- -----------------------------------------------------------------------------
-- S11a. Ranking de vinos dentro de cada sala por botellas vendidas.
-- Estrategia: x tiene las botellas por sala y vino. El puesto es 1 + la cantidad
-- de vinos de esa misma sala que vendieron mas (subconsulta correlacionada). Dos
-- vinos empatados quedan en el mismo puesto. Se muestran los 5 primeros por sala.
-- Costo: recalcula las ventas de la sala por cada fila de x. Con los 125.135
-- renglones de la carga tarda entre 2 y 3 minutos, y los indices no la mejoran.
-- -----------------------------------------------------------------------------
\echo '== S11a'
SELECT t.id_sala, t.puesto, t.cod_vino, v.nombre, t.botellas
  FROM (SELECT x.id_sala, x.cod_vino, x.botellas,
               1 + (SELECT COUNT(*)
                      FROM (SELECT r2.cod_vino, SUM(r2.cantidad) AS botellas
                              FROM comprobante c2
                              JOIN renglon_comprobante r2 ON r2.nro_comprobante = c2.nro
                             WHERE c2.id_sala = x.id_sala
                             GROUP BY r2.cod_vino) y
                     WHERE y.botellas > x.botellas) AS puesto
          FROM (SELECT c.id_sala, r.cod_vino, SUM(r.cantidad) AS botellas
                  FROM comprobante c
                  JOIN renglon_comprobante r ON r.nro_comprobante = c.nro
                 GROUP BY c.id_sala, r.cod_vino) x) t
  JOIN vino v ON v.cod_vino = t.cod_vino
 WHERE t.puesto <= 5
 ORDER BY t.id_sala, t.puesto, t.cod_vino;

-- -----------------------------------------------------------------------------
-- S11b. Ventas acumuladas mensuales por sala.
-- Estrategia: m tiene el total de cada sala y mes del ultimo anio; date_trunc lleva
-- cada fecha al primer dia del mes. El acumulado es la suma de los comprobantes de
-- esa sala hasta ese mes inclusive (subconsulta correlacionada).
-- -----------------------------------------------------------------------------
\echo '== S11b'
SELECT m.id_sala, m.mes, m.total_mes,
       (SELECT SUM(c2.total)
          FROM comprobante c2
         WHERE c2.id_sala = m.id_sala
           AND c2.fecha >= CURRENT_DATE - INTERVAL '1 year'
           AND date_trunc('month', c2.fecha)::date <= m.mes) AS acumulado
  FROM (SELECT id_sala, date_trunc('month', fecha)::date AS mes, SUM(total) AS total_mes
          FROM comprobante
         WHERE fecha >= CURRENT_DATE - INTERVAL '1 year'
         GROUP BY id_sala, date_trunc('month', fecha)::date) m
 ORDER BY m.id_sala, m.mes;

-- -----------------------------------------------------------------------------
-- S12a. Clientes que compraron todos los vinos de una bodega determinada.
-- Estrategia: division relacional, como S2: un cliente va en el resultado si NO
-- existe un vino de la bodega que el NO haya comprado.
-- -----------------------------------------------------------------------------
\echo '== S12a'
SELECT cl.id_cliente, cl.nombre_razon_social
  FROM cliente cl
 WHERE NOT EXISTS (SELECT 1
                     FROM vino v
                    WHERE v.cuit_bodega IN (SELECT cuit FROM bodega WHERE razon_social = :'bodega')
                      AND NOT EXISTS (SELECT 1
                                        FROM comprobante c
                                        JOIN renglon_comprobante r ON r.nro_comprobante = c.nro
                                       WHERE c.id_cliente = cl.id_cliente
                                         AND r.cod_vino = v.cod_vino))
 ORDER BY cl.id_cliente;

-- -----------------------------------------------------------------------------
-- S12b. Clientes que nunca compraron ningun vino tinto.
-- Estrategia: anti-join con NOT EXISTS: el cliente va si no existe una compra suya
-- de un vino tinto. Entran tambien los que nunca compraron nada. Como son muchos,
-- se muestra la cantidad total y los primeros 20.
-- -----------------------------------------------------------------------------
\echo '== S12b'
SELECT COUNT(*) AS clientes_sin_tinto
  FROM cliente cl
 WHERE NOT EXISTS (SELECT 1
                     FROM comprobante c
                     JOIN renglon_comprobante r ON r.nro_comprobante = c.nro
                     JOIN vino v ON v.cod_vino = r.cod_vino
                    WHERE c.id_cliente = cl.id_cliente
                      AND v.tipo = 'tinto');

SELECT cl.id_cliente, cl.nombre_razon_social
  FROM cliente cl
 WHERE NOT EXISTS (SELECT 1
                     FROM comprobante c
                     JOIN renglon_comprobante r ON r.nro_comprobante = c.nro
                     JOIN vino v ON v.cod_vino = r.cod_vino
                    WHERE c.id_cliente = cl.id_cliente
                      AND v.tipo = 'tinto')
 ORDER BY cl.id_cliente
 LIMIT 20;
