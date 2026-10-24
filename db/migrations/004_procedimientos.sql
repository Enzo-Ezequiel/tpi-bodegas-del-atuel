-- =============================================================================
-- 004_procedimientos.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Procedimientos que procesan ingresos y transferencias: validan, mueven el
-- stock y cambian el estado. La API los llama con CALL y no hace ninguno de
-- estos pasos por su cuenta.
--
-- Todo o nada: un CALL es una sola sentencia. Si en cualquier paso hay un
-- RAISE EXCEPTION o se viola una restriccion (por ejemplo stock >= 0),
-- PostgreSQL deshace todo lo que hizo el procedimiento. No queda nada a medias
-- aunque no escribamos BEGIN / COMMIT.
--
-- Cuando el vino puede no tener fila de stock todavia, se suma en dos pasos y
-- en este orden: primero UPDATE de los que ya tienen fila, despues INSERT de
-- los que faltan. Al reves, un vino nuevo se sumaria dos veces.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- sp_procesar_ingreso
-- RN-10: solo un ingreso terminado impacta en el deposito central, y una vez
-- impactado pasa a procesado.
-- Parametro: el codigo de ingreso.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_cod INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado     estado_documento;
    v_renglones  INTEGER;
BEGIN
    -- 1. El ingreso existe y esta terminado
    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = p_cod;

    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'El ingreso % no existe', p_cod;
    END IF;
    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'El ingreso % esta en estado %: solo se procesa si esta terminado (RN-10)',
            p_cod, v_estado;
    END IF;

    -- 2. Tiene renglones (procesar uno vacio no moveria nada)
    SELECT COUNT(*) INTO v_renglones FROM renglon_ingreso WHERE cod_ingreso = p_cod;

    IF v_renglones = 0 THEN
        RAISE EXCEPTION 'El ingreso % no tiene renglones', p_cod;
    END IF;

    -- 3a. Suma al deposito los vinos que ya tienen fila de stock
    UPDATE stock_deposito
       SET cantidad = cantidad + (SELECT r.cantidad
                                    FROM renglon_ingreso r
                                   WHERE r.cod_ingreso = p_cod
                                     AND r.cod_vino = stock_deposito.cod_vino)
     WHERE cod_vino IN (SELECT cod_vino FROM renglon_ingreso WHERE cod_ingreso = p_cod);

    -- 3b. Crea la fila de stock de los vinos que todavia no tenian
    INSERT INTO stock_deposito (cod_vino, cantidad)
    SELECT r.cod_vino, r.cantidad
      FROM renglon_ingreso r
     WHERE r.cod_ingreso = p_cod
       AND NOT EXISTS (SELECT 1 FROM stock_deposito d WHERE d.cod_vino = r.cod_vino);

    -- 4. Pasa a procesado (el trigger de estados permite terminado -> procesado)
    UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = p_cod;

    RAISE NOTICE 'Ingreso % procesado: % vinos sumados al deposito', p_cod, v_renglones;
END;
$$;

-- -----------------------------------------------------------------------------
-- sp_procesar_transferencia
-- RN-11: solo una transferencia terminada impacta en el stock. Al procesarla
-- se descuenta del deposito central y se suma a la sala. No se procesa si el
-- deposito no tiene stock suficiente.
-- Parametro: el numero de solicitud.
--
-- El stock se valida ANTES de tocar nada. No alcanza con el CHECK de
-- stock_deposito: si un vino no tiene fila en el deposito, el UPDATE no
-- encuentra nada que restar, no da error y la sala recibiria botellas que no
-- existen (el "Para pensar" del ejemplo A.6 del enunciado).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado      estado_documento;
    v_sala        INTEGER;
    v_renglones   INTEGER;
    v_vino        INTEGER;
    v_pedido      INTEGER;
    v_disponible  INTEGER;
BEGIN
    -- 1. La transferencia existe y esta terminada
    SELECT estado, id_sala INTO v_estado, v_sala
      FROM transferencia WHERE nro_solicitud = p_nro;

    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'La transferencia % no existe', p_nro;
    END IF;
    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'La transferencia % esta en estado %: solo se procesa si esta terminada (RN-11)',
            p_nro, v_estado;
    END IF;

    -- 2. Tiene renglones
    SELECT COUNT(*) INTO v_renglones FROM renglon_transferencia WHERE nro_solicitud = p_nro;

    IF v_renglones = 0 THEN
        RAISE EXCEPTION 'La transferencia % no tiene renglones', p_nro;
    END IF;

    -- 3. Busca algun vino sin stock suficiente en el deposito. El LEFT JOIN
    --    trae tambien los vinos sin fila en stock_deposito (disponible = 0).
    SELECT r.cod_vino, r.cantidad, COALESCE(d.cantidad, 0)
      INTO v_vino, v_pedido, v_disponible
      FROM renglon_transferencia r
      LEFT JOIN stock_deposito d ON d.cod_vino = r.cod_vino
     WHERE r.nro_solicitud = p_nro
       AND COALESCE(d.cantidad, 0) < r.cantidad
     ORDER BY r.cod_vino
     LIMIT 1;

    IF v_vino IS NOT NULL THEN
        RAISE EXCEPTION 'Stock insuficiente en el deposito del vino %: hay %, se piden % (RN-11)',
            v_vino, v_disponible, v_pedido;
    END IF;

    -- 4. Descuenta del deposito (ya sabemos que todos tienen fila y alcanza)
    UPDATE stock_deposito
       SET cantidad = cantidad - (SELECT r.cantidad
                                    FROM renglon_transferencia r
                                   WHERE r.nro_solicitud = p_nro
                                     AND r.cod_vino = stock_deposito.cod_vino)
     WHERE cod_vino IN (SELECT cod_vino FROM renglon_transferencia WHERE nro_solicitud = p_nro);

    -- 5a. Suma a la sala los vinos que ya tiene
    UPDATE stock_sala
       SET cantidad = cantidad + (SELECT r.cantidad
                                    FROM renglon_transferencia r
                                   WHERE r.nro_solicitud = p_nro
                                     AND r.cod_vino = stock_sala.cod_vino)
     WHERE id_sala = v_sala
       AND cod_vino IN (SELECT cod_vino FROM renglon_transferencia WHERE nro_solicitud = p_nro);

    -- 5b. Crea la fila de stock de los vinos que la sala no tenia
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    SELECT v_sala, r.cod_vino, r.cantidad
      FROM renglon_transferencia r
     WHERE r.nro_solicitud = p_nro
       AND NOT EXISTS (SELECT 1 FROM stock_sala s
                        WHERE s.id_sala = v_sala AND s.cod_vino = r.cod_vino);

    -- 6. Pasa a procesada
    UPDATE transferencia SET estado = 'procesado' WHERE nro_solicitud = p_nro;

    RAISE NOTICE 'Transferencia % procesada: % vinos enviados a la sala %', p_nro, v_renglones, v_sala;
END;
$$;
