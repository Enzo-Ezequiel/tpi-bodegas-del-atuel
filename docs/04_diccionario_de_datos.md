# Diccionario de datos

Una sección por cada tabla de `db/migrations/001_esquema.sql`, en el mismo orden. **Se mantiene a mano:** si cambia el esquema, hay que actualizarlo acá.

Referencias:

- **Obligatorio:** «Sí» significa que la columna es `NOT NULL`.
- **PK:** clave primaria. **FK → tabla:** clave foránea hacia esa tabla.
- **Autogenerado:** el valor lo asigna la base (`GENERATED ALWAYS AS IDENTITY`).
- Las restricciones UNIQUE, CHECK y DEFAULT se agregan en la etapa 2.

## Tipos propios

| Tipo | Clase | Valores permitidos |
|---|---|---|
| `estado_documento` | ENUM | en_confeccion, terminado, procesado |
| `tipo_vino` | ENUM | tinto, blanco, rosado, espumante |
| `tipo_cepa` | ENUM | tinta, blanca |
| `tipo_cliente` | ENUM | socio, distribuidor, exportador |
| `tipo_documento` | ENUM | DNI, CUIT, PASAPORTE |
| `dia_semana` | ENUM | lunes, martes, miercoles, jueves, viernes, sabado, domingo |
| `cuit_dom` | DOMAIN | `CHAR(11)` con exactamente 11 dígitos |
| `porcentaje_dom` | DOMAIN | `NUMERIC(5,2)` entre 0 y 100 |

## Localidades, salas de venta y empleados

### localidad

Localidades donde hay salas, clientes o cobertura de transporte

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_localidad` | `INTEGER` | Sí | PK, autogenerado | Identificador subrogado (el código postal se repite entre localidades) |
| `nombre` | `VARCHAR(80)` | Sí |  | Nombre de la localidad |
| `provincia` | `VARCHAR(50)` | Sí |  | Provincia a la que pertenece |
| `codigo_postal` | `VARCHAR(8)` | Sí |  | Código postal |
| `encargado_regional` | `VARCHAR(100)` | Sí |  | Nombre del responsable comercial, único por localidad (RN-02) |

### sala_venta

Salas de venta de la red

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_sala` | `INTEGER` | Sí | PK, autogenerado | Identificador de la sala |
| `calle` | `VARCHAR(80)` | Sí |  | Calle de la dirección |
| `numero` | `INTEGER` | Sí |  | Número de la dirección |
| `dia_cierre` | `dia_semana` | Sí |  | Día de cierre semanal |
| `id_localidad` | `INTEGER` | Sí | FK → `localidad` | Localidad donde está ubicada (RN-02) |

### empleado

Empleados de las salas de venta

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cuit` | `cuit_dom` | Sí | PK | CUIT del empleado (clave natural) |
| `nombre` | `VARCHAR(100)` | Sí |  | Apellido y nombre |
| `fecha_ingreso` | `DATE` | Sí |  | Fecha de ingreso laboral |
| `salario` | `NUMERIC(12,2)` | Sí |  | Salario mensual en pesos |
| `id_sala` | `INTEGER` | Sí | FK → `sala_venta` | Sala en la que trabaja (RN-03) |

## Producción de uva

### departamento

Departamentos provinciales donde se ubican las fincas

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_departamento` | `INTEGER` | Sí | PK, autogenerado | Identificador del departamento |
| `nombre` | `VARCHAR(60)` | Sí |  | Nombre del departamento |
| `provincia` | `VARCHAR(50)` | Sí |  | Provincia del departamento |

### cepa

Catálogo de cepas (variedades de uva)

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_cepa` | `INTEGER` | Sí | PK, autogenerado | Identificador de la cepa |
| `nombre` | `VARCHAR(60)` | Sí |  | Nombre de la cepa |
| `tipo` | `tipo_cepa` | Sí |  | Tinta o blanca |

### finca

Fincas donde la empresa cultiva uva

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_finca` | `INTEGER` | Sí | PK, autogenerado | Identificador de la finca |
| `nombre` | `VARCHAR(80)` | Sí |  | Nombre de la finca |
| `superficie_ha` | `NUMERIC(8,2)` | Sí |  | Superficie total en hectáreas |
| `id_departamento` | `INTEGER` | Sí | FK → `departamento` | Departamento donde se ubica |

