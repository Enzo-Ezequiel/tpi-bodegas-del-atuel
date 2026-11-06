-- =============================================================================
-- consultas/delete.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Consultas de la seccion 8.3 del enunciado.
-- Los parametros estan en los \set de abajo: cambiar ahi para probar otros valores.
-- Como se corre: con la carga de la etapa 3 hecha, psql -U postgres -d bodegas_atuel -f consultas/delete.sql
-- Las lineas Resultado son de la carga completa con fecha de referencia 2026-11-06.
--
-- Cada sentencia va en BEGIN / control previo / sentencia / control posterior /
-- ROLLBACK: se ve el antes y el despues, y la base queda igual.
-- :ROW_COUNT es una variable de psql con las filas que afecto la ultima sentencia.
-- =============================================================================
\set QUIET on
\set ON_ERROR_ROLLBACK on
\set loc_d 'San Rafael'

-- -----------------------------------------------------------------------------
-- D1. Borrar los comprobantes con mas de 5 anios de antiguedad asociados a
--     clientes socios del club.
-- Estrategia: subconsulta con los clientes socios. Los renglones se borran solos
-- por ON DELETE CASCADE: un renglon no existe sin su comprobante. Los dos
-- controles cuentan los renglones para que se vea la cascada.
-- Limite conocido: borrar una venta no devuelve el stock (docs/03, seccion 7).
-- Resultado: 4.908 comprobantes. Cascada sobre renglon_comprobante: se borran 12.303
-- renglones (de 125.135 a 112.832). No dispara triggers: T1 y T2 son de INSERT.
-- -----------------------------------------------------------------------------
\echo '== D1'
BEGIN;
-- Control previo: comprobantes y renglones que se van a borrar
SELECT COUNT(DISTINCT c.nro) AS comprobantes, COUNT(r.cod_vino) AS renglones
  FROM comprobante c
  LEFT JOIN renglon_comprobante r ON r.nro_comprobante = c.nro
 WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
   AND c.id_cliente IN (SELECT id_cliente FROM cliente WHERE tipo_cliente = 'socio');

SELECT COUNT(*) AS renglones_en_total FROM renglon_comprobante;

DELETE FROM comprobante
 WHERE fecha < CURRENT_DATE - INTERVAL '5 years'
   AND id_cliente IN (SELECT id_cliente FROM cliente WHERE tipo_cliente = 'socio');
\echo '   comprobantes borrados:' :ROW_COUNT

-- Control posterior
SELECT COUNT(DISTINCT c.nro) AS comprobantes, COUNT(r.cod_vino) AS renglones
  FROM comprobante c
  LEFT JOIN renglon_comprobante r ON r.nro_comprobante = c.nro
 WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
   AND c.id_cliente IN (SELECT id_cliente FROM cliente WHERE tipo_cliente = 'socio');

SELECT COUNT(*) AS renglones_en_total FROM renglon_comprobante;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- D2. Eliminar las cepas que no componen ningun vino ni estan plantadas en
--     ninguna parcela.
-- Estrategia: doble NOT EXISTS: la cepa no aparece en composicion y tampoco en
-- parcela. Las dos FK son RESTRICT, asi que con cualquier otra cepa daria error.
-- Resultado: 3 cepas: Petit Verdot, Viognier y Pinot Gris. No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== D2'
BEGIN;
-- Control previo
SELECT c.id_cepa, c.nombre
  FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa)
 ORDER BY c.id_cepa;

DELETE FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior: ya no queda ninguna
SELECT COUNT(*) AS cepas_sin_uso
  FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);
ROLLBACK;

-- -----------------------------------------------------------------------------
-- D3. La sala de una localidad determinada fue dada de baja: eliminar los
--     empleados de esa sala que trabajaron menos de dos anios.
-- Estrategia: subconsulta con las salas de la localidad, buscada por nombre, y
-- fn_antiguedad_anios para la antiguedad, que no se guarda porque cambia todos
-- los dias. Cuenta anios completos: < 2 son 0 o 1 anio.
-- Resultado: 2 empleados. No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== D3'
BEGIN;
-- Control previo
SELECT e.cuit, e.nombre, e.fecha_ingreso, e.id_sala
  FROM empleado e
 WHERE e.id_sala IN (SELECT s.id_sala
                       FROM sala_venta s
                       JOIN localidad l ON l.id_localidad = s.id_localidad
                      WHERE l.nombre = :'loc_d')
   AND fn_antiguedad_anios(e.fecha_ingreso) < 2
 ORDER BY e.cuit;

