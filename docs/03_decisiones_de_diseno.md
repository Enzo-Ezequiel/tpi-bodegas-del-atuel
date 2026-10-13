# Etapa 1 — Decisiones de diseño

Justificación de las decisiones que pide la sección 5 del enunciado.

## 1. Jerarquía de clientes

La jerarquía es **total** (todo cliente es socio, distribuidor o exportador) y **disjunta** (de un solo tipo).

El apunte de la cátedra plantea tres formas de convertir una relación IS-A:

| Opción | Ventajas | Desventajas |
|---|---|---|
| a. Tabla única con todos los atributos | Simple, sin joins | Columnas nulas según el tipo (zona, habilitación, país); no se puede poner NOT NULL a los atributos propios; `permiso_exportacion` referenciaría a cualquier cliente, no solo a exportadores |
| b. Una tabla por subtipo, sin supertipo | Sin nulos ni joins para leer un cliente | Los atributos comunes se repiten en tres tablas; `comprobante` necesitaría tres claves foráneas alternativas hacia cliente; el documento único entre los tres tipos no se puede garantizar con UNIQUE |
| c. Supertipo más una tabla por subtipo | Sin nulos; atributos propios NOT NULL; una sola FK desde `comprobante`; `permiso_exportacion` referencia solo a `exportador` | Leer un cliente completo requiere un join |

**Elegimos la opción c.** Aunque la opción b suele aplicarse en jerarquías totales y exclusivas, acá el supertipo participa en relaciones propias (compra comprobantes, vive en una localidad) que habría que triplicar.

- `cliente.tipo_cliente` actúa como discriminador y evita consultar tres tablas para saber el tipo.
- `socio` no tiene atributos propios, pero lleva su tabla para tratar los tres subtipos de la misma manera, como indica la regla de la cátedra.
- Que cada cliente tenga fila en el subtipo que corresponde a su `tipo_cliente` se controla en la etapa 2.

## 2. Claves naturales o subrogadas

| Tabla | Clave | Tipo | Justificación |
|---|---|---|---|
| bodega | cuit | Natural | Identifica a la empresa, es estable y el enunciado la da como identificador |
| empleado | cuit | Natural | Ídem; el enunciado no da otro identificador |
| localidad | id_localidad | Subrogada | El código postal no es único: varias localidades lo comparten |
| departamento | id_departamento | Subrogada | El nombre puede repetirse entre provincias |
| transportista | cod_transporte | Subrogada | El enunciado pide un código de transporte; el CUIT queda como UNIQUE |
| vino | cod_vino | Subrogada | El enunciado pide un código; (nombre, añada, volumen) queda como UNIQUE |
| cliente | id_cliente | Subrogada | El enunciado pide un ID; el documento depende del tipo de documento |
| parcela | (id_finca, nro_parcela) | Natural compuesta | Entidad débil: se identifica por su número dentro de la finca |
| lote_uva | nro_lote | Subrogada | El enunciado pide un número de lote; (parcela, campaña) queda como UNIQUE |
| renglones y stock | compuesta | Natural | Combinación de las claves que relacionan |
| permiso_exportacion | codigo | Natural | Lo emite el organismo, viene dado |

Las claves subrogadas usan `GENERATED ALWAYS AS IDENTITY`: las genera la base y no se pueden modificar.

## 3. Tipos de datos

- **Dinero:** `NUMERIC(10,2)` para precios, `NUMERIC(12,2)` para salarios y `NUMERIC(14,2)` para importes de comprobantes. Nunca `FLOAT`, porque no representa decimales en forma exacta y los totales no cerrarían.
- **Porcentajes:** dominio `porcentaje_dom` (`NUMERIC(5,2)` entre 0 y 100), usado en cortes y descuentos.
- **CUIT:** dominio `cuit_dom` (`CHAR(11)` con solo dígitos). Es texto y no número porque no se opera con él y puede empezar con cero.
- **Fechas:** `DATE` donde solo importa el día (cosecha, venta, ingreso). `TIMESTAMPTZ` en la auditoría de precio, donde importa el momento exacto.
- **Valores de lista cerrada:** tipos `ENUM` (`estado_documento`, `tipo_vino`, `tipo_cepa`, `tipo_cliente`, `tipo_documento`, `dia_semana`). No son texto libre y ocupan menos que un `VARCHAR`.
- **Cantidades de botellas:** `INTEGER`.
- **Medidas:** `NUMERIC` con la precisión de cada magnitud (hectáreas, kilos, Brix, pH, acidez, temperatura).

