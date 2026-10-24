# Plan de trabajo — TPI «Bodegas del Atuel» (versión simplificada)

Base de Datos · UTN FRSR · 2026 · Lanzamiento 13/10/2026 · **Consulta única: 03/11** · Entrega: a definir

Grupo: Ezequiel Buttini, Matías Cano, Manuel Gómez.
Stack: PostgreSQL 18 · Python + FastAPI + psycopg · HTML/CSS/JS sin framework · draw.io.

## El pilar del proyecto: lo que dijo el profesor

Este mensaje es la base de todo el trabajo. Cualquier decisión, archivo o tarea se mide contra él; si algo del enunciado o de este plan lo contradice, gana el mensaje.

> **Qué se evalúa: cómo lo pensaron**
>
> No vamos a mirar si su solución es idéntica a otra ni si cada detalle está perfecto. Lo que se evalúa, en el oral, es cómo plantearon y pensaron el modelo:
>
> - Cómo identificaron las entidades y qué las identifica (claves). Por qué algo es una tabla propia y no una columna de otra.
> - Cómo definieron las relaciones y sus cardinalidades. Qué es 1:N, qué es N:M, cuándo hace falta una tabla intermedia y qué atributos viven en ella.
> - Cómo llegaron a la normalización. Qué dependencias detectaron, qué redundancias evitaron y cómo justifican las que decidieron conservar.
> - Qué decisiones de diseño tomaron y qué alternativas descartaron. Por ejemplo, qué cosas se guardan y cuáles se calculan, o cómo representaron los distintos tipos de cliente.
> - Cómo el modelo respalda las reglas del negocio. Qué regla se resuelve con una clave, una restricción o un trigger, y por qué ahí.
> - La teoría que sostiene todo eso: dependencias funcionales, formas normales, claves candidatas, integridad referencial.
>
> Un modelo con un error que entienden y saben explicar vale más que un modelo correcto que no pueden justificar.
>
> **Lo mínimo que tiene que cumplirse**
>
> El trabajo tiene que estar razonablemente bien y funcionando (la base se crea desde cero, la API responde, el front se conecta). Es la condición para poder defenderlo, no el objeto de la nota. Y todo lo que entreguen tiene que ser comprensible para ustedes: se les va a pedir que expliquen cualquier parte, incluso si usaron material externo o herramientas de IA.
>
> **Por qué les decimos todo esto**
>
> Para este trabajo hay una sola clase de consulta, el 03/11. Por eso queremos que sepan desde ahora que no tienen que preocuparse si no todo sale a la perfección: no se espera que esté impecable, se espera que lo hayan pensado y puedan explicarlo.
>
> Recuerden que los temas que no hemos visto como por ejemplo transacciones son opcionales.

### Filtro para cada decisión

Antes de agregar algo al repo, tiene que pasar estas cuatro preguntas:

1. **¿Cualquiera de los tres lo explica en 2 o 3 frases?** Si no, se simplifica o no entra.
2. **¿Lo vimos en clase?** Si no, es [Opcional].
3. **¿Hace falta para que funcione (base, API, front) o para cumplir una regla RN?** Si no, afuera.
4. **¿Quedó escrito el porqué y la alternativa que descartamos?** En un comentario del SQL o en `docs/`.

Entonces el criterio es: **lo justo de cada etapa, hecho con lo que vimos en clase, y con su «por qué» escrito en pocas líneas.** Nada de super producción.

## Cómo trabajamos

- Cada tarea tiene una etiqueta:
  - **[Imprescindible]**: sin esto no se puede defender.
  - **[Si da el tiempo]**: lo pide el enunciado, pero no es lo que se evalúa.
  - **[Opcional]**: tema que no vimos en clase; solo si sobra tiempo.
- Primero se termina todo lo imprescindible de todas las etapas; después se vuelve por lo demás.
- Cada archivo SQL lleva comentarios cortos que expliquen **qué hace y por qué está ahí** (qué regla protege). Esos comentarios son el material de estudio para el oral.
- Ramas por etapa y pull request a `main`. Que Matías y Manuel commiteen desde sus cuentas.

## Reglas que se mantienen

| Regla | En la práctica |
|---|---|
| Sin ORM | SQL escrito a mano, con parámetros (`%s`), nunca concatenando texto |
| La lógica vive en la base | Totales, descuentos y stock los calculan funciones y triggers; la API solo los llama |
| La API no usa el usuario dueño | Se conecta con un rol de lectura/escritura |
| Sin contraseñas en el repo | Van en `.env`, que está en el `.gitignore` |
| Dinero con `NUMERIC`, estados con `ENUM` | Ya está así en `001_esquema.sql` |

## Objetivo para la consulta del 03/11

Llegar con las **etapas 2 y 3 hechas y la 5 empezada**, para preguntar dudas concretas sobre lo que más pesa en el oral: modelo, reglas y consultas.

