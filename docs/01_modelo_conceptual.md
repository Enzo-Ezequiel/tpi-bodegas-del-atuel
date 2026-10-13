# Etapa 1 — Modelo conceptual

Relevamiento del escenario (sección 3 del enunciado): entidades, atributos, claves y relaciones con sus cardinalidades. Es la base para dibujar el DER.

Notación de atributos: **clave primaria**, *clave foránea*, `(U)` único, `(D)` derivado.

## 1. Entidades y atributos

### 1.1 Localidades, salas y empleados

| Entidad | Atributos | Notas |
|---|---|---|
| LOCALIDAD | **id_localidad**, nombre, provincia, codigo_postal, encargado_regional | Clave subrogada: el código postal se repite entre localidades. (nombre, provincia) `(U)` |
| SALA_VENTA | **id_sala**, calle, numero, dia_cierre, *id_localidad* | El encargado no se guarda acá: depende de la localidad (RN-02) |
| EMPLEADO | **cuit**, nombre, fecha_ingreso, salario, *id_sala* | Clave natural: el CUIT identifica a la persona y es estable |

### 1.2 Producción de uva

| Entidad | Atributos | Notas |
|---|---|---|
| DEPARTAMENTO | **id_departamento**, nombre, provincia | Se separa de FINCA para evitar la dependencia transitiva finca → departamento → provincia. (nombre, provincia) `(U)` |
| FINCA | **id_finca**, nombre, superficie_ha, *id_departamento* | |
| PARCELA | ***id_finca*, nro_parcela**, superficie_ha, anio_plantacion, *id_cepa* | **Entidad débil** de FINCA: `nro_parcela` es su discriminador |
| CEPA | **id_cepa**, nombre `(U)`, tipo (tinta / blanca) | Catálogo real |
| LOTE_UVA | **nro_lote**, *(id_finca, nro_parcela)*, campania, fecha_cosecha, kilos, *cuit_bodega* | (id_finca, nro_parcela, campania) `(U)`: una cosecha por parcela y campaña (RN-04) |
| ANALISIS_CALIDAD | **id_analisis**, *nro_lote*, fecha, brix, ph, acidez_total | Varios por lote |

### 1.3 Bodegas y vinos

| Entidad | Atributos | Notas |
|---|---|---|
| BODEGA | **cuit**, razon_social, domicilio | |
| VINO | **cod_vino**, nombre, tipo, anada, volumen_ml, graduacion, precio, *cuit_bodega* | (nombre, anada, volumen_ml) `(U)`. Precio único para toda la red (RN-01) |
| MARIDAJE | **id_maridaje**, nombre `(U)`, temperatura_servicio | Catálogo |

### 1.4 Clientes y ventas

| Entidad | Atributos | Notas |
|---|---|---|
| CLIENTE | **id_cliente**, nombre_razon_social, tipo_documento, nro_documento, direccion, *id_localidad*, fecha_alta, tipo_cliente, descuento | Supertipo. (tipo_documento, nro_documento) `(U)` |
| SOCIO | ***id_cliente*** | Subtipo sin atributos propios |
| DISTRIBUIDOR | ***id_cliente***, zona_cobertura, nro_habilitacion | Subtipo |
| EXPORTADOR | ***id_cliente***, pais_destino | Subtipo |
| PERMISO_EXPORTACION | **codigo**, *id_cliente*, fecha_emision, fecha_vencimiento | Solo de exportadores. Vencimiento > emisión (RN-07) |
| COMPROBANTE | **nro**, fecha, *id_cliente*, *id_sala*, subtotal `(D)`, descuento `(D)`, total `(D)` | Los importes los escribe la base, no se cargan a mano (RN-08) |

**Jerarquía de CLIENTE:** *total* (todo cliente es de algún tipo) y *disjunta* (de uno solo).

### 1.5 Stock, ingresos y transferencias

| Entidad | Atributos | Notas |
|---|---|---|
| TRANSPORTISTA | **cod_transporte**, razon_social, cuit `(U)`, email, telefono, domicilio | |
| INGRESO | **cod_ingreso**, fecha, estado, *cod_transporte*, *cuit_bodega* | Estado: en_confeccion → terminado → procesado (RN-10) |
| TRANSFERENCIA | **nro_solicitud**, *id_sala*, fecha_confeccion, estado | Fecha = la actual, no modificable (RN-11) |
| AUDITORIA_PRECIO | **id_auditoria**, *cod_vino*, precio_anterior, precio_nuevo, fecha_hora, usuario | La completa un trigger (RN-13) |

El **depósito central** es único, así que no hay una entidad DEPÓSITO. Su stock se modela como STOCK_DEPOSITO (cantidad), entidad débil de VINO con relación 1:1: existe a lo sumo una fila por vino y se identifica por él.

## 2. Relaciones

Las cardinalidades (mín, máx) escritas junto a una entidad indican con cuántas instancias de **esa** entidad se relaciona una instancia de la otra. Es la misma convención del DER (`docs/der/`).

### 2.1 Relaciones 1:N