### parcela

Parcelas de una finca (entidad débil de finca)

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_finca` | `INTEGER` | Sí | PK, FK → `finca` | Finca a la que pertenece |
| `nro_parcela` | `SMALLINT` | Sí | PK | Número de parcela dentro de la finca |
| `superficie_ha` | `NUMERIC(7,2)` | Sí |  | Superficie en hectáreas |
| `anio_plantacion` | `SMALLINT` | Sí |  | Año de plantacion |
| `id_cepa` | `INTEGER` | Sí | FK → `cepa` | Cepa plantada, una sola por parcela (RN-04) |

## Bodegas y vinos

### bodega

Bodegas del grupo que elaboran los vinos

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cuit` | `cuit_dom` | Sí | PK | CUIT de la bodega (clave natural) |
| `razon_social` | `VARCHAR(100)` | Sí |  | Razón social |
| `domicilio` | `VARCHAR(150)` | Sí |  | Domicilio |

### lote_uva

Lote de uva generado por la cosecha de una parcela en una campaña

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `nro_lote` | `INTEGER` | Sí | PK, autogenerado | Número de lote |
| `id_finca` | `INTEGER` | Sí | FK → `parcela` | Finca de la parcela cosechada |
| `nro_parcela` | `SMALLINT` | Sí | FK → `parcela` | Parcela cosechada |
| `campania` | `SMALLINT` | Sí |  | Año de cosecha; una cosecha por parcela y campaña (RN-04) |
| `fecha_cosecha` | `DATE` | Sí |  | Fecha de cosecha |
| `kilos` | `NUMERIC(10,2)` | Sí |  | Kilos cosechados |
| `cuit_bodega` | `cuit_dom` | Sí | FK → `bodega` | Bodega a la que se entregó el lote |

### analisis_calidad

Análisis de calidad practicados a un lote de uva

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_analisis` | `INTEGER` | Sí | PK, autogenerado | Identificador del análisis |
| `nro_lote` | `INTEGER` | Sí | FK → `lote_uva` | Lote analizado |
| `fecha` | `DATE` | Sí |  | Fecha del análisis |
| `brix` | `NUMERIC(4,2)` | Sí |  | Grado Brix |
| `ph` | `NUMERIC(3,2)` | Sí |  | pH |
| `acidez_total` | `NUMERIC(4,2)` | Sí |  | Acidez total en g/L |

### vino

Vinos elaborados por las bodegas del grupo

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cod_vino` | `INTEGER` | Sí | PK, autogenerado | Código del vino |
| `nombre` | `VARCHAR(80)` | Sí |  | Nombre comercial |
| `tipo` | `tipo_vino` | Sí |  | Tinto, blanco, rosado o espumante |
| `anada` | `SMALLINT` | Sí |  | Añada (año de cosecha de la uva) |
| `volumen_ml` | `INTEGER` | Sí |  | Presentación: volumen en mililitros |
| `graduacion` | `NUMERIC(4,2)` | Sí |  | Graduación alcohólica en grados |
| `precio` | `NUMERIC(10,2)` | Sí |  | Precio de venta, único para toda la red (RN-01) |
| `cuit_bodega` | `cuit_dom` | Sí | FK → `bodega` | Bodega que lo elabora |

### composicion

Cepas que componen cada vino y su porcentaje de corte

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cod_vino` | `INTEGER` | Sí | PK, FK → `vino` | Vino |
| `id_cepa` | `INTEGER` | Sí | PK, FK → `cepa` | Cepa |
| `porcentaje` | `porcentaje_dom` | Sí |  | Porcentaje de corte; la suma por vino es 100 (RN-05) |

### maridaje

Catálogo de maridajes

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_maridaje` | `INTEGER` | Sí | PK, autogenerado | Identificador del maridaje |
| `nombre` | `VARCHAR(60)` | Sí |  | Nombre del maridaje |
| `temperatura_servicio` | `NUMERIC(3,1)` | Sí |  | Temperatura de servicio sugerida en grados Celsius |

