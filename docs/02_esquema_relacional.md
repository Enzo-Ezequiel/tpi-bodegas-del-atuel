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

Se sigue la *Metodología para normalizar hasta 3FN* de la cátedra: verificar 1FN, determinar las claves candidatas, identificar atributos primos y no primos, buscar dependencias parciales (2FN) y transitivas (3FN).

### 2.1 Primera forma normal

Todos los atributos son atómicos y no hay grupos repetitivos:

- La **dirección de la sala** (atributo compuesto) se guarda como `calle` y `numero`.
- Los atributos multivaluados del escenario pasaron a tablas propias: las cepas de un vino (`composicion`), sus maridajes (`vino_maridaje`), los permisos de un exportador (`permiso_exportacion`), las localidades que cubre un transportista (`transportista_localidad`) y los vinos de cada comprobante, ingreso y transferencia (tablas de renglones).

### 2.2 Claves candidatas y dependencias funcionales

Para cada relación se indican sus claves candidatas (la primera es la clave primaria) y las dependencias funcionales. Son **atributos primos** los que forman parte de alguna clave candidata; el resto son no primos.

| Relación | Claves candidatas | Dependencias funcionales |
|---|---|---|
| localidad | id_localidad; (nombre, provincia) | id_localidad → nombre, provincia, codigo_postal, encargado_regional |
| sala_venta | id_sala | id_sala → calle, numero, dia_cierre, id_localidad |
| empleado | cuit | cuit → nombre, fecha_ingreso, salario, id_sala |
| departamento | id_departamento; (nombre, provincia) | id_departamento → nombre, provincia |
| cepa | id_cepa; nombre | id_cepa → nombre, tipo |
| finca | id_finca | id_finca → nombre, superficie_ha, id_departamento |
| parcela | (id_finca, nro_parcela) | (id_finca, nro_parcela) → superficie_ha, anio_plantacion, id_cepa |
| lote_uva | nro_lote; (id_finca, nro_parcela, campania) | nro_lote → id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega |
| analisis_calidad | id_analisis | id_analisis → nro_lote, fecha, brix, ph, acidez_total |
| bodega | cuit | cuit → razon_social, domicilio |
| vino | cod_vino; (nombre, anada, volumen_ml) | cod_vino → nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega |
| composicion | (cod_vino, id_cepa) | (cod_vino, id_cepa) → porcentaje |
| maridaje | id_maridaje; nombre | id_maridaje → nombre, temperatura_servicio |
| vino_maridaje | (cod_vino, id_maridaje) | Solo la trivial: no hay atributos no clave |
| cliente | id_cliente; (tipo_documento, nro_documento) | id_cliente → nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta, tipo_cliente, descuento |
| socio | id_cliente | Solo la trivial |
| distribuidor | id_cliente | id_cliente → zona_cobertura, nro_habilitacion |
| exportador | id_cliente | id_cliente → pais_destino |
| permiso_exportacion | codigo | codigo → id_cliente, fecha_emision, fecha_vencimiento |
| comprobante | nro | nro → fecha, id_cliente, id_sala, subtotal, descuento, total |
| renglon_comprobante | (nro_comprobante, cod_vino) | (nro_comprobante, cod_vino) → cantidad, precio_unitario, descuento, subtotal |
| transportista | cod_transporte; cuit | cod_transporte → razon_social, cuit, email, telefono, domicilio |
| transportista_localidad | (cod_transporte, id_localidad) | Solo la trivial |
| ingreso | cod_ingreso | cod_ingreso → fecha, estado, cod_transporte, cuit_bodega |
| renglon_ingreso | (cod_ingreso, cod_vino) | (cod_ingreso, cod_vino) → cantidad |
| transferencia | nro_solicitud | nro_solicitud → id_sala, fecha_confeccion, estado |
| renglon_transferencia | (nro_solicitud, cod_vino) | (nro_solicitud, cod_vino) → cantidad |
| stock_sala | (id_sala, cod_vino) | (id_sala, cod_vino) → cantidad |
| stock_deposito | cod_vino | cod_vino → cantidad |
| auditoria_precio | id_auditoria | id_auditoria → cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario |

En las relaciones con una segunda clave candidata, esa clave también determina a todos los atributos. En `002_constraints.sql` se declararon como UNIQUE las de `lote_uva` (es la regla RN-04), `vino`, `transportista` y `cliente`. Las de los catálogos (`localidad`, `departamento`, `cepa`, `maridaje`) no se declararon: son tablas chicas que se cargan una sola vez desde CSV. Es una decisión de alcance, no de diseño; agregarlas sería una línea cada una.

### 2.3 Segunda forma normal

Solo puede haber dependencias parciales en las relaciones con clave compuesta. En todas, los atributos no primos dependen de la clave completa:

| Relación | Clave | Atributos no primos | ¿Dependen de toda la clave? |
|---|---|---|---|
| parcela | (id_finca, nro_parcela) | superficie_ha, anio_plantacion, id_cepa | Sí: describen a esa parcela, no a la finca |
| composicion | (cod_vino, id_cepa) | porcentaje | Sí: el porcentaje es de esa cepa en ese vino |
| renglon_comprobante | (nro_comprobante, cod_vino) | cantidad, precio_unitario, descuento, subtotal | Sí (ver notas) |
| renglon_ingreso | (cod_ingreso, cod_vino) | cantidad | Sí |
| renglon_transferencia | (nro_solicitud, cod_vino) | cantidad | Sí |
| stock_sala | (id_sala, cod_vino) | cantidad | Sí |
| vino_maridaje, transportista_localidad | toda la relación | — | No tienen atributos no primos |

