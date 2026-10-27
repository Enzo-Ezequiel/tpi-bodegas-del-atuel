-- =============================================================================
-- 005_triggers.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Triggers que protegen las reglas que un CHECK no puede cubrir: las que miran
-- otras filas, otras tablas o la fecha de hoy.
--
-- Convencion: la funcion que ejecuta el trigger empieza con tf_ y el trigger
-- con trg_. Cada bloque indica la regla de negocio que protege.
--
--   T1  trg_renglon_venta_validar      BEFORE INSERT renglon_comprobante  RN-09, RN-08
--   T2  trg_renglon_venta_actualizar   AFTER  INSERT renglon_comprobante  RN-09, RN-08
--   T3  trg_ingreso_estado             BEFORE UPDATE ingreso              RN-10
--       trg_transferencia_estado       BEFORE UPDATE transferencia        RN-11
--   T4  trg_renglon_ingreso_bloqueo    BEFORE INS/UPD/DEL renglon_ingreso RN-12
--       trg_renglon_transf_bloqueo     BEFORE INS/UPD/DEL renglon_transf. RN-12
--   T5  trg_transferencia_fecha        BEFORE INSERT/UPDATE transferencia RN-11
--   T6  trg_vino_auditar_precio        AFTER  UPDATE vino                 RN-13
--   T7  trg_composicion_suma           AFTER  INSERT/UPDATE composicion   RN-05
--   T8  trg_cliente_descuento          BEFORE INSERT cliente              RN-06
--
-- BEFORE se usa cuando hay que rechazar la operacion o modificar la fila antes
-- de guardarla (NEW). AFTER se usa cuando hay que tocar otras tablas una vez
-- que la fila ya quedo guardada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T1. RN-09 y RN-08: validar el stock y completar el renglon de venta
-- Antes de guardar el renglon: si la sala no tiene stock suficiente, rechaza la
-- venta. Si alcanza, completa precio_unitario, descuento y subtotal: no se
-- cargan a mano. Tiene que ser BEFORE porque modifica NEW.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tf_validar_renglon_venta()
RETURNS TRIGGER AS $$
DECLARE
    v_sala               INTEGER;
    v_descuento_cliente  NUMERIC;
    v_precio             NUMERIC;
    v_stock              INTEGER;
BEGIN
    -- Sala del comprobante y porcentaje de descuento de su cliente
    SELECT c.id_sala, cl.descuento INTO v_sala, v_descuento_cliente
      FROM comprobante c
      JOIN cliente cl ON cl.id_cliente = c.id_cliente
     WHERE c.nro = NEW.nro_comprobante;

    IF v_sala IS NULL THEN
        RAISE EXCEPTION 'El comprobante % no existe', NEW.nro_comprobante;
    END IF;

    v_stock := fn_stock_sala(v_sala, NEW.cod_vino);
    IF v_stock < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente del vino % en la sala %: hay %, se piden % (RN-09)',
            NEW.cod_vino, v_sala, v_stock, NEW.cantidad;
    END IF;

    -- El precio se copia del vino: queda fijo aunque despues cambie
    SELECT precio INTO v_precio FROM vino WHERE cod_vino = NEW.cod_vino;

    NEW.precio_unitario := v_precio;
    NEW.descuento := ROUND(NEW.cantidad * v_precio * v_descuento_cliente / 100, 2);
    NEW.subtotal := NEW.cantidad * v_precio - NEW.descuento;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_renglon_venta_validar
BEFORE INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION tf_validar_renglon_venta();

-- -----------------------------------------------------------------------------
-- T2. RN-09 y RN-08: descontar el stock y actualizar los importes del comprobante
-- Despues de guardar el renglon: resta las botellas del stock de la sala y
-- recalcula subtotal, descuento y total de la cabecera. Es AFTER porque toca
-- otras tablas y solo tiene sentido cuando el renglon ya quedo guardado.
-- Limite conocido: solo el INSERT mueve stock. Una venta emitida no se edita,
-- asi que borrar o modificar un renglon no devuelve las botellas.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tf_actualizar_venta()
RETURNS TRIGGER AS $$
DECLARE
    v_sala INTEGER;