## 4. Atributos derivados

| Atributo | ¿Se almacena? | Cómo se garantiza la consistencia |
|---|---|---|
| `renglon_comprobante.subtotal` | Sí | Lo calcula un trigger al insertar el renglón |
| `comprobante.subtotal`, `descuento`, `total` | Sí | Función `fn_total_comprobante` y trigger AFTER sobre los renglones (RN-08) |
| `renglon_comprobante.precio_unitario` y `descuento` | Sí | No son derivados: son una copia histórica del precio y del descuento al momento de la venta |
| Antigüedad del empleado | No | Función `fn_antiguedad_anios` |
| Stock total de un vino | No | Vista que suma depósito y salas |
| Rendimiento kg/ha de una parcela | No | Se calcula en la consulta S10 |

Se almacenan solo los importes de la venta, porque el enunciado los pide como datos del comprobante y deben reflejar lo que se cobró aunque después cambien los precios.

## 5. Acciones referenciales

Criterio general: **RESTRICT** en todo lo que sea un catálogo o tenga movimientos, **CASCADE** solo cuando la fila hija no tiene sentido sin la madre.

| Clave foránea | ON DELETE | Por qué |
|---|---|---|
| renglones → comprobante, ingreso, transferencia | CASCADE | Un renglón no existe sin su cabecera |
| parcela → finca | CASCADE | Entidad débil |
| analisis_calidad → lote_uva | CASCADE | El análisis es parte del lote |
| composicion, vino_maridaje → vino | CASCADE | Describen al vino |
| socio, distribuidor, exportador → cliente | CASCADE | El subtipo es parte del cliente |
| permiso_exportacion → exportador | CASCADE | El permiso es del exportador |
| transportista_localidad → transportista | CASCADE | La cobertura es del transportista y no es un movimiento |
| renglones, stock, auditoría → vino | RESTRICT | RN-14: no se borra un vino con movimientos |
| vino, lote_uva, ingreso → bodega | RESTRICT | RN-14 |
| ingreso → transportista | RESTRICT | RN-14 |
| comprobante → cliente, sala_venta | RESTRICT | No se pierde el historial de ventas |
| resto (localidad, departamento, cepa, maridaje, sala) | RESTRICT | Son catálogos referenciados |

**ON UPDATE:** `CASCADE` en las claves foráneas hacia `bodega.cuit`, que es una clave natural y podría corregirse. `RESTRICT` en el resto: apuntan a claves autogeneradas que no se modifican.

Consecuencia a tener en cuenta: borrar una finca borra sus parcelas, pero si alguna parcela tiene lotes cosechados el borrado se rechaza, porque `lote_uva → parcela` es RESTRICT.

## 6. Otras decisiones

- **Encargado regional:** columna de `localidad` con el nombre del responsable. El enunciado no le da más datos, y como clave foránea a `empleado` obligaría a que pertenezca a una sola sala, cuando está afectado a todas las de la localidad.
- **Descuento del cliente:** columna en `cliente` con valor inicial según el tipo. No es fijo por tipo porque el enunciado (consulta U6) cambia el de algunos exportadores.
- **Descuento en la venta:** en el renglón se guarda el **porcentaje** aplicado; en el comprobante, el **importe** total descontado.
- **Depósito central:** es único, así que `stock_deposito` tiene una fila por vino y no existe una tabla de depósitos.
- **Vinos de un ingreso:** deben ser de la bodega de origen del ingreso. Regla agregada por el grupo, se valida con trigger en la etapa 2.
- **Restricciones en `001_esquema.sql`:** incluye tipos, dominios, NOT NULL, claves primarias y claves foráneas con sus acciones. UNIQUE, CHECK y DEFAULT se agregan en `002_constraints.sql`.