**Nota sobre `precio_unitario`.** Podría parecer que depende solo de `cod_vino`. No es así: guarda el precio del vino **en el momento de esa venta**. Si después cambia `vino.precio`, el renglón conserva el valor histórico, así que `cod_vino → precio_unitario` no se cumple.

**Nota sobre `descuento` del renglón.** Se guarda el **importe** descontado en ese renglón, no el porcentaje del cliente. El porcentaje sería igual en todos los renglones de un mismo comprobante, es decir que dependería solo de `nro_comprobante`: una dependencia parcial que violaría 2FN. El importe, en cambio, depende de la cantidad y del precio de ese vino en ese comprobante, o sea de la clave completa.

Las dependencias parciales que existían en el escenario se resolvieron al modelar:

- (nro_comprobante, cod_vino) → fecha, cliente, sala: dependen solo del comprobante → relación `comprobante`.
- (cod_vino, id_cepa) → nombre de la cepa, tipo: dependen solo de la cepa → relación `cepa`.
- La temperatura de servicio depende solo del maridaje, no del par vino-maridaje → queda en `maridaje`.

### 2.4 Tercera forma normal

Dependencias transitivas detectadas en el escenario y cómo se eliminaron:

| Dependencia transitiva | Problema | Solución |
|---|---|---|
| id_sala → id_localidad → encargado_regional | El encargado se repetiría en cada sala de la localidad (RN-02) | `encargado_regional` está en `localidad`; la sala solo guarda `id_localidad` |
| id_sala → id_localidad → nombre, provincia, codigo_postal | Datos de la localidad repetidos por sala | Relación `localidad` |
| id_finca → departamento → provincia | La provincia se repetiría en cada finca del departamento | Relación `departamento`; la finca solo guarda `id_departamento` |
| id_cliente → id_localidad → nombre, provincia | Igual que en sala | El cliente referencia a `localidad` |
| (id_finca, nro_parcela) → id_cepa → nombre, tipo | Datos de la cepa repetidos por parcela | Relación `cepa` |
| cod_vino → cuit_bodega → razon_social, domicilio | Datos de la bodega repetidos por vino | Relación `bodega` |
| cod_ingreso → cod_transporte → razon_social, cuit, … | Datos del transportista repetidos por ingreso | Relación `transportista` |

Fuera de las excepciones de la sección 2.5, en todas las relaciones cada atributo no primo depende directamente de la clave y de nada más.

### 2.5 Excepciones deliberadas: atributos derivados almacenados

Estos atributos se calculan a partir de otros, así que en sentido estricto introducen dependencias entre atributos no clave y **no cumplen 3FN**. Se almacenan igual, a conciencia:

| Atributo | Cómo se obtiene | Por qué se almacena |
|---|---|---|
| `renglon_comprobante.descuento` | cantidad × precio_unitario × porcentaje del cliente al momento de la venta | El porcentaje del cliente puede cambiar después; el importe es un dato histórico de la venta |
| `renglon_comprobante.subtotal` | cantidad × precio_unitario − descuento | El enunciado lo pide como dato del renglón |
| `comprobante.subtotal` | Suma de cantidad × precio_unitario de sus renglones | El enunciado lo pide como dato del comprobante |
| `comprobante.descuento` | Suma de los descuentos de sus renglones | Ídem |
| `comprobante.total` | subtotal − descuento | Ídem |

El apunte de la cátedra indica que los atributos derivados en general no se almacenan. Acá el enunciado los lista como atributos del comprobante y del renglón (secciones 3.4 y 5), y además evitan recalcular 500.000 renglones en cada consulta de ventas. El riesgo de una redundancia así es que los valores queden inconsistentes; se evita porque **nunca se cargan a mano**: los escriben una función y un trigger de la base (RN-08) y las consultas de control de la etapa 3 verifican que cierren.

**`lote_uva.campania`** es un caso aparte: es el año de `fecha_cosecha`, pero forma parte de la clave candidata (id_finca, nro_parcela, campania), así que es un atributo primo y no viola 3FN. Se almacena porque hace falta para el UNIQUE de «una cosecha por parcela y campaña» (RN-04). Que coincida con el año de `fecha_cosecha` no se controla en la base (no hay un CHECK para eso): queda como límite conocido.

### 2.6 Otros casos que merecen explicación

- **`localidad.provincia` y `codigo_postal`.** En `localidad` no hay dependencia entre atributos no primos: un mismo código postal corresponde a varias localidades, así que no determina a ningún otro atributo. No se creó una relación `provincia` porque del escenario no surge ningún atributo propio de la provincia.
- **`cliente.descuento` frente a `tipo_cliente`.** Si el descuento dependiera siempre del tipo (tipo_cliente → descuento) sería una dependencia transitiva. No lo es: el tipo solo fija el valor inicial, y la consulta U6 del enunciado sube a 35 % el descuento de algunos exportadores, así que dos clientes del mismo tipo pueden tener descuentos distintos.