### vino_maridaje

Maridajes recomendados para cada vino

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cod_vino` | `INTEGER` | Sí | PK, FK → `vino` | Vino |
| `id_maridaje` | `INTEGER` | Sí | PK, FK → `maridaje` | Maridaje recomendado |

## Clientes

### cliente

Clientes (supertipo de socio, distribuidor y exportador)

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_cliente` | `INTEGER` | Sí | PK, autogenerado | Identificador del cliente |
| `nombre_razon_social` | `VARCHAR(120)` | Sí |  | Apellido y nombre, o razón social |
| `tipo_documento` | `tipo_documento` | Sí |  | Tipo de documento |
| `nro_documento` | `VARCHAR(15)` | Sí |  | Número de documento |
| `direccion` | `VARCHAR(150)` | Sí |  | Dirección |
| `id_localidad` | `INTEGER` | Sí | FK → `localidad` | Localidad donde reside |
| `fecha_alta` | `DATE` | Sí |  | Fecha de alta como cliente |
| `tipo_cliente` | `tipo_cliente` | Sí |  | Discriminador de la jerarquía |
| `descuento` | `porcentaje_dom` | Sí |  | Porcentaje de descuento; por defecto según el tipo (RN-06) |

### socio

Subtipo de cliente: socio del club (sin atributos propios)

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_cliente` | `INTEGER` | Sí | PK, FK → `cliente` | Cliente que es socio |

### distribuidor

Subtipo de cliente: distribuidor

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_cliente` | `INTEGER` | Sí | PK, FK → `cliente` | Cliente que es distribuidor |
| `zona_cobertura` | `VARCHAR(100)` | Sí |  | Zona de cobertura |
| `nro_habilitacion` | `VARCHAR(20)` | Sí |  | Número de habilitación |

### exportador

Subtipo de cliente: exportador

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_cliente` | `INTEGER` | Sí | PK, FK → `cliente` | Cliente que es exportador |
| `pais_destino` | `VARCHAR(60)` | Sí |  | País de destino principal |

### permiso_exportacion

Permisos de exportación de un exportador

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `codigo` | `VARCHAR(20)` | Sí | PK | Código del permiso |
| `id_cliente` | `INTEGER` | Sí | FK → `exportador` | Exportador titular |
| `fecha_emision` | `DATE` | Sí |  | Fecha de emisión |
| `fecha_vencimiento` | `DATE` | Sí |  | Fecha de vencimiento, posterior a la emisión (RN-07) |

## Ventas

### comprobante

Comprobantes de venta emitidos en las salas

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `nro` | `INTEGER` | Sí | PK, autogenerado | Número de comprobante |
| `fecha` | `DATE` | Sí |  | Fecha de la venta |
| `id_cliente` | `INTEGER` | Sí | FK → `cliente` | Cliente que compra |
| `id_sala` | `INTEGER` | Sí | FK → `sala_venta` | Sala donde se realizó la venta |
| `subtotal` | `NUMERIC(14,2)` | Sí |  | Suma de cantidad por precio unitario de los renglones, sin descuento (derivado, RN-08) |
| `descuento` | `NUMERIC(14,2)` | Sí |  | Suma de los descuentos de los renglones (derivado, RN-08) |
| `total` | `NUMERIC(14,2)` | Sí |  | Subtotal menos descuento (derivado, RN-08) |

### renglon_comprobante

Vinos incluidos en cada comprobante

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `nro_comprobante` | `INTEGER` | Sí | PK, FK → `comprobante` | Comprobante al que pertenece |
| `cod_vino` | `INTEGER` | Sí | PK, FK → `vino` | Vino vendido |
| `cantidad` | `INTEGER` | Sí |  | Cantidad de botellas |
| `precio_unitario` | `NUMERIC(10,2)` | Sí |  | Precio del vino al momento de la venta |
| `descuento` | `NUMERIC(14,2)` | Sí |  | Importe descontado en el renglón según el descuento del cliente (derivado) |
| `subtotal` | `NUMERIC(14,2)` | Sí |  | Cantidad por precio unitario menos descuento (derivado) |

## Transportistas, ingresos y transferencias

### transportista

Empresas de transporte que trasladan los ingresos

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cod_transporte` | `INTEGER` | Sí | PK, autogenerado | Código de transporte |
| `razon_social` | `VARCHAR(100)` | Sí |  | Razón social |
| `cuit` | `cuit_dom` | Sí |  | CUIT de la empresa |
| `email` | `VARCHAR(120)` | Sí |  | Correo electrónico |
| `telefono` | `VARCHAR(20)` | Sí |  | Teléfono |
| `domicilio` | `VARCHAR(150)` | Sí |  | Domicilio |