---

## Etapa 0 y 1 — Entorno y modelado ✅

- [x] Repo, estructura, `.gitignore`, `scripts/recrear_bd.ps1`.
- [x] DER, esquema relacional, normalización, decisiones de diseño, diccionario (escrito a mano en `docs/04_diccionario_de_datos.md`) y `001_esquema.sql`, probado en el PostgreSQL local.
- [ ] **[Si da el tiempo]** Probar el esquema en Docker (ver `pendientes.md`, lo hace un compañero).

**No se rehace.** Lo que hay que hacer con la etapa 1 es **estudiarla**: es exactamente lo que el profesor dice que va a preguntar (ver la guía al final).

## Etapa 2 — Reglas de negocio en la base

Apuntes: *Reglas de integridad*, *Funciones, Procedimientos y Triggers*, *Vistas*, *Roles*.

**[Imprescindible]**

- [x] `002_constraints.sql`: los UNIQUE, CHECK y DEFAULT que pide el enunciado (4 UNIQUE, 11 CHECK, 3 DEFAULT). Son una línea cada uno.
- [x] `003_funciones.sql`: 4 funciones cortas — descuento según tipo de cliente, stock de un vino en una sala, total de un comprobante, antigüedad de un empleado.
- [ ] `004_procedimientos.sql`: 2 procedimientos — procesar un ingreso (suma al depósito) y procesar una transferencia (resta del depósito y suma a la sala), validando el estado y el stock con mensajes claros.
- [x] `005_triggers.sql`: 8 triggers con BEFORE y AFTER, que son los que vimos:
  1. Validar el stock y completar precio, descuento y subtotal del renglón (BEFORE INSERT en renglón de comprobante).
  2. Descontar el stock y actualizar los importes del comprobante (AFTER INSERT en renglón).
  3. Controlar los cambios de estado de ingresos y transferencias (que no retrocedan).
  4. No permitir tocar renglones de un documento que ya no está en confección (deja pasar el borrado en cascada).
  5. Poner la fecha actual en la transferencia y no dejar cambiarla.
  6. Registrar los cambios de precio en la auditoría (AFTER UPDATE en vino).
  7. Porcentajes de corte: **versión simple**, no deja que la suma pase de 100 (la vista de vinos incompletos va en `006`).
  8. Completar el descuento inicial del cliente según su tipo.
- [ ] `006_vistas.sql`: 3 vistas — stock total por vino, ventas mensuales por sala, documentos pendientes.
- [ ] `007_roles.sql`: 3 roles — dueño, API (lectura/escritura) y reportes (solo lectura).
- [ ] `db/tests/db_tests.sql`: un caso que funciona y uno que falla por cada regla RN-01 a RN-15, con un comentario del error esperado.
- [ ] `docs/trazabilidad.md`: tabla «regla → dónde se resuelve → caso de prueba».

**[Opcional] (no lo vimos)**

- [ ] Constraint trigger diferido para la suma de 100 (lo que pide literalmente el enunciado).
- [ ] Bloqueos `FOR UPDATE` en los procedimientos y la demostración de concurrencia con dos sesiones.

**Decisiones tomadas** (las más simples; los límites están en `docs/03_decisiones_de_diseno.md`, sección 7):

1. Un comprobante puede quedar sin renglones en la base; se documenta como límite conocido.
2. Un vino con movimientos o con cambios de precio no se puede borrar (ya está así con RESTRICT).

## Etapa 3 — Carga de datos

**[Imprescindible]**

- [ ] CSV con los catálogos reales del anexo B: cepas, maridajes, departamentos y localidades de Mendoza.
- [ ] Un script de Python (`db/seed/cargar.py`) con semilla fija, que genere los datos con Faker y `random`.
- [ ] Volúmenes **mínimos** del enunciado, no los recomendados: todas las tablas con al menos una fila, 3 tablas con más de 10.000 y una con más de 100.000 (renglones de comprobante, unos 120.000).
- [ ] Cargar el historial con los triggers deshabilitados y volver a habilitarlos. Explicar en 3 líneas por qué.
- [ ] Consultas de control: conteo por tabla, stock negativo y totales que no coinciden con los renglones.

**[Si da el tiempo]**

- [ ] Medir una vez fila por fila contra por lotes y anotar los dos tiempos.
- [ ] Volcado con `pg_dump`.

## Etapa 4 — Índices

Apunte: *Índices en PostgreSQL* (vimos compuesto, parcial y BRIN, y `EXPLAIN`).

**[Imprescindible]**

- [ ] `008_indices.sql`: 5 índices — uno compuesto, uno parcial, uno sobre una clave foránea y uno BRIN sobre fechas. Cada uno con una línea de por qué.
- [ ] 3 consultas medidas con `EXPLAIN ANALYZE` antes y después, en una tabla de tiempos.

**[Si da el tiempo]**

