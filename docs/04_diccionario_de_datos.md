# Diccionario de datos

Generado desde el catálogo de PostgreSQL con `scripts/diccionario.sql`. No editar a mano.

## Tipos propios

| Tipo | Clase | Definición |
|---|---|---|
| cuit_dom | DOMAIN | character(11) CHECK ((VALUE ~ '^[0-9]{11}$'::text)) |
| dia_semana | ENUM | lunes, martes, miercoles, jueves, viernes, sabado, domingo |
| estado_documento | ENUM | en_confeccion, terminado, procesado |
| porcentaje_dom | DOMAIN | numeric(5,2) CHECK (((VALUE >= (0)::numeric) AND (VALUE <= (100)::numeric))) |
| tipo_cepa | ENUM | tinta, blanca |
| tipo_cliente | ENUM | socio, distribuidor, exportador |
| tipo_documento | ENUM | DNI, CUIT, PASAPORTE |
| tipo_vino | ENUM | tinto, blanco, rosado, espumante |

## analisis_calidad

Analisis de calidad practicados a un lote de uva

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_analisis | integer | No | PK; autogenerado | Identificador del analisis |
| nro_lote | integer | No | FK → lote_uva | Lote analizado |
| fecha | date | No |  | Fecha del analisis |
| brix | numeric(4,2) | No |  | Grado Brix |
| ph | numeric(3,2) | No |  | pH |
| acidez_total | numeric(4,2) | No |  | Acidez total en g/L |

## auditoria_precio

Historial de cambios de precio de los vinos (RN-13)

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_auditoria | integer | No | PK; autogenerado | Identificador del registro |
| cod_vino | integer | No | FK → vino | Vino cuyo precio cambio |
| precio_anterior | numeric(10,2) | No |  | Precio antes del cambio |
| precio_nuevo | numeric(10,2) | No |  | Precio despues del cambio |
| fecha_hora | timestamp with time zone | No |  | Momento del cambio |
| usuario | character varying(63) | No |  | Usuario de base de datos que hizo el cambio |

## bodega

Bodegas del grupo que elaboran los vinos

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cuit | cuit_dom | No | PK | CUIT de la bodega (clave natural) |
| razon_social | character varying(100) | No |  | Razon social |
| domicilio | character varying(150) | No |  | Domicilio |

## cepa

Catalogo de cepas (variedades de uva)

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cepa | integer | No | PK; autogenerado | Identificador de la cepa |
| nombre | character varying(60) | No |  | Nombre de la cepa |
| tipo | tipo_cepa | No |  | Tinta o blanca |

## cliente

Clientes (supertipo de socio, distribuidor y exportador)

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | integer | No | PK; autogenerado | Identificador del cliente |
| nombre_razon_social | character varying(120) | No |  | Apellido y nombre, o razon social |
| tipo_documento | tipo_documento | No |  | Tipo de documento |
| nro_documento | character varying(15) | No |  | Numero de documento |
| direccion | character varying(150) | No |  | Direccion |
| id_localidad | integer | No | FK → localidad | Localidad donde reside |
| fecha_alta | date | No |  | Fecha de alta como cliente |
| tipo_cliente | tipo_cliente | No |  | Discriminador de la jerarquia |
| descuento | porcentaje_dom | No |  | Porcentaje de descuento; por defecto segun el tipo (RN-06) |

## composicion

Cepas que componen cada vino y su porcentaje de corte

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | integer | No | PK; FK → vino | Vino |
| id_cepa | integer | No | PK; FK → cepa | Cepa |
| porcentaje | porcentaje_dom | No |  | Porcentaje de corte; la suma por vino es 100 (RN-05) |

## comprobante

Comprobantes de venta emitidos en las salas

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro | integer | No | PK; autogenerado | Numero de comprobante |
| fecha | date | No |  | Fecha de la venta |
| id_cliente | integer | No | FK → cliente | Cliente que compra |
| id_sala | integer | No | FK → sala_venta | Sala donde se realizo la venta |
| subtotal | numeric(14,2) | No |  | Suma de cantidad por precio unitario de los renglones, sin descuento (derivado, RN-08) |
| descuento | numeric(14,2) | No |  | Suma de los descuentos de los renglones (derivado, RN-08) |
| total | numeric(14,2) | No |  | Subtotal menos descuento (derivado, RN-08) |

