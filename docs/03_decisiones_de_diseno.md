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
- Que cada cliente tenga fila en el subtipo que corresponde a su `tipo_cliente` no lo controla la base: es un límite conocido (sección 7).

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
- **Porcentajes:** dominio `porcentaje_dom` (`NUMERIC(5,2)` entre 0 y 100), usado en los cortes y en el descuento del cliente.
- **CUIT:** dominio `cuit_dom` (`CHAR(11)` con solo dígitos). Es texto y no número porque no se opera con él y puede empezar con cero.
- **Fechas:** `DATE` donde solo importa el día (cosecha, venta, ingreso). `TIMESTAMPTZ` en la auditoría de precio, donde importa el momento exacto.
- **Valores de lista cerrada:** tipos `ENUM` (`estado_documento`, `tipo_vino`, `tipo_cepa`, `tipo_cliente`, `tipo_documento`, `dia_semana`). No son texto libre y ocupan menos que un `VARCHAR`.
- **Cantidades de botellas:** `INTEGER`.
- **Medidas:** `NUMERIC` con la precisión de cada magnitud (hectáreas, kilos, Brix, pH, acidez, temperatura).

## 4. Atributos derivados

| Atributo | ¿Se almacena? | Cómo se garantiza la consistencia |
|---|---|---|
| `renglon_comprobante.descuento` y `subtotal` | Sí | Los calcula un trigger al insertar el renglón |
| `comprobante.subtotal`, `descuento`, `total` | Sí | Función `fn_total_comprobante` y trigger AFTER sobre los renglones (RN-08) |
| `renglon_comprobante.precio_unitario` | Sí | No es derivado: es una copia histórica del precio al momento de la venta |
| Antigüedad del empleado | No | Función `fn_antiguedad_anios` |
| Stock total de un vino | No | Vista que suma depósito y salas |
| Rendimiento kg/ha de una parcela | No | Se calcula en la consulta S10 |

Se almacenan solo los importes de la venta, porque el enunciado los pide como datos del comprobante y deben reflejar lo que se cobró aunque después cambien los precios o el descuento del cliente. Es una excepción deliberada a la 3FN; está analizada en la sección 2.5 del esquema relacional.

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
- **Descuento en la venta:** tanto en el renglón como en el comprobante se guarda el **importe** descontado. El porcentaje solo está en `cliente`. Guardar el porcentaje en cada renglón sería una dependencia parcial, porque es el mismo para todo el comprobante.
- **Depósito central:** es único, así que `stock_deposito` tiene una fila por vino y no existe una tabla de depósitos.
- **Vinos de un ingreso:** evaluamos exigir que sean de la bodega de origen del ingreso y lo descartamos, porque el enunciado no lo pide.
- **Restricciones en `001_esquema.sql`:** incluye tipos, dominios, NOT NULL, claves primarias y claves foráneas con sus acciones. UNIQUE, CHECK y DEFAULT están en `002_constraints.sql`.
- **Vistas comunes, no materializadas:** una vista materializada guarda el resultado y queda desactualizada hasta que se ejecuta `REFRESH MATERIALIZED VIEW`; una venta nueva no aparecería en el tablero. Con el volumen del trabajo, la vista común responde bien y siempre muestra los datos actuales.
- **Roles:** `bodegas_admin` (todos los permisos), `bodegas_api` (lectura y escritura de datos, sin crear ni borrar tablas, y sin poder modificar ni borrar la auditoría de precios) y `bodegas_reportes` (solo lectura). El dueño técnico de las tablas es el usuario que corre las migraciones; la API nunca se conecta con él. Para que el dueño fuera `bodegas_admin` habría que correr las migraciones con ese usuario, lo que cambia el script de recreación y el Docker; lo descartamos por simplicidad.
- **Contraseñas de los roles:** no están en el repositorio. Los roles se crean sin contraseña y se les asigna una a mano (`ALTER ROLE … PASSWORD`), que se guarda en el `.env`.

## 7. Límites conocidos

Reglas que la base **no** garantiza del todo. Las dejamos así a propósito: resolverlas exige herramientas que no vimos en clase (triggers diferidos, transacciones) o agrega trabajo sin cubrir una regla del enunciado. Las tenemos identificadas y sabemos qué haría falta para cerrarlas.

| Límite | Por qué pasa | Qué haría falta | Cómo lo cubrimos hoy |
|---|---|---|---|
| Los porcentajes de corte de un vino pueden sumar menos de 100 (RN-05) | Mientras se cargan las cepas de a una, la suma pasa por valores intermedios; si se exige 100 en cada fila, no se puede cargar ningún vino | Verificar la suma al final de la transacción (constraint trigger diferido) | Un trigger impide pasar de 100 y una vista muestra los vinos incompletos |
| Un cliente puede quedar sin fila en su subtipo (`socio`, `distribuidor`, `exportador`) | La fila del cliente y la del subtipo se insertan por separado | Un control al final de la transacción | La API da de alta el cliente y su subtipo juntos |
| Un comprobante puede quedar sin renglones; un lote, sin análisis | Una FK garantiza el lado (1,1), no el mínimo de un (1,N) | Un control al final de la transacción | Se documenta |
| Borrar o modificar un renglón de venta no devuelve el stock | Solo el alta del renglón mueve stock (trigger T2) | Triggers de UPDATE y DELETE sobre `renglon_comprobante` | Una venta emitida no se edita |
| Un ingreso o transferencia se puede marcar `procesado` con un UPDATE a mano, sin mover el stock | El trigger de estados controla el orden, no quién hace el cambio | Permisos que solo dejen cambiar el estado desde el procedimiento | La API solo usa los procedimientos de `004` |
| Si dos personas procesan **la misma** transferencia o ingreso al mismo tiempo, el stock se puede mover dos veces | Las dos leen el estado `terminado` antes de que la otra lo cambie; para la segunda el estado ya no cambia, así que el trigger de estados no se dispara | Bloquear la fila del documento al leerla (`SELECT … FOR UPDATE`) | Que el stock quede negativo sí está cubierto: el `CHECK cantidad >= 0` hace fallar y deshacer el segundo procesamiento |
| `lote_uva.campania` podría no coincidir con el año de `fecha_cosecha` | No se declaró un CHECK para eso | `CHECK (campania = EXTRACT(YEAR FROM fecha_cosecha))` | La carga de datos los genera coherentes |