- [ ] Un índice descartado y por qué.
- [ ] Costo de escritura y un caso donde PostgreSQL no usa el índice.

## Etapa 5 — Consultas SQL

Apunte: *JOIN, GROUP BY, HAVING, Subconsultas*.

**[Imprescindible]**

- [ ] `consultas/update.sql`, `insert.sql`, `delete.sql` y `select.sql`: todas las consignas de la sección 8, cada una con un comentario de 2-3 líneas sobre cómo se pensó.
- [ ] Resolver con lo que vimos: JOIN, GROUP BY, HAVING, subconsultas, EXISTS / NOT EXISTS.

**[Opcional] (no lo vimos)**

- [ ] S10 con CTE (`WITH`) y S11 con funciones de ventana (`RANK() OVER`). Si no, resolverlas con subconsultas y explicar la diferencia.
- [ ] Probar los UPDATE y DELETE dentro de `BEGIN; … ROLLBACK;`.

## Etapa 6 — API

**[Imprescindible]** (FastAPI genera la documentación Swagger sola)

- [ ] `api/db.py`: la conexión (datos desde `.env`) y una función por consulta.
- [ ] `api/main.py` con los endpoints básicos:
  - `GET /salud`
  - `GET /vinos` (filtros por tipo, cepa, bodega y añada, con paginación) y `GET /vinos/{cod}`
  - `GET` y `POST /clientes`
  - `POST /comprobantes` y `GET /comprobantes/{nro}`
  - transferencias: crear, agregar renglones, terminar y procesar
  - 2 o 3 reportes de la sección 8
- [ ] Los errores de la base se devuelven con su mensaje: 409 para reglas violadas, 422 para datos inválidos.

**[Si da el tiempo]**

- [ ] Resto de los endpoints del enunciado (ingresos, PUT y DELETE de vinos y clientes).
- [ ] Algunas pruebas automáticas y la demostración de inyección SQL fallida.
- [ ] API dentro del `docker-compose.yml`.

## Etapa 7 — Front

**[Imprescindible]** Páginas HTML simples que llaman a la API:

- [ ] Catálogo de vinos con filtros.
- [ ] Nueva venta, mostrando el error de stock insuficiente que devuelve la base.
- [ ] Transferencias, con botones para terminar y procesar.

**[Si da el tiempo]**

- [ ] Alta y edición de vino.
- [ ] Tablero con el ranking y un gráfico.

## Etapa 8 — Nube

**[Si da el tiempo]** No está dentro del mínimo que nombró el profesor. Si sobra tiempo al final: base en un servicio gratuito (Neon o Supabase), API en Render, y una prueba de backup y restauración.

## Etapa 9 — Documentación y defensa

**[Imprescindible]**

- [ ] README: cómo crear la base, cargar los datos y levantar la API y el front.
- [ ] Informe final: juntar los documentos de `docs/`.
- [ ] Preparar el oral con la guía de abajo. Cada integrante tiene que poder explicar **todo**.

---

## Guía para el oral

Lo que dijo el profesor que va a preguntar, y dónde está la respuesta:

| Pregunta del profesor | Dónde estudiarlo |
|---|---|
| Cómo identificamos las entidades y sus claves; por qué algo es tabla y no columna | `docs/01_modelo_conceptual.md` y `docs/03_decisiones_de_diseno.md` (sección 2, claves naturales y subrogadas) |
| Relaciones y cardinalidades; cuándo hace falta tabla intermedia y qué atributos van en ella | `docs/01_modelo_conceptual.md` (sección 2) y el DER |
| Normalización: dependencias detectadas, redundancias evitadas y las que conservamos | `docs/02_esquema_relacional.md` (sección 2, en especial 2.2 y 2.5) |
| Decisiones de diseño y alternativas descartadas (qué se guarda y qué se calcula, tipos de cliente) | `docs/03_decisiones_de_diseno.md` (secciones 1 y 4) |
| Cómo el modelo respalda las reglas: clave, restricción o trigger, y por qué ahí | `docs/trazabilidad.md` (etapa 2) |
| Teoría: dependencias funcionales, formas normales, claves candidatas, integridad referencial | Apuntes de la cátedra + `docs/02_esquema_relacional.md` |

Preguntas para practicar entre los tres:

- ¿Por qué `localidad` tiene clave subrogada y `bodega` usa el CUIT?
- ¿Por qué existe la tabla `departamento`? ¿Qué dependencia evita?
- ¿Por qué el descuento del renglón es un importe y no un porcentaje?
- ¿Por qué guardamos el total del comprobante si se puede calcular? ¿Cómo evitamos que quede mal?
- ¿Qué opciones había para los tipos de cliente y por qué elegimos supertipo más subtipos?
- ¿Por qué los renglones se borran en cascada pero los vinos no?
- ¿Qué pasa si intento vender más botellas de las que hay en la sala? ¿Qué parte de la base lo impide?
