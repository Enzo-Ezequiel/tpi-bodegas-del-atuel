-- =============================================================================
-- 001_esquema.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Esquema fisico: tipos enumerados, dominios, tablas, claves primarias y
-- claves foraneas. Las restricciones UNIQUE, CHECK y DEFAULT se agregan en
-- 002_constraints.sql.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tipos enumerados
-- -----------------------------------------------------------------------------

-- Estado de ingresos y transferencias (RN-10, RN-11)
CREATE TYPE estado_documento AS ENUM ('en_confeccion', 'terminado', 'procesado');

CREATE TYPE tipo_vino AS ENUM ('tinto', 'blanco', 'rosado', 'espumante');

CREATE TYPE tipo_cepa AS ENUM ('tinta', 'blanca');

CREATE TYPE tipo_cliente AS ENUM ('socio', 'distribuidor', 'exportador');

CREATE TYPE tipo_documento AS ENUM ('DNI', 'CUIT', 'PASAPORTE');

CREATE TYPE dia_semana AS ENUM
    ('lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo');

-- -----------------------------------------------------------------------------
-- Dominios
-- -----------------------------------------------------------------------------

-- CUIT: exactamente 11 digitos, sin guiones
CREATE DOMAIN cuit_dom AS CHAR(11)
    CHECK (VALUE ~ '^[0-9]{11}$');

-- Porcentaje entre 0 y 100 con dos decimales (cortes y descuento del cliente)
CREATE DOMAIN porcentaje_dom AS NUMERIC(5,2)
    CHECK (VALUE BETWEEN 0 AND 100);

-- -----------------------------------------------------------------------------
-- Localidades, salas de venta y empleados
-- -----------------------------------------------------------------------------

CREATE TABLE localidad (
    id_localidad        INTEGER      GENERATED ALWAYS AS IDENTITY,
    nombre              VARCHAR(80)  NOT NULL,
    provincia           VARCHAR(50)  NOT NULL,
    codigo_postal       VARCHAR(8)   NOT NULL,
    encargado_regional  VARCHAR(100) NOT NULL,
    CONSTRAINT pk_localidad PRIMARY KEY (id_localidad)
);