DELETE FROM empleado
 WHERE id_sala IN (SELECT s.id_sala
                     FROM sala_venta s
                     JOIN localidad l ON l.id_localidad = s.id_localidad
                    WHERE l.nombre = :'loc_d')
   AND fn_antiguedad_anios(fecha_ingreso) < 2;
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior: ya no queda ninguno
SELECT COUNT(*) AS empleados_que_quedan
  FROM empleado e
 WHERE e.id_sala IN (SELECT s.id_sala
                       FROM sala_venta s
                       JOIN localidad l ON l.id_localidad = s.id_localidad
                      WHERE l.nombre = :'loc_d')
   AND fn_antiguedad_anios(e.fecha_ingreso) < 2;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- D4. Borrar los clientes socios que nunca compraron y se dieron de alta hace
--     mas de 5 anios.
-- Estrategia: NOT EXISTS para "nunca compraron". Se borra en cliente: la fila de
-- socio se va en cascada, porque el subtipo es parte del cliente. Si tuviera
-- comprobantes la FK no lo dejaria (RESTRICT), pero el NOT EXISTS ya los excluye.
-- Resultado: 214 clientes. Cascada sobre socio (de 8.400 a 8.186). No dispara
-- triggers.
-- -----------------------------------------------------------------------------
\echo '== D4'
BEGIN;
-- Control previo
SELECT cl.id_cliente, cl.nombre_razon_social, cl.fecha_alta
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente)
 ORDER BY cl.id_cliente;

SELECT COUNT(*) AS filas_en_socio FROM socio;

DELETE FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior: la tabla socio tambien bajo, por la cascada
SELECT COUNT(*) AS filas_en_socio FROM socio;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- D5. Eliminar los ingresos en estado procesado de hace mas de 365 dias.
-- Estrategia: DELETE con dos condiciones sobre el ingreso. Los renglones se borran
-- en cascada. El trigger T4 bloquea tocar renglones de un documento procesado,
-- pero cuando se borra el ingreso entero lo deja pasar: al llegar al renglon, la
-- cabecera ya no existe. El stock del deposito no cambia.
-- Resultado: 2.104 ingresos. Cascada sobre renglon_ingreso: se borran 6.097 renglones
-- (de 7.267 a 1.170). Dispara el trigger T4, que no lo impide.
-- -----------------------------------------------------------------------------
\echo '== D5'
BEGIN;
-- Control previo: ingresos y renglones que se van a borrar
SELECT COUNT(DISTINCT i.cod_ingreso) AS ingresos, COUNT(r.cod_vino) AS renglones
  FROM ingreso i
  LEFT JOIN renglon_ingreso r ON r.cod_ingreso = i.cod_ingreso
 WHERE i.estado = 'procesado'
   AND i.fecha < CURRENT_DATE - 365;

SELECT COUNT(*) AS renglones_en_total FROM renglon_ingreso;

DELETE FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_DATE - 365;
\echo '   ingresos borrados:' :ROW_COUNT

-- Control posterior
SELECT COUNT(DISTINCT i.cod_ingreso) AS ingresos, COUNT(r.cod_vino) AS renglones
  FROM ingreso i
  LEFT JOIN renglon_ingreso r ON r.cod_ingreso = i.cod_ingreso
 WHERE i.estado = 'procesado'
   AND i.fecha < CURRENT_DATE - 365;

SELECT COUNT(*) AS renglones_en_total FROM renglon_ingreso;
ROLLBACK;

-- -----------------------------------------------------------------------------
-- D6. Borrar los clientes socios sin compras que viven en una localidad
--     especifica.
-- Estrategia: igual que D4, pero el filtro es la localidad, buscada por nombre.
-- Resultado: 70 clientes. Cascada sobre socio. No dispara triggers.
-- -----------------------------------------------------------------------------
\echo '== D6'
BEGIN;
-- Control previo
SELECT cl.id_cliente, cl.nombre_razon_social
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.id_localidad IN (SELECT id_localidad FROM localidad WHERE nombre = :'loc_d')
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente)
 ORDER BY cl.id_cliente;

DELETE FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.id_localidad IN (SELECT id_localidad FROM localidad WHERE nombre = :'loc_d')
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);
\echo '   filas afectadas:' :ROW_COUNT

-- Control posterior: ya no queda ninguno
SELECT COUNT(*) AS socios_sin_compras_en_la_localidad
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.id_localidad IN (SELECT id_localidad FROM localidad WHERE nombre = :'loc_d')
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);
ROLLBACK;
