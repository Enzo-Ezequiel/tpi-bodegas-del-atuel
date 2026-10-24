-- =============================================================================
-- 003_funciones.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Funciones de calculo que usan los triggers (005_triggers.sql) y las
-- consultas de la seccion 8. Estan aca para que cada calculo se escriba una
-- sola vez y la API no tenga que repetirlo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_descuento_cliente
-- RN-06: el descuento depende del tipo de cliente.
-- Parametro: el tipo de cliente. Devuelve el porcentaje (10, 20 o 30), en la
-- misma escala que cliente.descuento.
-- Se usa para el valor inicial del descuento al dar de alta un cliente y en U1.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_tipo tipo_cliente)
RETURNS NUMERIC AS $$
BEGIN
    IF p_tipo = 'socio' THEN
        RETURN 10;
    ELSIF p_tipo = 'distribuidor' THEN
        RETURN 20;
    ELSIF p_tipo = 'exportador' THEN
        RETURN 30;
    END IF;

    -- Solo se llega aca si el tipo vino vacio (el ENUM no admite otros valores)
    RAISE EXCEPTION 'No se puede calcular el descuento: falta el tipo de cliente (RN-06)';
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- fn_stock_sala
-- RN-09: cuantas botellas de un vino hay en una sala.
-- Parametros: la sala y el vino. Devuelve 0 si la sala nunca tuvo ese vino
-- (no hay fila en stock_sala), asi quien la llama no tiene que tratar el NULL.
-- Se usa en el trigger que valida el stock antes de vender y en S6.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_sala(p_sala INTEGER, p_vino INTEGER)
RETURNS INTEGER AS $$
DECLARE
    v_cantidad INTEGER;
BEGIN
    SELECT cantidad INTO v_cantidad
      FROM stock_sala
     WHERE id_sala = p_sala AND cod_vino = p_vino;

    IF v_cantidad IS NULL THEN
        RETURN 0;
    END IF;
    RETURN v_cantidad;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- fn_total_comprobante
-- RN-08: el total del comprobante es la suma de sus renglones con el
-- descuento aplicado. Cada renglon ya guarda su subtotal con el descuento
-- restado, asi que alcanza con sumarlos.
-- Parametro: el numero de comprobante. Devuelve 0 si todavia no tiene renglones.
-- Se usa en el trigger que actualiza la cabecera y en U1.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro INTEGER)
RETURNS NUMERIC AS $$
DECLARE
    v_total NUMERIC(14,2);
BEGIN
    SELECT SUM(subtotal) INTO v_total
      FROM renglon_comprobante
     WHERE nro_comprobante = p_nro;

    IF v_total IS NULL THEN
        RETURN 0;
    END IF;
    RETURN v_total;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- fn_antiguedad_anios
-- Antiguedad de un empleado en anios completos. No se guarda en la tabla
-- porque cambia todos los dias (es un atributo derivado).
-- Parametro: la fecha de ingreso. age() devuelve el tiempo transcurrido hasta
-- hoy y EXTRACT toma solo los anios.
-- Se usa en U2 (mas de 5 anios) y en D3 (menos de 2 anios).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha_ingreso DATE)
RETURNS INTEGER AS $$
BEGIN
    RETURN EXTRACT(YEAR FROM age(CURRENT_DATE, p_fecha_ingreso));
END;
$$ LANGUAGE plpgsql;