## departamento

Departamentos provinciales donde se ubican las fincas

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_departamento | integer | No | PK; autogenerado | Identificador del departamento |
| nombre | character varying(60) | No |  | Nombre del departamento |
| provincia | character varying(50) | No |  | Provincia del departamento |

## distribuidor

Subtipo de cliente: distribuidor

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | integer | No | PK; FK → cliente | Cliente que es distribuidor |
| zona_cobertura | character varying(100) | No |  | Zona de cobertura |
| nro_habilitacion | character varying(20) | No |  | Numero de habilitacion |

## empleado

Empleados de las salas de venta

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cuit | cuit_dom | No | PK | CUIT del empleado (clave natural) |
| nombre | character varying(100) | No |  | Apellido y nombre |
| fecha_ingreso | date | No |  | Fecha de ingreso laboral |
| salario | numeric(12,2) | No |  | Salario mensual en pesos |
| id_sala | integer | No | FK → sala_venta | Sala en la que trabaja (RN-03) |

## exportador

Subtipo de cliente: exportador

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | integer | No | PK; FK → cliente | Cliente que es exportador |
| pais_destino | character varying(60) | No |  | Pais de destino principal |

## finca

Fincas donde la empresa cultiva uva

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_finca | integer | No | PK; autogenerado | Identificador de la finca |
| nombre | character varying(80) | No |  | Nombre de la finca |
| superficie_ha | numeric(8,2) | No |  | Superficie total en hectareas |
| id_departamento | integer | No | FK → departamento | Departamento donde se ubica |

## ingreso

Ingresos de vino al deposito central

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_ingreso | integer | No | PK; autogenerado | Codigo de ingreso |
| fecha | date | No |  | Fecha del ingreso |
| estado | estado_documento | No |  | en_confeccion, terminado o procesado (RN-10) |
| cod_transporte | integer | No | FK → transportista | Transportista que efectuo el traslado |
| cuit_bodega | cuit_dom | No | FK → bodega | Bodega de origen |

## localidad

Localidades donde hay salas, clientes o cobertura de transporte

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_localidad | integer | No | PK; autogenerado | Identificador subrogado (el codigo postal se repite entre localidades) |
| nombre | character varying(80) | No |  | Nombre de la localidad |
| provincia | character varying(50) | No |  | Provincia a la que pertenece |
| codigo_postal | character varying(8) | No |  | Codigo postal |
| encargado_regional | character varying(100) | No |  | Nombre del responsable comercial, unico por localidad (RN-02) |

## lote_uva

Lote de uva generado por la cosecha de una parcela en una campania

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_lote | integer | No | PK; autogenerado | Numero de lote |
| id_finca | integer | No | FK → parcela | Finca de la parcela cosechada |
| nro_parcela | smallint | No | FK → parcela | Parcela cosechada |
| campania | smallint | No |  | Anio de cosecha; una cosecha por parcela y campania (RN-04) |
| fecha_cosecha | date | No |  | Fecha de cosecha |
| kilos | numeric(10,2) | No |  | Kilos cosechados |
| cuit_bodega | cuit_dom | No | FK → bodega | Bodega a la que se entrego el lote |

## maridaje

Catalogo de maridajes

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_maridaje | integer | No | PK; autogenerado | Identificador del maridaje |
| nombre | character varying(60) | No |  | Nombre del maridaje |
| temperatura_servicio | numeric(3,1) | No |  | Temperatura de servicio sugerida en grados Celsius |

## parcela

Parcelas de una finca (entidad debil de finca)

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_finca | integer | No | PK; FK → finca | Finca a la que pertenece |
| nro_parcela | smallint | No | PK | Numero de parcela dentro de la finca |
| superficie_ha | numeric(7,2) | No |  | Superficie en hectareas |
| anio_plantacion | smallint | No |  | Anio de plantacion |
| id_cepa | integer | No | FK → cepa | Cepa plantada, una sola por parcela (RN-04) |

## permiso_exportacion

Permisos de exportacion de un exportador

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| codigo | character varying(20) | No | PK | Codigo del permiso |
| id_cliente | integer | No | FK → exportador | Exportador titular |
| fecha_emision | date | No |  | Fecha de emision |
| fecha_vencimiento | date | No |  | Fecha de vencimiento, posterior a la emision (RN-07) |