| Relación | Lado «uno» | Lado «muchos» | Lectura |
|---|---|---|---|
| ubicada_en | LOCALIDAD (1,1) | SALA_VENTA (0,N) | Una sala está en una sola localidad; una localidad puede tener varias salas o ninguna |
| trabaja_en | SALA_VENTA (1,1) | EMPLEADO (0,N) | Cada empleado trabaja en una sola sala (RN-03) |
| se_ubica_en | DEPARTAMENTO (1,1) | FINCA (0,N) | |
| se_divide_en | FINCA (1,1) | PARCELA (1,N) | Relación identificadora de la entidad débil |
| plantada_con | CEPA (1,1) | PARCELA (0,N) | Una parcela tiene una sola cepa (RN-04) |
| se_cosecha | PARCELA (1,1) | LOTE_UVA (0,N) | A lo sumo un lote por campaña |
| entregado_a | BODEGA (1,1) | LOTE_UVA (0,N) | |
| se_analiza | LOTE_UVA (1,1) | ANALISIS_CALIDAD (1,N) | Uno o más análisis por lote |
| elabora | BODEGA (1,1) | VINO (0,N) | |
| vive_en | LOCALIDAD (1,1) | CLIENTE (0,N) | |
| tiene_permiso | EXPORTADOR (1,1) | PERMISO_EXPORTACION (0,N) | |
| compra | CLIENTE (1,1) | COMPROBANTE (0,N) | |
| se_emite_en | SALA_VENTA (1,1) | COMPROBANTE (0,N) | |
| traslada | TRANSPORTISTA (1,1) | INGRESO (0,N) | |
| origina | BODEGA (1,1) | INGRESO (0,N) | |
| solicita | SALA_VENTA (1,1) | TRANSFERENCIA (0,N) | |
| registra_cambio | VINO (1,1) | AUDITORIA_PRECIO (0,N) | |
| en_deposito | VINO (1,1) | STOCK_DEPOSITO (0,1) | Relación 1:1 identificadora: un vino tiene a lo sumo una fila de stock en el depósito |

### 2.2 Relaciones N:M

| Relación | Entre | Atributos propios | Tabla resultante |
|---|---|---|---|
| composicion | VINO (0,N) — CEPA (1,N) | porcentaje | COMPOSICION (**cod_vino, id_cepa**). Suma 100 por vino (RN-05) |
| recomienda | VINO (0,N) — MARIDAJE (1,N) | — | VINO_MARIDAJE (**cod_vino, id_maridaje**) |
| renglon de venta | COMPROBANTE (0,N) — VINO (1,N) | cantidad, precio_unitario, descuento, subtotal `(D)` | RENGLON_COMPROBANTE (**nro_comprobante, cod_vino**) |
| cubre | TRANSPORTISTA (0,N) — LOCALIDAD (0,N) | — | TRANSPORTISTA_LOCALIDAD (**cod_transporte, id_localidad**) |
| renglon de ingreso | INGRESO (0,N) — VINO (1,N) | cantidad | RENGLON_INGRESO (**cod_ingreso, cod_vino**) |
| renglon de transferencia | TRANSFERENCIA (0,N) — VINO (1,N) | cantidad | RENGLON_TRANSFERENCIA (**nro_solicitud, cod_vino**) |
| stock de sala | SALA_VENTA (0,N) — VINO (0,N) | cantidad | STOCK_SALA (**id_sala, cod_vino**) |

Ejemplo de lectura: en *composicion*, un vino tiene de 1 a N cepas (CEPA (1,N)) y una cepa puede estar en ninguno o en varios vinos (VINO (0,N)).

Total: **30 tablas** = 22 de la sección 1 + 7 relaciones N:M + STOCK_DEPOSITO.

## 3. Decisiones tomadas sobre el relevamiento

1. **Subtipo SOCIO: lleva tabla propia**, aunque solo tenga la clave. El apunte de la cátedra (*Modelo Relacional*, conversión de relaciones IS-A, opción c) indica «crear una relación por cada conjunto de entidades», y así los tres subtipos se tratan igual.
2. **Los vinos de un ingreso deben ser de la bodega que lo origina.** El enunciado no lo dice, pero un ingreso tiene una sola bodega de origen. Se valida con un trigger en la etapa 2 (regla propia del grupo, RN-16).
3. **Trazabilidad lote → vino:** no hay relación directa en el escenario. Se infiere por cepa del vino + bodega elaboradora + campaña igual a la añada.
4. **Día de cierre:** tipo enumerado con los siete días.

## 4. Puntos todavía abiertos

1. **Mínimos (1,N) que una FK no garantiza.** «Un lote tiene al menos un análisis» y «un comprobante tiene al menos un renglón» no se pueden exigir con constraints simples. La composición sí queda cubierta por el trigger diferido de RN-05. Hay que decidir si los otros se exigen o se documentan como límite conocido.
2. **Auditoría de precio y borrado de vinos.** Por ahora la FK es RESTRICT: un vino que alguna vez cambió de precio no se puede borrar, para no perder el historial. Afecta al endpoint `DELETE /vinos/{cod}`.