### transportista_localidad

Localidades que alcanza el servicio de cada transportista

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cod_transporte` | `INTEGER` | Sí | PK, FK → `transportista` | Transportista |
| `id_localidad` | `INTEGER` | Sí | PK, FK → `localidad` | Localidad cubierta |

### ingreso

Ingresos de vino al depósito central

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cod_ingreso` | `INTEGER` | Sí | PK, autogenerado | Código de ingreso |
| `fecha` | `DATE` | Sí |  | Fecha del ingreso |
| `estado` | `estado_documento` | Sí |  | en_confeccion, terminado o procesado (RN-10) |
| `cod_transporte` | `INTEGER` | Sí | FK → `transportista` | Transportista que efectuó el traslado |
| `cuit_bodega` | `cuit_dom` | Sí | FK → `bodega` | Bodega de origen |

### renglon_ingreso

Vinos incluidos en cada ingreso

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cod_ingreso` | `INTEGER` | Sí | PK, FK → `ingreso` | Ingreso al que pertenece |
| `cod_vino` | `INTEGER` | Sí | PK, FK → `vino` | Vino ingresado |
| `cantidad` | `INTEGER` | Sí |  | Cantidad de botellas |

### transferencia

Solicitudes de vino de una sala al depósito central

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `nro_solicitud` | `INTEGER` | Sí | PK, autogenerado | Número de solicitud |
| `id_sala` | `INTEGER` | Sí | FK → `sala_venta` | Sala solicitante |
| `fecha_confeccion` | `DATE` | Sí |  | Fecha de confección: la actual, no modificable (RN-11) |
| `estado` | `estado_documento` | Sí |  | en_confeccion, terminado o procesado (RN-11) |

### renglon_transferencia

Vinos incluidos en cada transferencia

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `nro_solicitud` | `INTEGER` | Sí | PK, FK → `transferencia` | Transferencia a la que pertenece |
| `cod_vino` | `INTEGER` | Sí | PK, FK → `vino` | Vino solicitado |
| `cantidad` | `INTEGER` | Sí |  | Cantidad de botellas |

## Stock y auditoría

### stock_sala

Stock de cada vino en cada sala

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_sala` | `INTEGER` | Sí | PK, FK → `sala_venta` | Sala |
| `cod_vino` | `INTEGER` | Sí | PK, FK → `vino` | Vino |
| `cantidad` | `INTEGER` | Sí |  | Botellas disponibles, nunca negativo (RN-09) |

### stock_deposito

Stock de cada vino en el depósito central (único)

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `cod_vino` | `INTEGER` | Sí | PK, FK → `vino` | Vino |
| `cantidad` | `INTEGER` | Sí |  | Botellas disponibles, nunca negativo |

### auditoria_precio

Historial de cambios de precio de los vinos (RN-13)

| Columna | Tipo | Obligatorio | Clave | Descripción |
|---|---|---|---|---|
| `id_auditoria` | `INTEGER` | Sí | PK, autogenerado | Identificador del registro |
| `cod_vino` | `INTEGER` | Sí | FK → `vino` | Vino cuyo precio cambió |
| `precio_anterior` | `NUMERIC(10,2)` | Sí |  | Precio antes del cambio |
| `precio_nuevo` | `NUMERIC(10,2)` | Sí |  | Precio después del cambio |
| `fecha_hora` | `TIMESTAMPTZ` | Sí |  | Momento del cambio |
| `usuario` | `VARCHAR(63)` | Sí |  | Usuario de base de datos que hizo el cambio |