BEGIN
    SELECT id_sala INTO v_sala FROM comprobante WHERE nro = NEW.nro_comprobante;

    -- El CHECK cantidad >= 0 de stock_sala es la ultima barrera si algo falla
    UPDATE stock_sala
       SET cantidad = cantidad - NEW.cantidad
     WHERE id_sala = v_sala AND cod_vino = NEW.cod_vino;

    UPDATE comprobante
       SET subtotal = (SELECT SUM(cantidad * precio_unitario)
                         FROM renglon_comprobante
                        WHERE nro_comprobante = NEW.nro_comprobante),
           descuento = (SELECT SUM(descuento)
                          FROM renglon_comprobante
                         WHERE nro_comprobante = NEW.nro_comprobante),
           total = fn_total_comprobante(NEW.nro_comprobante)
     WHERE nro = NEW.nro_comprobante;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_renglon_venta_actualizar
AFTER INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION tf_actualizar_venta();

-- -----------------------------------------------------------------------------
-- T3. RN-10 y RN-11: los estados solo avanzan
-- Permite en_confeccion -> terminado y terminado -> procesado. Cualquier otro
-- cambio (saltear un paso o volver atras) se rechaza. La misma funcion sirve
-- para ingresos y transferencias porque las dos tablas tienen columna estado.
-- El WHEN hace que el trigger solo se dispare si el estado cambio.
-- Limite conocido: el trigger controla el orden, pero no sabe si el paso a
-- procesado lo hizo el procedimiento (que mueve el stock) o un UPDATE a mano.
-- Lo cubre que la API solo use los procedimientos de 004.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tf_controlar_estado()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
       OR (OLD.estado = 'terminado' AND NEW.estado = 'procesado') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Cambio de estado no permitido: de % a % (RN-10 / RN-11)',
        OLD.estado, NEW.estado;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ingreso_estado
BEFORE UPDATE ON ingreso
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION tf_controlar_estado();

CREATE TRIGGER trg_transferencia_estado
BEFORE UPDATE ON transferencia
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION tf_controlar_estado();

-- -----------------------------------------------------------------------------
-- T4. RN-12: un documento que no esta en confeccion no admite cambios en sus
-- renglones (agregar, modificar ni quitar).
-- TG_OP dice que operacion disparo el trigger: en un DELETE la fila es OLD, en
-- INSERT y UPDATE es NEW. En un BEFORE DELETE hay que devolver OLD; si se
-- devuelve NEW (que es nulo) el borrado se cancela sin avisar.
-- Si la cabecera ya no existe, el renglon se esta borrando en cascada porque
-- se borro el documento entero (consulta D5): eso se deja pasar.
-- Hay una funcion por tabla porque cada una apunta a una cabecera distinta.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tf_bloquear_renglones_ingreso()
RETURNS TRIGGER AS $$
DECLARE
    v_cod     INTEGER;
    v_estado  estado_documento;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_cod := OLD.cod_ingreso;
    ELSE
        v_cod := NEW.cod_ingreso;
    END IF;

    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = v_cod;

    IF v_estado IS NOT NULL AND v_estado <> 'en_confeccion' THEN
        RAISE EXCEPTION 'El ingreso % esta en estado %: no se pueden agregar, modificar ni quitar renglones (RN-12)',
            v_cod, v_estado;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_renglon_ingreso_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION tf_bloquear_renglones_ingreso();

