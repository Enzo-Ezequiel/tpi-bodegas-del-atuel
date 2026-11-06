-- =============================================================================
-- db/seed/control.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Consultas de control despues de la carga (etapa 3). Salvo la primera, todas
-- tienen que dar 0. Las corre cargar.py al terminar; tambien se pueden correr
-- solas con psql (ver db/seed/README.md).
-- =============================================================================

-- 1. Cuantas filas tiene cada una de las 30 tablas, de mayor a menor.
\echo '== 1. Filas por tabla'
SELECT tabla, filas
  FROM (SELECT 'departamento' AS tabla, COUNT(*) AS filas FROM departamento
        UNION ALL SELECT 'localidad', COUNT(*) FROM localidad
        UNION ALL SELECT 'cepa', COUNT(*) FROM cepa
        UNION ALL SELECT 'maridaje', COUNT(*) FROM maridaje
        UNION ALL SELECT 'bodega', COUNT(*) FROM bodega
        UNION ALL SELECT 'transportista', COUNT(*) FROM transportista
        UNION ALL SELECT 'transportista_localidad', COUNT(*) FROM transportista_localidad
        UNION ALL SELECT 'sala_venta', COUNT(*) FROM sala_venta
        UNION ALL SELECT 'empleado', COUNT(*) FROM empleado
        UNION ALL SELECT 'finca', COUNT(*) FROM finca
        UNION ALL SELECT 'parcela', COUNT(*) FROM parcela
        UNION ALL SELECT 'lote_uva', COUNT(*) FROM lote_uva
        UNION ALL SELECT 'analisis_calidad', COUNT(*) FROM analisis_calidad
        UNION ALL SELECT 'vino', COUNT(*) FROM vino
        UNION ALL SELECT 'composicion', COUNT(*) FROM composicion
        UNION ALL SELECT 'vino_maridaje', COUNT(*) FROM vino_maridaje
        UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
        UNION ALL SELECT 'socio', COUNT(*) FROM socio
        UNION ALL SELECT 'distribuidor', COUNT(*) FROM distribuidor
        UNION ALL SELECT 'exportador', COUNT(*) FROM exportador
        UNION ALL SELECT 'permiso_exportacion', COUNT(*) FROM permiso_exportacion
        UNION ALL SELECT 'comprobante', COUNT(*) FROM comprobante
        UNION ALL SELECT 'renglon_comprobante', COUNT(*) FROM renglon_comprobante
        UNION ALL SELECT 'ingreso', COUNT(*) FROM ingreso
        UNION ALL SELECT 'renglon_ingreso', COUNT(*) FROM renglon_ingreso
        UNION ALL SELECT 'transferencia', COUNT(*) FROM transferencia
        UNION ALL SELECT 'renglon_transferencia', COUNT(*) FROM renglon_transferencia
        UNION ALL SELECT 'stock_sala', COUNT(*) FROM stock_sala
        UNION ALL SELECT 'stock_deposito', COUNT(*) FROM stock_deposito
        UNION ALL SELECT 'auditoria_precio', COUNT(*) FROM auditoria_precio) t
 ORDER BY filas DESC, tabla;

-- 2. RN-09: ningun stock negativo. El CHECK ya lo impide; el control confirma
--    que la carga no lo esquivo.
\echo '== 2. Stock negativo (tiene que dar 0 y 0)'
SELECT (SELECT COUNT(*) FROM stock_sala WHERE cantidad < 0)     AS stock_sala_negativo,
       (SELECT COUNT(*) FROM stock_deposito WHERE cantidad < 0) AS stock_deposito_negativo;

-- 3. RN-08: el total guardado en la cabecera coincide con la suma de los
--    renglones. Los importes se calcularon en SQL con los triggers apagados:
--    este control prueba que la cuenta dio lo mismo que haria el trigger.
\echo '== 3. Comprobantes con total distinto de fn_total_comprobante (tiene que dar 0)'
SELECT COUNT(*) AS comprobantes_mal_totalizados
  FROM comprobante c
 WHERE c.total <> fn_total_comprobante(c.nro);

-- 4. Un comprobante sin renglones es una venta vacia.
\echo '== 4. Comprobantes sin renglones (tiene que dar 0)'
SELECT COUNT(*) AS comprobantes_sin_renglones
  FROM comprobante c
 WHERE NOT EXISTS (SELECT 1 FROM renglon_comprobante r WHERE r.nro_comprobante = c.nro);

-- 5. RN-05: el trigger T7 solo impide pasar de 100; que lleguen exactamente a
--    100 se controla con la vista.
\echo '== 5. Vinos con la composicion incompleta (tiene que dar 0)'
SELECT COUNT(*) AS vinos_composicion_incompleta FROM v_vinos_composicion_incompleta;

-- 6. Jerarquia total: todo cliente tiene su fila en el subtipo que dice su
--    discriminador.
\echo '== 6. Clientes sin fila en su subtipo (tiene que dar 0)'
SELECT COUNT(*) AS clientes_sin_subtipo
  FROM cliente cl
 WHERE (cl.tipo_cliente = 'socio'
        AND NOT EXISTS (SELECT 1 FROM socio s WHERE s.id_cliente = cl.id_cliente))
    OR (cl.tipo_cliente = 'distribuidor'
        AND NOT EXISTS (SELECT 1 FROM distribuidor d WHERE d.id_cliente = cl.id_cliente))
    OR (cl.tipo_cliente = 'exportador'
        AND NOT EXISTS (SELECT 1 FROM exportador e WHERE e.id_cliente = cl.id_cliente));

-- 7. La campania es el anio de la cosecha.
\echo '== 7. Lotes con campania distinta del anio de cosecha (tiene que dar 0)'
SELECT COUNT(*) AS lotes_campania_incorrecta
  FROM lote_uva
 WHERE campania <> EXTRACT(YEAR FROM fecha_cosecha);
