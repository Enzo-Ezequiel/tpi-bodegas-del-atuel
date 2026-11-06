-- =============================================================================
-- 008_indices.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Indices para las consultas de la seccion 8. PostgreSQL ya crea uno por cada
-- PRIMARY KEY y UNIQUE, pero ninguno para las claves foraneas.
-- Las mediciones antes y despues estan en docs/rendimiento.md.
-- =============================================================================

-- Compuesto. S3: busca por sala (igualdad) y despues por fecha (rango).
-- La igualdad va primero: el indice salta a la sala y ahi las fechas estan en orden.
CREATE INDEX idx_comprobante_sala_fecha
    ON comprobante (id_sala, fecha);

-- BRIN. S8: filtra por fecha toda la red. La carga inserta los comprobantes por
-- fecha, que es cuando BRIN sirve: guarda el minimo y maximo de cada bloque y ocupa poco.
CREATE INDEX idx_comprobante_fecha_brin
    ON comprobante USING BRIN (fecha);

-- Sobre clave foranea. S4: buscar las transferencias de un vino.
-- La PK (nro_solicitud, cod_vino) no sirve: el vino es su segunda columna.
CREATE INDEX idx_renglon_transf_vino
    ON renglon_transferencia (cod_vino);

-- Parcial. S5: solo importan las transferencias sin procesar, que son muy pocas.
-- Indexa solo esas filas, asi es chico y casi no cuesta mantenerlo.
CREATE INDEX idx_transferencia_pendientes
    ON transferencia (id_sala)
    WHERE estado <> 'procesado';

-- Sobre clave foranea. Buscar las ventas de un vino, sin recorrer todos los renglones.
-- La PK (nro_comprobante, cod_vino) no sirve: el vino es su segunda columna.
-- S2 y S12a no lo usan: leen todos los renglones y conviene el Hash Join.
CREATE INDEX idx_renglon_venta_vino
    ON renglon_comprobante (cod_vino);