CREATE OR REPLACE FUNCTION tf_bloquear_renglones_transferencia()
RETURNS TRIGGER AS $$
DECLARE
    v_nro     INTEGER;
    v_estado  estado_documento;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_nro := OLD.nro_solicitud;
    ELSE
        v_nro := NEW.nro_solicitud;
    END IF;

    SELECT estado INTO v_estado FROM transferencia WHERE nro_solicitud = v_nro;

    IF v_estado IS NOT NULL AND v_estado <> 'en_confeccion' THEN
        RAISE EXCEPTION 'La transferencia % esta en estado %: no se pueden agregar, modificar ni quitar renglones (RN-12)',
            v_nro, v_estado;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_renglon_transf_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW EXECUTE FUNCTION tf_bloquear_renglones_transferencia();

-- -----------------------------------------------------------------------------
-- T5. RN-11: la fecha de confeccion de una transferencia es la actual y no se
-- puede modificar. No puede ser un CHECK porque depende de la fecha de hoy:
-- un CHECK con CURRENT_DATE dejaria de cumplirse al dia siguiente.
-- Al insertar se pisa cualquier fecha que venga; al modificar, si cambia, error.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tf_fecha_transferencia()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
        RETURN NEW;
    END IF;

    IF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
        RAISE EXCEPTION 'La fecha de confeccion de la transferencia % no se puede modificar (RN-11)',
            OLD.nro_solicitud;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION tf_fecha_transferencia();

-- -----------------------------------------------------------------------------
-- T6. RN-13: todo cambio de precio de un vino queda auditado
-- Mismo esquema que el ejemplo del apunte (registrar_cambio_salario): AFTER
-- UPDATE, y el WHEN hace que solo se dispare si el precio cambio de verdad.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tf_auditar_precio()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
    VALUES (OLD.cod_vino, OLD.precio, NEW.precio, now(), current_user);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_vino_auditar_precio
AFTER UPDATE ON vino
FOR EACH ROW
WHEN (OLD.precio IS DISTINCT FROM NEW.precio)
EXECUTE FUNCTION tf_auditar_precio();

-- -----------------------------------------------------------------------------
-- T7. RN-05: los porcentajes de corte de un vino no pueden pasar de 100
-- Version simple: despues de cada alta o cambio en composicion suma los
-- porcentajes del vino y rechaza si superan 100.
-- Limite conocido: no exige que lleguen exactamente a 100, porque mientras se
-- cargan las cepas de a una la suma pasa por valores intermedios (85, despues
-- 100). Para exigir 100 justo habria que verificarlo al final de la
-- transaccion con un trigger diferido, que no vimos. Los vinos incompletos se
-- detectan con una vista (006_vistas.sql).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tf_controlar_suma_corte()
RETURNS TRIGGER AS $$
DECLARE
    v_suma NUMERIC;
BEGIN
    SELECT SUM(porcentaje) INTO v_suma
      FROM composicion
     WHERE cod_vino = NEW.cod_vino;

    IF v_suma > 100 THEN
        RAISE EXCEPTION 'Los porcentajes de corte del vino % suman %: no pueden pasar de 100 (RN-05)',
            NEW.cod_vino, v_suma;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_composicion_suma
AFTER INSERT OR UPDATE ON composicion
FOR EACH ROW EXECUTE FUNCTION tf_controlar_suma_corte();

-- -----------------------------------------------------------------------------
-- T8. RN-06: el descuento inicial del cliente depende de su tipo
-- Un DEFAULT no puede leer otra columna (tipo_cliente), por eso el valor
-- inicial lo pone este trigger. Si el descuento viene cargado se respeta
-- (por ejemplo, la consulta U6 sube algunos exportadores al 35 %).
-- La columna sigue siendo NOT NULL: PostgreSQL controla el NOT NULL despues
-- de los triggers BEFORE, cuando el trigger ya completo el valor.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tf_descuento_inicial()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.descuento IS NULL THEN
        NEW.descuento := fn_descuento_cliente(NEW.tipo_cliente);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cliente_descuento
BEFORE INSERT ON cliente
FOR EACH ROW EXECUTE FUNCTION tf_descuento_inicial();