CREATE TABLE sala_venta (
    id_sala       INTEGER     GENERATED ALWAYS AS IDENTITY,
    calle         VARCHAR(80) NOT NULL,
    numero        INTEGER     NOT NULL,
    dia_cierre    dia_semana  NOT NULL,
    id_localidad  INTEGER     NOT NULL,
    CONSTRAINT pk_sala_venta PRIMARY KEY (id_sala),
    CONSTRAINT fk_sala_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE empleado (
    cuit           cuit_dom      NOT NULL,
    nombre         VARCHAR(100)  NOT NULL,
    fecha_ingreso  DATE          NOT NULL,
    salario        NUMERIC(12,2) NOT NULL,
    id_sala        INTEGER       NOT NULL,
    CONSTRAINT pk_empleado PRIMARY KEY (cuit),
    CONSTRAINT fk_empleado_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- -----------------------------------------------------------------------------
-- Produccion de uva
-- -----------------------------------------------------------------------------

CREATE TABLE departamento (
    id_departamento  INTEGER     GENERATED ALWAYS AS IDENTITY,
    nombre           VARCHAR(60) NOT NULL,
    provincia        VARCHAR(50) NOT NULL,
    CONSTRAINT pk_departamento PRIMARY KEY (id_departamento)
);

CREATE TABLE cepa (
    id_cepa  INTEGER     GENERATED ALWAYS AS IDENTITY,
    nombre   VARCHAR(60) NOT NULL,
    tipo     tipo_cepa   NOT NULL,
    CONSTRAINT pk_cepa PRIMARY KEY (id_cepa)
);

CREATE TABLE finca (
    id_finca         INTEGER      GENERATED ALWAYS AS IDENTITY,
    nombre           VARCHAR(80)  NOT NULL,
    superficie_ha    NUMERIC(8,2) NOT NULL,
    id_departamento  INTEGER      NOT NULL,
    CONSTRAINT pk_finca PRIMARY KEY (id_finca),
    CONSTRAINT fk_finca_departamento FOREIGN KEY (id_departamento)
        REFERENCES departamento (id_departamento) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- Entidad debil: la parcela se identifica por su numero dentro de la finca
CREATE TABLE parcela (
    id_finca         INTEGER      NOT NULL,
    nro_parcela      SMALLINT     NOT NULL,
    superficie_ha    NUMERIC(7,2) NOT NULL,
    anio_plantacion  SMALLINT     NOT NULL,
    id_cepa          INTEGER      NOT NULL,
    CONSTRAINT pk_parcela PRIMARY KEY (id_finca, nro_parcela),
    CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca)
        REFERENCES finca (id_finca) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- -----------------------------------------------------------------------------
-- Bodegas y vinos
-- -----------------------------------------------------------------------------

CREATE TABLE bodega (
    cuit          cuit_dom     NOT NULL,
    razon_social  VARCHAR(100) NOT NULL,
    domicilio     VARCHAR(150) NOT NULL,
    CONSTRAINT pk_bodega PRIMARY KEY (cuit)
);

CREATE TABLE lote_uva (
    nro_lote       INTEGER       GENERATED ALWAYS AS IDENTITY,
    id_finca       INTEGER       NOT NULL,
    nro_parcela    SMALLINT      NOT NULL,
    campania       SMALLINT      NOT NULL,
    fecha_cosecha  DATE          NOT NULL,
    kilos          NUMERIC(10,2) NOT NULL,
    cuit_bodega    cuit_dom      NOT NULL,
    CONSTRAINT pk_lote_uva PRIMARY KEY (nro_lote),
    CONSTRAINT fk_lote_parcela FOREIGN KEY (id_finca, nro_parcela)
        REFERENCES parcela (id_finca, nro_parcela) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_lote_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE analisis_calidad (
    id_analisis   INTEGER      GENERATED ALWAYS AS IDENTITY,
    nro_lote      INTEGER      NOT NULL,
    fecha         DATE         NOT NULL,
    brix          NUMERIC(4,2) NOT NULL,
    ph            NUMERIC(3,2) NOT NULL,
    acidez_total  NUMERIC(4,2) NOT NULL,
    CONSTRAINT pk_analisis_calidad PRIMARY KEY (id_analisis),
    CONSTRAINT fk_analisis_lote FOREIGN KEY (nro_lote)
        REFERENCES lote_uva (nro_lote) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE vino (
    cod_vino     INTEGER       GENERATED ALWAYS AS IDENTITY,
    nombre       VARCHAR(80)   NOT NULL,
    tipo         tipo_vino     NOT NULL,
    anada        SMALLINT      NOT NULL,
    volumen_ml   INTEGER       NOT NULL,
    graduacion   NUMERIC(4,2)  NOT NULL,
    precio       NUMERIC(10,2) NOT NULL,
    cuit_bodega  cuit_dom      NOT NULL,
    CONSTRAINT pk_vino PRIMARY KEY (cod_vino),
    CONSTRAINT fk_vino_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- N:M vino-cepa con atributo. La suma por vino debe ser 100 (RN-05, etapa 2)
CREATE TABLE composicion (
    cod_vino    INTEGER        NOT NULL,
    id_cepa     INTEGER        NOT NULL,
    porcentaje  porcentaje_dom NOT NULL,
    CONSTRAINT pk_composicion PRIMARY KEY (cod_vino, id_cepa),
    CONSTRAINT fk_composicion_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_composicion_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE maridaje (
    id_maridaje           INTEGER      GENERATED ALWAYS AS IDENTITY,
    nombre                VARCHAR(60)  NOT NULL,
    temperatura_servicio  NUMERIC(3,1) NOT NULL,
    CONSTRAINT pk_maridaje PRIMARY KEY (id_maridaje)
);

CREATE TABLE vino_maridaje (
    cod_vino     INTEGER NOT NULL,
    id_maridaje  INTEGER NOT NULL,
    CONSTRAINT pk_vino_maridaje PRIMARY KEY (cod_vino, id_maridaje),
    CONSTRAINT fk_vino_maridaje_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_vino_maridaje_maridaje FOREIGN KEY (id_maridaje)
        REFERENCES maridaje (id_maridaje) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- -----------------------------------------------------------------------------
-- Clientes (jerarquia total y disjunta: supertipo + una tabla por subtipo)
-- -----------------------------------------------------------------------------

CREATE TABLE cliente (
    id_cliente           INTEGER        GENERATED ALWAYS AS IDENTITY,
    nombre_razon_social  VARCHAR(120)   NOT NULL,
    tipo_documento       tipo_documento NOT NULL,
    nro_documento        VARCHAR(15)    NOT NULL,
    direccion            VARCHAR(150)   NOT NULL,
    id_localidad         INTEGER        NOT NULL,
    fecha_alta           DATE           NOT NULL,
    tipo_cliente         tipo_cliente   NOT NULL,
    descuento            porcentaje_dom NOT NULL,
    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT fk_cliente_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE socio (
    id_cliente  INTEGER NOT NULL,
    CONSTRAINT pk_socio PRIMARY KEY (id_cliente),
    CONSTRAINT fk_socio_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE distribuidor (
    id_cliente       INTEGER      NOT NULL,
    zona_cobertura   VARCHAR(100) NOT NULL,
    nro_habilitacion VARCHAR(20)  NOT NULL,
    CONSTRAINT pk_distribuidor PRIMARY KEY (id_cliente),
    CONSTRAINT fk_distribuidor_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE exportador (
    id_cliente    INTEGER     NOT NULL,
    pais_destino  VARCHAR(60) NOT NULL,
    CONSTRAINT pk_exportador PRIMARY KEY (id_cliente),
    CONSTRAINT fk_exportador_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE permiso_exportacion (
    codigo             VARCHAR(20) NOT NULL,
    id_cliente         INTEGER     NOT NULL,
    fecha_emision      DATE        NOT NULL,
    fecha_vencimiento  DATE        NOT NULL,
    CONSTRAINT pk_permiso_exportacion PRIMARY KEY (codigo),
    CONSTRAINT fk_permiso_exportador FOREIGN KEY (id_cliente)
        REFERENCES exportador (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT
);

-- -----------------------------------------------------------------------------
-- Ventas
-- -----------------------------------------------------------------------------

-- subtotal, descuento (importe) y total los mantiene un trigger (RN-08, etapa 2)
CREATE TABLE comprobante (
    nro         INTEGER       GENERATED ALWAYS AS IDENTITY,
    fecha       DATE          NOT NULL,
    id_cliente  INTEGER       NOT NULL,
    id_sala     INTEGER       NOT NULL,
    subtotal    NUMERIC(14,2) NOT NULL,
    descuento   NUMERIC(14,2) NOT NULL,
    total       NUMERIC(14,2) NOT NULL,
    CONSTRAINT pk_comprobante PRIMARY KEY (nro),
    CONSTRAINT fk_comprobante_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_comprobante_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- precio_unitario: precio del vino al momento de la venta
-- descuento: importe descontado en el renglon segun el descuento del cliente
-- subtotal: cantidad * precio_unitario - descuento
CREATE TABLE renglon_comprobante (
    nro_comprobante  INTEGER        NOT NULL,
    cod_vino         INTEGER        NOT NULL,
    cantidad         INTEGER        NOT NULL,
    precio_unitario  NUMERIC(10,2)  NOT NULL,
    descuento        NUMERIC(14,2)  NOT NULL,
    subtotal         NUMERIC(14,2)  NOT NULL,
    CONSTRAINT pk_renglon_comprobante PRIMARY KEY (nro_comprobante, cod_vino),
    CONSTRAINT fk_renglon_comprobante_cabecera FOREIGN KEY (nro_comprobante)
        REFERENCES comprobante (nro) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_renglon_comprobante_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- -----------------------------------------------------------------------------
-- Transportistas, ingresos y transferencias
-- -----------------------------------------------------------------------------

CREATE TABLE transportista (
    cod_transporte  INTEGER      GENERATED ALWAYS AS IDENTITY,
    razon_social    VARCHAR(100) NOT NULL,
    cuit            cuit_dom     NOT NULL,
    email           VARCHAR(120) NOT NULL,
    telefono        VARCHAR(20)  NOT NULL,
    domicilio       VARCHAR(150) NOT NULL,
    CONSTRAINT pk_transportista PRIMARY KEY (cod_transporte)
);

CREATE TABLE transportista_localidad (
    cod_transporte  INTEGER NOT NULL,
    id_localidad    INTEGER NOT NULL,
    CONSTRAINT pk_transportista_localidad PRIMARY KEY (cod_transporte, id_localidad),
    CONSTRAINT fk_cobertura_transportista FOREIGN KEY (cod_transporte)
        REFERENCES transportista (cod_transporte) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_cobertura_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE ingreso (
    cod_ingreso     INTEGER          GENERATED ALWAYS AS IDENTITY,
    fecha           DATE             NOT NULL,
    estado          estado_documento NOT NULL,
    cod_transporte  INTEGER          NOT NULL,
    cuit_bodega     cuit_dom         NOT NULL,
    CONSTRAINT pk_ingreso PRIMARY KEY (cod_ingreso),
    CONSTRAINT fk_ingreso_transportista FOREIGN KEY (cod_transporte)
        REFERENCES transportista (cod_transporte) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_ingreso_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE renglon_ingreso (
    cod_ingreso  INTEGER NOT NULL,
    cod_vino     INTEGER NOT NULL,
    cantidad     INTEGER NOT NULL,
    CONSTRAINT pk_renglon_ingreso PRIMARY KEY (cod_ingreso, cod_vino),
    CONSTRAINT fk_renglon_ingreso_cabecera FOREIGN KEY (cod_ingreso)
        REFERENCES ingreso (cod_ingreso) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_renglon_ingreso_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE transferencia (
    nro_solicitud     INTEGER          GENERATED ALWAYS AS IDENTITY,
    id_sala           INTEGER          NOT NULL,
    fecha_confeccion  DATE             NOT NULL,
    estado            estado_documento NOT NULL,
    CONSTRAINT pk_transferencia PRIMARY KEY (nro_solicitud),
    CONSTRAINT fk_transferencia_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE renglon_transferencia (
    nro_solicitud  INTEGER NOT NULL,
    cod_vino       INTEGER NOT NULL,
    cantidad       INTEGER NOT NULL,
    CONSTRAINT pk_renglon_transferencia PRIMARY KEY (nro_solicitud, cod_vino),
    CONSTRAINT fk_renglon_transferencia_cabecera FOREIGN KEY (nro_solicitud)
        REFERENCES transferencia (nro_solicitud) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_renglon_transferencia_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- -----------------------------------------------------------------------------
-- Stock y auditoria
-- -----------------------------------------------------------------------------

CREATE TABLE stock_sala (
    id_sala   INTEGER NOT NULL,
    cod_vino  INTEGER NOT NULL,
    cantidad  INTEGER NOT NULL,
    CONSTRAINT pk_stock_sala PRIMARY KEY (id_sala, cod_vino),
    CONSTRAINT fk_stock_sala_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_stock_sala_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- Hay un unico deposito central: una fila por vino
CREATE TABLE stock_deposito (
    cod_vino  INTEGER NOT NULL,
    cantidad  INTEGER NOT NULL,
    CONSTRAINT pk_stock_deposito PRIMARY KEY (cod_vino),
    CONSTRAINT fk_stock_deposito_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- La completa un trigger AFTER UPDATE sobre vino (RN-13, etapa 2)
CREATE TABLE auditoria_precio (
    id_auditoria     INTEGER       GENERATED ALWAYS AS IDENTITY,
    cod_vino         INTEGER       NOT NULL,
    precio_anterior  NUMERIC(10,2) NOT NULL,
    precio_nuevo     NUMERIC(10,2) NOT NULL,
    fecha_hora       TIMESTAMPTZ   NOT NULL,
    usuario          VARCHAR(63)   NOT NULL,
    CONSTRAINT pk_auditoria_precio PRIMARY KEY (id_auditoria),
    CONSTRAINT fk_auditoria_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- -----------------------------------------------------------------------------
-- Descripciones (fuente del diccionario de datos)
-- -----------------------------------------------------------------------------

COMMENT ON TABLE localidad IS 'Localidades donde hay salas, clientes o cobertura de transporte';
COMMENT ON COLUMN localidad.id_localidad IS 'Identificador subrogado (el codigo postal se repite entre localidades)';
COMMENT ON COLUMN localidad.nombre IS 'Nombre de la localidad';
COMMENT ON COLUMN localidad.provincia IS 'Provincia a la que pertenece';
COMMENT ON COLUMN localidad.codigo_postal IS 'Codigo postal';
COMMENT ON COLUMN localidad.encargado_regional IS 'Nombre del responsable comercial, unico por localidad (RN-02)';

COMMENT ON TABLE sala_venta IS 'Salas de venta de la red';
COMMENT ON COLUMN sala_venta.id_sala IS 'Identificador de la sala';
COMMENT ON COLUMN sala_venta.calle IS 'Calle de la direccion';
COMMENT ON COLUMN sala_venta.numero IS 'Numero de la direccion';
COMMENT ON COLUMN sala_venta.dia_cierre IS 'Dia de cierre semanal';
COMMENT ON COLUMN sala_venta.id_localidad IS 'Localidad donde esta ubicada (RN-02)';

COMMENT ON TABLE empleado IS 'Empleados de las salas de venta';
COMMENT ON COLUMN empleado.cuit IS 'CUIT del empleado (clave natural)';
COMMENT ON COLUMN empleado.nombre IS 'Apellido y nombre';
COMMENT ON COLUMN empleado.fecha_ingreso IS 'Fecha de ingreso laboral';
COMMENT ON COLUMN empleado.salario IS 'Salario mensual en pesos';
COMMENT ON COLUMN empleado.id_sala IS 'Sala en la que trabaja (RN-03)';

COMMENT ON TABLE departamento IS 'Departamentos provinciales donde se ubican las fincas';
COMMENT ON COLUMN departamento.id_departamento IS 'Identificador del departamento';
COMMENT ON COLUMN departamento.nombre IS 'Nombre del departamento';
COMMENT ON COLUMN departamento.provincia IS 'Provincia del departamento';

COMMENT ON TABLE cepa IS 'Catalogo de cepas (variedades de uva)';
COMMENT ON COLUMN cepa.id_cepa IS 'Identificador de la cepa';
COMMENT ON COLUMN cepa.nombre IS 'Nombre de la cepa';
COMMENT ON COLUMN cepa.tipo IS 'Tinta o blanca';

COMMENT ON TABLE finca IS 'Fincas donde la empresa cultiva uva';
COMMENT ON COLUMN finca.id_finca IS 'Identificador de la finca';
COMMENT ON COLUMN finca.nombre IS 'Nombre de la finca';
COMMENT ON COLUMN finca.superficie_ha IS 'Superficie total en hectareas';
COMMENT ON COLUMN finca.id_departamento IS 'Departamento donde se ubica';

COMMENT ON TABLE parcela IS 'Parcelas de una finca (entidad debil de finca)';
COMMENT ON COLUMN parcela.id_finca IS 'Finca a la que pertenece';
COMMENT ON COLUMN parcela.nro_parcela IS 'Numero de parcela dentro de la finca';
COMMENT ON COLUMN parcela.superficie_ha IS 'Superficie en hectareas';
COMMENT ON COLUMN parcela.anio_plantacion IS 'Anio de plantacion';
COMMENT ON COLUMN parcela.id_cepa IS 'Cepa plantada, una sola por parcela (RN-04)';

COMMENT ON TABLE bodega IS 'Bodegas del grupo que elaboran los vinos';
COMMENT ON COLUMN bodega.cuit IS 'CUIT de la bodega (clave natural)';
COMMENT ON COLUMN bodega.razon_social IS 'Razon social';
COMMENT ON COLUMN bodega.domicilio IS 'Domicilio';

COMMENT ON TABLE lote_uva IS 'Lote de uva generado por la cosecha de una parcela en una campania';
COMMENT ON COLUMN lote_uva.nro_lote IS 'Numero de lote';
COMMENT ON COLUMN lote_uva.id_finca IS 'Finca de la parcela cosechada';
COMMENT ON COLUMN lote_uva.nro_parcela IS 'Parcela cosechada';
COMMENT ON COLUMN lote_uva.campania IS 'Anio de cosecha; una cosecha por parcela y campania (RN-04)';
COMMENT ON COLUMN lote_uva.fecha_cosecha IS 'Fecha de cosecha';
COMMENT ON COLUMN lote_uva.kilos IS 'Kilos cosechados';
COMMENT ON COLUMN lote_uva.cuit_bodega IS 'Bodega a la que se entrego el lote';

COMMENT ON TABLE analisis_calidad IS 'Analisis de calidad practicados a un lote de uva';
COMMENT ON COLUMN analisis_calidad.id_analisis IS 'Identificador del analisis';
COMMENT ON COLUMN analisis_calidad.nro_lote IS 'Lote analizado';
COMMENT ON COLUMN analisis_calidad.fecha IS 'Fecha del analisis';
COMMENT ON COLUMN analisis_calidad.brix IS 'Grado Brix';
COMMENT ON COLUMN analisis_calidad.ph IS 'pH';
COMMENT ON COLUMN analisis_calidad.acidez_total IS 'Acidez total en g/L';

COMMENT ON TABLE vino IS 'Vinos elaborados por las bodegas del grupo';
COMMENT ON COLUMN vino.cod_vino IS 'Codigo del vino';
COMMENT ON COLUMN vino.nombre IS 'Nombre comercial';
COMMENT ON COLUMN vino.tipo IS 'Tinto, blanco, rosado o espumante';
COMMENT ON COLUMN vino.anada IS 'Aniada (anio de cosecha de la uva)';
COMMENT ON COLUMN vino.volumen_ml IS 'Presentacion: volumen en mililitros';
COMMENT ON COLUMN vino.graduacion IS 'Graduacion alcoholica en grados';
COMMENT ON COLUMN vino.precio IS 'Precio de venta, unico para toda la red (RN-01)';
COMMENT ON COLUMN vino.cuit_bodega IS 'Bodega que lo elabora';

COMMENT ON TABLE composicion IS 'Cepas que componen cada vino y su porcentaje de corte';
COMMENT ON COLUMN composicion.cod_vino IS 'Vino';
COMMENT ON COLUMN composicion.id_cepa IS 'Cepa';
COMMENT ON COLUMN composicion.porcentaje IS 'Porcentaje de corte; la suma por vino es 100 (RN-05)';

COMMENT ON TABLE maridaje IS 'Catalogo de maridajes';
COMMENT ON COLUMN maridaje.id_maridaje IS 'Identificador del maridaje';
COMMENT ON COLUMN maridaje.nombre IS 'Nombre del maridaje';
COMMENT ON COLUMN maridaje.temperatura_servicio IS 'Temperatura de servicio sugerida en grados Celsius';

COMMENT ON TABLE vino_maridaje IS 'Maridajes recomendados para cada vino';
COMMENT ON COLUMN vino_maridaje.cod_vino IS 'Vino';
COMMENT ON COLUMN vino_maridaje.id_maridaje IS 'Maridaje recomendado';

COMMENT ON TABLE cliente IS 'Clientes (supertipo de socio, distribuidor y exportador)';
COMMENT ON COLUMN cliente.id_cliente IS 'Identificador del cliente';
COMMENT ON COLUMN cliente.nombre_razon_social IS 'Apellido y nombre, o razon social';
COMMENT ON COLUMN cliente.tipo_documento IS 'Tipo de documento';
COMMENT ON COLUMN cliente.nro_documento IS 'Numero de documento';
COMMENT ON COLUMN cliente.direccion IS 'Direccion';
COMMENT ON COLUMN cliente.id_localidad IS 'Localidad donde reside';
COMMENT ON COLUMN cliente.fecha_alta IS 'Fecha de alta como cliente';
COMMENT ON COLUMN cliente.tipo_cliente IS 'Discriminador de la jerarquia';
COMMENT ON COLUMN cliente.descuento IS 'Porcentaje de descuento; por defecto segun el tipo (RN-06)';

COMMENT ON TABLE socio IS 'Subtipo de cliente: socio del club (sin atributos propios)';
COMMENT ON COLUMN socio.id_cliente IS 'Cliente que es socio';

COMMENT ON TABLE distribuidor IS 'Subtipo de cliente: distribuidor';
COMMENT ON COLUMN distribuidor.id_cliente IS 'Cliente que es distribuidor';
COMMENT ON COLUMN distribuidor.zona_cobertura IS 'Zona de cobertura';
COMMENT ON COLUMN distribuidor.nro_habilitacion IS 'Numero de habilitacion';

COMMENT ON TABLE exportador IS 'Subtipo de cliente: exportador';
COMMENT ON COLUMN exportador.id_cliente IS 'Cliente que es exportador';
COMMENT ON COLUMN exportador.pais_destino IS 'Pais de destino principal';

COMMENT ON TABLE permiso_exportacion IS 'Permisos de exportacion de un exportador';
COMMENT ON COLUMN permiso_exportacion.codigo IS 'Codigo del permiso';
COMMENT ON COLUMN permiso_exportacion.id_cliente IS 'Exportador titular';
COMMENT ON COLUMN permiso_exportacion.fecha_emision IS 'Fecha de emision';
COMMENT ON COLUMN permiso_exportacion.fecha_vencimiento IS 'Fecha de vencimiento, posterior a la emision (RN-07)';

COMMENT ON TABLE comprobante IS 'Comprobantes de venta emitidos en las salas';
COMMENT ON COLUMN comprobante.nro IS 'Numero de comprobante';
COMMENT ON COLUMN comprobante.fecha IS 'Fecha de la venta';
COMMENT ON COLUMN comprobante.id_cliente IS 'Cliente que compra';
COMMENT ON COLUMN comprobante.id_sala IS 'Sala donde se realizo la venta';
COMMENT ON COLUMN comprobante.subtotal IS 'Suma de cantidad por precio unitario de los renglones, sin descuento (derivado, RN-08)';
COMMENT ON COLUMN comprobante.descuento IS 'Suma de los descuentos de los renglones (derivado, RN-08)';
COMMENT ON COLUMN comprobante.total IS 'Subtotal menos descuento (derivado, RN-08)';

COMMENT ON TABLE renglon_comprobante IS 'Vinos incluidos en cada comprobante';
COMMENT ON COLUMN renglon_comprobante.nro_comprobante IS 'Comprobante al que pertenece';
COMMENT ON COLUMN renglon_comprobante.cod_vino IS 'Vino vendido';
COMMENT ON COLUMN renglon_comprobante.cantidad IS 'Cantidad de botellas';
COMMENT ON COLUMN renglon_comprobante.precio_unitario IS 'Precio del vino al momento de la venta';
COMMENT ON COLUMN renglon_comprobante.descuento IS 'Importe descontado en el renglon segun el descuento del cliente (derivado)';
COMMENT ON COLUMN renglon_comprobante.subtotal IS 'Cantidad por precio unitario menos descuento (derivado)';

COMMENT ON TABLE transportista IS 'Empresas de transporte que trasladan los ingresos';
COMMENT ON COLUMN transportista.cod_transporte IS 'Codigo de transporte';
COMMENT ON COLUMN transportista.razon_social IS 'Razon social';
COMMENT ON COLUMN transportista.cuit IS 'CUIT de la empresa';
COMMENT ON COLUMN transportista.email IS 'Correo electronico';
COMMENT ON COLUMN transportista.telefono IS 'Telefono';
COMMENT ON COLUMN transportista.domicilio IS 'Domicilio';

COMMENT ON TABLE transportista_localidad IS 'Localidades que alcanza el servicio de cada transportista';
COMMENT ON COLUMN transportista_localidad.cod_transporte IS 'Transportista';
COMMENT ON COLUMN transportista_localidad.id_localidad IS 'Localidad cubierta';

COMMENT ON TABLE ingreso IS 'Ingresos de vino al deposito central';
COMMENT ON COLUMN ingreso.cod_ingreso IS 'Codigo de ingreso';
COMMENT ON COLUMN ingreso.fecha IS 'Fecha del ingreso';
COMMENT ON COLUMN ingreso.estado IS 'en_confeccion, terminado o procesado (RN-10)';
COMMENT ON COLUMN ingreso.cod_transporte IS 'Transportista que efectuo el traslado';
COMMENT ON COLUMN ingreso.cuit_bodega IS 'Bodega de origen';

COMMENT ON TABLE renglon_ingreso IS 'Vinos incluidos en cada ingreso';
COMMENT ON COLUMN renglon_ingreso.cod_ingreso IS 'Ingreso al que pertenece';
COMMENT ON COLUMN renglon_ingreso.cod_vino IS 'Vino ingresado';
COMMENT ON COLUMN renglon_ingreso.cantidad IS 'Cantidad de botellas';

COMMENT ON TABLE transferencia IS 'Solicitudes de vino de una sala al deposito central';
COMMENT ON COLUMN transferencia.nro_solicitud IS 'Numero de solicitud';
COMMENT ON COLUMN transferencia.id_sala IS 'Sala solicitante';
COMMENT ON COLUMN transferencia.fecha_confeccion IS 'Fecha de confeccion: la actual, no modificable (RN-11)';
COMMENT ON COLUMN transferencia.estado IS 'en_confeccion, terminado o procesado (RN-11)';

COMMENT ON TABLE renglon_transferencia IS 'Vinos incluidos en cada transferencia';
COMMENT ON COLUMN renglon_transferencia.nro_solicitud IS 'Transferencia a la que pertenece';
COMMENT ON COLUMN renglon_transferencia.cod_vino IS 'Vino solicitado';
COMMENT ON COLUMN renglon_transferencia.cantidad IS 'Cantidad de botellas';

COMMENT ON TABLE stock_sala IS 'Stock de cada vino en cada sala';
COMMENT ON COLUMN stock_sala.id_sala IS 'Sala';
COMMENT ON COLUMN stock_sala.cod_vino IS 'Vino';
COMMENT ON COLUMN stock_sala.cantidad IS 'Botellas disponibles, nunca negativo (RN-09)';

COMMENT ON TABLE stock_deposito IS 'Stock de cada vino en el deposito central (unico)';
COMMENT ON COLUMN stock_deposito.cod_vino IS 'Vino';
COMMENT ON COLUMN stock_deposito.cantidad IS 'Botellas disponibles, nunca negativo';

COMMENT ON TABLE auditoria_precio IS 'Historial de cambios de precio de los vinos (RN-13)';
COMMENT ON COLUMN auditoria_precio.id_auditoria IS 'Identificador del registro';
COMMENT ON COLUMN auditoria_precio.cod_vino IS 'Vino cuyo precio cambio';
COMMENT ON COLUMN auditoria_precio.precio_anterior IS 'Precio antes del cambio';
COMMENT ON COLUMN auditoria_precio.precio_nuevo IS 'Precio despues del cambio';
COMMENT ON COLUMN auditoria_precio.fecha_hora IS 'Momento del cambio';
COMMENT ON COLUMN auditoria_precio.usuario IS 'Usuario de base de datos que hizo el cambio';
