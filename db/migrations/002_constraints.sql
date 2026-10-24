-- =============================================================================
-- 002_constraints.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Restricciones UNIQUE, CHECK y DEFAULT que completan el esquema de
-- 001_esquema.sql. Cada una indica la regla de negocio que protege.
--
-- Criterio: un CHECK sirve para reglas que se verifican mirando UNA sola fila
-- (precio > 0, vencimiento > emision). Si la regla necesita mirar otra tabla
-- o la fecha de hoy (stock suficiente, fecha de la transferencia, suma de los
-- porcentajes), no va aca: va en un trigger (005_triggers.sql).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- UNIQUE: claves candidatas que no son la clave primaria
-- -----------------------------------------------------------------------------

-- RN-04: una parcela se cosecha como maximo una vez por campania
ALTER TABLE lote_uva
    ADD CONSTRAINT uq_lote_parcela_campania UNIQUE (id_finca, nro_parcela, campania);

-- Un vino se distingue por nombre, aniada y presentacion (la PK es un codigo)
ALTER TABLE vino
    ADD CONSTRAINT uq_vino_nombre_anada_volumen UNIQUE (nombre, anada, volumen_ml);

-- La PK es el codigo de transporte, pero dos transportistas no comparten CUIT
ALTER TABLE transportista
    ADD CONSTRAINT uq_transportista_cuit UNIQUE (cuit);

-- La misma persona o empresa no se da de alta dos veces como cliente
ALTER TABLE cliente
    ADD CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, nro_documento);

-- -----------------------------------------------------------------------------
-- CHECK: reglas que se cumplen mirando una sola fila
-- -----------------------------------------------------------------------------

-- RN-01: el precio de un vino es siempre mayor que cero
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_precio CHECK (precio > 0);

-- RN-15: la graduacion esta entre 5 y 20
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_graduacion CHECK (graduacion BETWEEN 5 AND 20);

-- RN-07: el vencimiento es posterior a la emision (CHECK entre dos columnas)
ALTER TABLE permiso_exportacion
    ADD CONSTRAINT ck_permiso_fechas CHECK (fecha_vencimiento > fecha_emision);

-- RN-09: el stock nunca es negativo, ni en las salas ni en el deposito
ALTER TABLE stock_sala
    ADD CONSTRAINT ck_stock_sala_cantidad CHECK (cantidad >= 0);

ALTER TABLE stock_deposito
    ADD CONSTRAINT ck_stock_deposito_cantidad CHECK (cantidad >= 0);

-- RN-15: las cantidades de los renglones son positivas
ALTER TABLE renglon_comprobante
    ADD CONSTRAINT ck_renglon_comprobante_cantidad CHECK (cantidad > 0);

ALTER TABLE renglon_ingreso
    ADD CONSTRAINT ck_renglon_ingreso_cantidad CHECK (cantidad > 0);

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT ck_renglon_transferencia_cantidad CHECK (cantidad > 0);

-- RN-15: los kilos cosechados y las superficies son positivos
ALTER TABLE lote_uva
    ADD CONSTRAINT ck_lote_kilos CHECK (kilos > 0);

ALTER TABLE finca
    ADD CONSTRAINT ck_finca_superficie CHECK (superficie_ha > 0);

ALTER TABLE parcela
    ADD CONSTRAINT ck_parcela_superficie CHECK (superficie_ha > 0);

-- -----------------------------------------------------------------------------
-- DEFAULT: valores iniciales
-- -----------------------------------------------------------------------------

-- RN-10 y RN-11: todo ingreso y toda transferencia nacen en confeccion
ALTER TABLE ingreso
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE transferencia
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

-- Si no se indica, el cliente se da de alta hoy
ALTER TABLE cliente
    ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;

-- RN-08: los importes no se cargan a mano. El comprobante se crea en 0 y los
-- triggers de los renglones los van actualizando. Sin este DEFAULT no se podria
-- crear la cabecera, porque las tres columnas son NOT NULL.
ALTER TABLE comprobante
    ALTER COLUMN subtotal  SET DEFAULT 0,
    ALTER COLUMN descuento SET DEFAULT 0,
    ALTER COLUMN total     SET DEFAULT 0;
