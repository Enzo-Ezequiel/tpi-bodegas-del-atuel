# Etapa 1 — Esquema relacional y normalización

## 1. Esquema relacional

Derivado del DER con las reglas del apunte *Modelo Relacional*: una relación por entidad, las relaciones 1:N pasan como clave foránea al lado «muchos», las N:M generan una relación nueva y la entidad débil incorpora la clave de la fuerte.

Notación: <u>clave primaria subrayada</u>, *clave foránea en cursiva*.

### Localidades, salas y empleados

- **localidad** (<u>id_localidad</u>, nombre, provincia, codigo_postal, encargado_regional)
- **sala_venta** (<u>id_sala</u>, calle, numero, dia_cierre, *id_localidad*)
- **empleado** (<u>cuit</u>, nombre, fecha_ingreso, salario, *id_sala*)

### Producción de uva

- **departamento** (<u>id_departamento</u>, nombre, provincia)
- **cepa** (<u>id_cepa</u>, nombre, tipo)
- **finca** (<u>id_finca</u>, nombre, superficie_ha, *id_departamento*)
- **parcela** (<u>*id_finca*, nro_parcela</u>, superficie_ha, anio_plantacion, *id_cepa*)
- **lote_uva** (<u>nro_lote</u>, *id_finca*, *nro_parcela*, campania, fecha_cosecha, kilos, *cuit_bodega*)
- **analisis_calidad** (<u>id_analisis</u>, *nro_lote*, fecha, brix, ph, acidez_total)

### Bodegas y vinos

- **bodega** (<u>cuit</u>, razon_social, domicilio)
- **vino** (<u>cod_vino</u>, nombre, tipo, anada, volumen_ml, graduacion, precio, *cuit_bodega*)
- **composicion** (<u>*cod_vino*, *id_cepa*</u>, porcentaje)
- **maridaje** (<u>id_maridaje</u>, nombre, temperatura_servicio)
- **vino_maridaje** (<u>*cod_vino*, *id_maridaje*</u>)

### Clientes y ventas

- **cliente** (<u>id_cliente</u>, nombre_razon_social, tipo_documento, nro_documento, direccion, *id_localidad*, fecha_alta, tipo_cliente, descuento)
- **socio** (<u>*id_cliente*</u>)
- **distribuidor** (<u>*id_cliente*</u>, zona_cobertura, nro_habilitacion)
- **exportador** (<u>*id_cliente*</u>, pais_destino)
- **permiso_exportacion** (<u>codigo</u>, *id_cliente*, fecha_emision, fecha_vencimiento)
- **comprobante** (<u>nro</u>, fecha, *id_cliente*, *id_sala*, subtotal, descuento, total)
- **renglon_comprobante** (<u>*nro_comprobante*, *cod_vino*</u>, cantidad, precio_unitario, descuento, subtotal)

### Transporte, ingresos, transferencias y stock

- **transportista** (<u>cod_transporte</u>, razon_social, cuit, email, telefono, domicilio)
- **transportista_localidad** (<u>*cod_transporte*, *id_localidad*</u>)
- **ingreso** (<u>cod_ingreso</u>, fecha, estado, *cod_transporte*, *cuit_bodega*)
- **renglon_ingreso** (<u>*cod_ingreso*, *cod_vino*</u>, cantidad)
- **transferencia** (<u>nro_solicitud</u>, *id_sala*, fecha_confeccion, estado)
- **renglon_transferencia** (<u>*nro_solicitud*, *cod_vino*</u>, cantidad)
- **stock_sala** (<u>*id_sala*, *cod_vino*</u>, cantidad)
- **stock_deposito** (<u>*cod_vino*</u>, cantidad)
- **auditoria_precio** (<u>id_auditoria</u>, *cod_vino*, precio_anterior, precio_nuevo, fecha_hora, usuario)

### Claves foráneas

| Tabla | Columna(s) | Referencia |
|---|---|---|
| sala_venta | id_localidad | localidad |
| empleado | id_sala | sala_venta |
| finca | id_departamento | departamento |
| parcela | id_finca | finca |
| parcela | id_cepa | cepa |
| lote_uva | (id_finca, nro_parcela) | parcela |
| lote_uva | cuit_bodega | bodega |
| analisis_calidad | nro_lote | lote_uva |
| vino | cuit_bodega | bodega |
| composicion | cod_vino | vino |
| composicion | id_cepa | cepa |
| vino_maridaje | cod_vino | vino |
| vino_maridaje | id_maridaje | maridaje |
| cliente | id_localidad | localidad |
| socio, distribuidor, exportador | id_cliente | cliente |
| permiso_exportacion | id_cliente | exportador |
| comprobante | id_cliente | cliente |
| comprobante | id_sala | sala_venta |
| renglon_comprobante | nro_comprobante | comprobante |
| renglon_comprobante | cod_vino | vino |
| transportista_localidad | cod_transporte | transportista |
| transportista_localidad | id_localidad | localidad |
| ingreso | cod_transporte | transportista |
| ingreso | cuit_bodega | bodega |
| renglon_ingreso | cod_ingreso | ingreso |
| renglon_ingreso | cod_vino | vino |
| transferencia | id_sala | sala_venta |
| renglon_transferencia | nro_solicitud | transferencia |
| renglon_transferencia | cod_vino | vino |
| stock_sala | id_sala | sala_venta |
| stock_sala | cod_vino | vino |
| stock_deposito | cod_vino | vino |
| auditoria_precio | cod_vino | vino |

## 2. Normalización hasta 3FN