## renglon_comprobante

Vinos incluidos en cada comprobante

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_comprobante | integer | No | PK; FK → comprobante | Comprobante al que pertenece |
| cod_vino | integer | No | PK; FK → vino | Vino vendido |
| cantidad | integer | No |  | Cantidad de botellas |
| precio_unitario | numeric(10,2) | No |  | Precio del vino al momento de la venta |
| descuento | numeric(14,2) | No |  | Importe descontado en el renglon segun el descuento del cliente (derivado) |
| subtotal | numeric(14,2) | No |  | Cantidad por precio unitario menos descuento (derivado) |

## renglon_ingreso

Vinos incluidos en cada ingreso

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_ingreso | integer | No | PK; FK → ingreso | Ingreso al que pertenece |
| cod_vino | integer | No | PK; FK → vino | Vino ingresado |
| cantidad | integer | No |  | Cantidad de botellas |

## renglon_transferencia

Vinos incluidos en cada transferencia

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_solicitud | integer | No | PK; FK → transferencia | Transferencia a la que pertenece |
| cod_vino | integer | No | PK; FK → vino | Vino solicitado |
| cantidad | integer | No |  | Cantidad de botellas |

## sala_venta

Salas de venta de la red

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_sala | integer | No | PK; autogenerado | Identificador de la sala |
| calle | character varying(80) | No |  | Calle de la direccion |
| numero | integer | No |  | Numero de la direccion |
| dia_cierre | dia_semana | No |  | Dia de cierre semanal |
| id_localidad | integer | No | FK → localidad | Localidad donde esta ubicada (RN-02) |

## socio

Subtipo de cliente: socio del club (sin atributos propios)

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_cliente | integer | No | PK; FK → cliente | Cliente que es socio |

## stock_deposito

Stock de cada vino en el deposito central (unico)

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | integer | No | PK; FK → vino | Vino |
| cantidad | integer | No |  | Botellas disponibles, nunca negativo |

## stock_sala

Stock de cada vino en cada sala

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| id_sala | integer | No | PK; FK → sala_venta | Sala |
| cod_vino | integer | No | PK; FK → vino | Vino |
| cantidad | integer | No |  | Botellas disponibles, nunca negativo (RN-09) |

## transferencia

Solicitudes de vino de una sala al deposito central

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| nro_solicitud | integer | No | PK; autogenerado | Numero de solicitud |
| id_sala | integer | No | FK → sala_venta | Sala solicitante |
| fecha_confeccion | date | No |  | Fecha de confeccion: la actual, no modificable (RN-11) |
| estado | estado_documento | No |  | en_confeccion, terminado o procesado (RN-11) |

## transportista

Empresas de transporte que trasladan los ingresos

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_transporte | integer | No | PK; autogenerado | Codigo de transporte |
| razon_social | character varying(100) | No |  | Razon social |
| cuit | cuit_dom | No |  | CUIT de la empresa |
| email | character varying(120) | No |  | Correo electronico |
| telefono | character varying(20) | No |  | Telefono |
| domicilio | character varying(150) | No |  | Domicilio |

## transportista_localidad

Localidades que alcanza el servicio de cada transportista

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_transporte | integer | No | PK; FK → transportista | Transportista |
| id_localidad | integer | No | PK; FK → localidad | Localidad cubierta |

## vino

Vinos elaborados por las bodegas del grupo

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | integer | No | PK; autogenerado | Codigo del vino |
| nombre | character varying(80) | No |  | Nombre comercial |
| tipo | tipo_vino | No |  | Tinto, blanco, rosado o espumante |
| anada | smallint | No |  | Aniada (anio de cosecha de la uva) |
| volumen_ml | integer | No |  | Presentacion: volumen en mililitros |
| graduacion | numeric(4,2) | No |  | Graduacion alcoholica en grados |
| precio | numeric(10,2) | No |  | Precio de venta, unico para toda la red (RN-01) |
| cuit_bodega | cuit_dom | No | FK → bodega | Bodega que lo elabora |

## vino_maridaje

Maridajes recomendados para cada vino

| Columna | Tipo | Nulos | Restricciones | Descripción |
|---|---|---|---|---|
| cod_vino | integer | No | PK; FK → vino | Vino |
| id_maridaje | integer | No | PK; FK → maridaje | Maridaje recomendado |
