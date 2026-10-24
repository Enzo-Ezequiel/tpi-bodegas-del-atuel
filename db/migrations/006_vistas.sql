-- =============================================================================
-- 006_vistas.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Vistas: consultas guardadas que se usan como si fueran tablas. Evitan
-- repetir los mismos JOIN y GROUP BY en las consultas, la API y el front.
--
-- Son vistas comunes, no materializadas: se calculan cada vez que se consultan,
-- asi que siempre muestran los datos actuales. Una materializada guarda el
-- resultado y queda vieja hasta que alguien ejecuta REFRESH MATERIALIZED VIEW
-- (por ejemplo, una venta nueva no apareceria en el tablero).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- v_stock_total_vino
-- Stock de cada vino en el deposito, en todas las salas y el total.
-- No se guarda en ninguna tabla porque se deduce de stock_deposito y
-- stock_sala (atributo derivado). Se usa en la ficha del vino (S9).
-- El LEFT JOIN trae tambien los vinos sin stock; COALESCE convierte el
-- "no hay fila" (NULL) en 0.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_stock_total_vino AS
SELECT v.cod_vino,
       v.nombre,
       v.anada,
       v.volumen_ml,
       COALESCE(d.cantidad, 0)                           AS en_deposito,
       COALESCE(s.cantidad, 0)                           AS en_salas,
       COALESCE(d.cantidad, 0) + COALESCE(s.cantidad, 0) AS total
  FROM vino v
  LEFT JOIN stock_deposito d ON d.cod_vino = v.cod_vino
  LEFT JOIN (SELECT cod_vino, SUM(cantidad) AS cantidad
               FROM stock_sala
              GROUP BY cod_vino) s ON s.cod_vino = v.cod_vino;

-- -----------------------------------------------------------------------------
-- v_ventas_mensuales_sala
-- Cantidad de comprobantes y monto vendido por sala, anio y mes.
-- Se usa en S8, S11 y en el tablero del front.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ventas_mensuales_sala AS
SELECT s.id_sala,
       l.nombre                    AS localidad,
       EXTRACT(YEAR FROM c.fecha)  AS anio,
       EXTRACT(MONTH FROM c.fecha) AS mes,
       COUNT(*)                    AS comprobantes,
       SUM(c.total)                AS total_vendido
  FROM comprobante c
  JOIN sala_venta s ON s.id_sala = c.id_sala
  JOIN localidad l ON l.id_localidad = s.id_localidad
 GROUP BY s.id_sala, l.nombre, anio, mes;

-- -----------------------------------------------------------------------------
-- v_documentos_pendientes
-- Ingresos y transferencias que todavia no se procesaron, en una sola lista.
-- UNION ALL junta dos SELECT con las mismas columnas. Un ingreso no tiene sala
-- y una transferencia no tiene bodega: esa columna va en NULL, con el tipo
-- indicado para que las dos partes coincidan.
-- Se usa en S5 (salas con menos transferencias pendientes).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_documentos_pendientes AS
SELECT 'ingreso'          AS tipo,
       i.cod_ingreso      AS numero,
       i.fecha,
       i.estado,
       NULL::INTEGER      AS id_sala,
       i.cuit_bodega
  FROM ingreso i
 WHERE i.estado <> 'procesado'
UNION ALL
SELECT 'transferencia'    AS tipo,
       t.nro_solicitud    AS numero,
       t.fecha_confeccion AS fecha,
       t.estado,
       t.id_sala,
       NULL::CHAR(11)     AS cuit_bodega
  FROM transferencia t
 WHERE t.estado <> 'procesado';

-- -----------------------------------------------------------------------------
-- v_vinos_composicion_incompleta
-- RN-05: vinos cuyos porcentajes de corte no suman 100 (0 si no tienen cepas
-- cargadas). Complementa al trigger T7, que solo impide pasar de 100: lo que
-- falta para llegar a 100 se detecta aca.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_vinos_composicion_incompleta AS
SELECT v.cod_vino,
       v.nombre,
       COALESCE(SUM(c.porcentaje), 0) AS suma_porcentajes
  FROM vino v
  LEFT JOIN composicion c ON c.cod_vino = v.cod_vino
 GROUP BY v.cod_vino, v.nombre
HAVING COALESCE(SUM(c.porcentaje), 0) <> 100;