Se sigue la *Metodología para normalizar hasta 3FN* de la cátedra: verificar 1FN, determinar claves candidatas, buscar dependencias parciales (2FN) y transitivas (3FN).

### 2.1 Primera forma normal

Todos los atributos son atómicos y no hay grupos repetitivos:

- La **dirección de la sala** (atributo compuesto) se guarda como `calle` y `numero`.
- Los atributos multivaluados del escenario pasaron a tablas propias: las cepas de un vino (`composicion`), sus maridajes (`vino_maridaje`), los permisos de un exportador (`permiso_exportacion`), las localidades que cubre un transportista (`transportista_localidad`) y los vinos de cada comprobante, ingreso y transferencia (tablas de renglones).

### 2.2 Segunda forma normal

Solo puede haber dependencias parciales en las tablas con clave compuesta. En todas, los atributos no clave dependen de la clave completa:

| Tabla | Clave | Atributos no clave | ¿Dependen de toda la clave? |
|---|---|---|---|
| parcela | (id_finca, nro_parcela) | superficie_ha, anio_plantacion, id_cepa | Sí: describen a esa parcela, no a la finca |
| composicion | (cod_vino, id_cepa) | porcentaje | Sí: el porcentaje es de esa cepa en ese vino |
| renglon_comprobante | (nro_comprobante, cod_vino) | cantidad, precio_unitario, descuento, subtotal | Sí (ver nota) |
| renglon_ingreso | (cod_ingreso, cod_vino) | cantidad | Sí |
| renglon_transferencia | (nro_solicitud, cod_vino) | cantidad | Sí |
| stock_sala | (id_sala, cod_vino) | cantidad | Sí |
| vino_maridaje, transportista_localidad | toda la tabla | — | No tienen atributos no clave |

**Nota sobre `precio_unitario` y `descuento` del renglón.** Podría parecer que `precio_unitario` depende solo de `cod_vino` (sería parcial) y que `descuento` depende solo del comprobante. No es así: guardan el precio del vino y el descuento del cliente **en el momento de esa venta**. Si mañana cambia `vino.precio`, el renglón conserva el valor histórico, así que `cod_vino → precio_unitario` no se cumple.

Las dependencias parciales que sí existían en el escenario se resolvieron al modelar:

- (nro_comprobante, cod_vino) → fecha, cliente, sala: dependen solo del comprobante → tabla `comprobante`.
- (cod_vino, id_cepa) → nombre de la cepa, tipo: dependen solo de la cepa → tabla `cepa`.
- La temperatura de servicio depende solo del maridaje, no del par vino-maridaje → queda en `maridaje`.

### 2.3 Tercera forma normal

Dependencias transitivas detectadas en el escenario y cómo se eliminaron:

| Dependencia transitiva | Problema | Solución |
|---|---|---|
| id_sala → id_localidad → encargado_regional | El encargado se repetiría en cada sala de la localidad (RN-02) | `encargado_regional` está en `localidad`; la sala solo guarda `id_localidad` |
| id_sala → id_localidad → nombre, provincia, codigo_postal | Datos de la localidad repetidos por sala | Tabla `localidad` |
| id_finca → departamento → provincia | La provincia se repetiría en cada finca del departamento | Tabla `departamento`; la finca solo guarda `id_departamento` |
| id_cliente → id_localidad → nombre, provincia | Igual que en sala | El cliente referencia a `localidad` |
| (id_finca, nro_parcela) → id_cepa → nombre, tipo | Datos de la cepa repetidos por parcela | Tabla `cepa` |
| cod_vino → cuit_bodega → razon_social, domicilio | Datos de la bodega repetidos por vino | Tabla `bodega` |
| cod_ingreso → cod_transporte → razon_social, cuit, … | Datos del transportista repetidos por ingreso | Tabla `transportista` |

En el resto de las tablas todo atributo no clave depende directamente de la clave primaria.

### 2.4 Casos que merecen explicación

- **`localidad.provincia` y `codigo_postal`.** En `localidad` no hay dependencia entre atributos no clave: un mismo código postal corresponde a varias localidades y el nombre de una localidad se repite en distintas provincias, así que ninguno determina al otro. No se creó una tabla `provincia` porque del escenario no surge ningún atributo propio de la provincia.
- **`cliente.descuento` frente a `tipo_cliente`.** Si el descuento dependiera siempre del tipo (tipo_cliente → descuento) sería una dependencia transitiva. No lo es: el tipo solo fija el valor inicial, y la consulta U6 del enunciado sube a 35 % el descuento de algunos exportadores, así que dos clientes del mismo tipo pueden tener descuentos distintos.
- **Atributos derivados almacenados.** `comprobante.subtotal`, `descuento` y `total`, y `renglon_comprobante.subtotal` se calculan a partir de otros datos. El apunte de la cátedra indica que los derivados en general no se almacenan; acá el enunciado los pide como atributos del comprobante (sección 5) y deben conservar el valor histórico de la venta. La consistencia la garantiza la base con una función y un trigger (RN-08), nunca se cargan a mano.
- **Claves candidatas alternativas.** `vino` (nombre, anada, volumen_ml), `lote_uva` (id_finca, nro_parcela, campania), `cliente` (tipo_documento, nro_documento), `transportista` (cuit), `cepa` (nombre) y `maridaje` (nombre) tienen una segunda clave candidata. Se protegen con UNIQUE en `002_constraints.sql`; no generan dependencias que violen 3FN porque todo atributo depende de una clave candidata completa.
