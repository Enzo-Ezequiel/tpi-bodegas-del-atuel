-- Genera el diccionario de datos en Markdown a partir del catalogo de PostgreSQL,
-- para que siempre coincida con el esquema fisico.
-- Uso: psql -U postgres -d bodegas_atuel -At -f scripts/diccionario.sql > docs/04_diccionario_de_datos.md

WITH columnas AS (
    SELECT c.oid AS tabla_oid,
           c.relname AS tabla,
           a.attnum,
           a.attname AS columna,
           format_type(a.atttypid, a.atttypmod) AS tipo,
           a.attnotnull AS no_nulo,
           a.attidentity <> '' AS identidad,
           pg_get_expr(d.adbin, d.adrelid) AS valor_defecto,
           col_description(c.oid, a.attnum) AS descripcion
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
     WHERE n.nspname = 'public' AND c.relkind = 'r'
),
restricciones AS (
    -- Una fila por (tabla, columna, restriccion)
    SELECT k.conrelid AS tabla_oid,
           col.attnum,
           CASE k.contype
               WHEN 'p' THEN 'PK'
               WHEN 'u' THEN 'UNIQUE'
                             || CASE WHEN cardinality(k.conkey) > 1
                                     THEN ' (' || (SELECT string_agg(a2.attname, ', ' ORDER BY u.ord)
                                                     FROM unnest(k.conkey) WITH ORDINALITY AS u(num, ord)
                                                     JOIN pg_attribute a2
                                                       ON a2.attrelid = k.conrelid AND a2.attnum = u.num) || ')'
                                     ELSE '' END
               WHEN 'f' THEN 'FK → ' || k.confrelid::regclass
               WHEN 'c' THEN replace(pg_get_constraintdef(k.oid), '|', '\|')
           END AS texto,
           CASE k.contype WHEN 'p' THEN 1 WHEN 'f' THEN 2 WHEN 'u' THEN 3 ELSE 4 END AS orden
      FROM pg_constraint k
      JOIN LATERAL unnest(k.conkey) AS col(attnum) ON true
     WHERE k.contype IN ('p', 'u', 'f', 'c')
),
filas AS (
    SELECT c.tabla, c.attnum,
           format('| %s | %s | %s | %s | %s |',
                  c.columna,
                  c.tipo,
                  CASE WHEN c.no_nulo THEN 'No' ELSE 'Sí' END,
                  concat_ws('; ',
                      (SELECT string_agg(r.texto, '; ' ORDER BY r.orden, r.texto)
                         FROM restricciones r
                        WHERE r.tabla_oid = c.tabla_oid AND r.attnum = c.attnum),
                      CASE WHEN c.identidad THEN 'autogenerado' END,
                      'DEFAULT ' || c.valor_defecto),
                  COALESCE(c.descripcion, '')) AS linea
      FROM columnas c
),
tablas AS (
    SELECT c.relname AS tabla, obj_description(c.oid, 'pg_class') AS descripcion
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'r'
),
salida AS (
    SELECT NULL::name AS tabla, -3 AS orden, '# Diccionario de datos' AS linea
    UNION ALL
    SELECT NULL, -2, E'\nGenerado desde el catálogo de PostgreSQL con `scripts/diccionario.sql`. No editar a mano.'
    UNION ALL
    SELECT NULL, -1, E'\n## Tipos propios\n\n| Tipo | Clase | Definición |\n|---|---|---|'
    UNION ALL
    SELECT NULL, 0,
           format('| %s | ENUM | %s |', t.typname,
                  (SELECT string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder)
                     FROM pg_enum e WHERE e.enumtypid = t.oid))
      FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
     WHERE n.nspname = 'public' AND t.typtype = 'e'
    UNION ALL
    SELECT NULL, 0,
           format('| %s | DOMAIN | %s %s |', t.typname,
                  format_type(t.typbasetype, t.typtypmod),
                  (SELECT string_agg(replace(pg_get_constraintdef(k.oid), '|', '\|'), ' ')
                     FROM pg_constraint k WHERE k.contypid = t.oid))
      FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
     WHERE n.nspname = 'public' AND t.typtype = 'd'
    UNION ALL
    SELECT tabla, 1,
           format(E'\n## %s\n\n%s\n\n| Columna | Tipo | Nulos | Restricciones | Descripción |\n|---|---|---|---|---|',
                  tabla, COALESCE(descripcion, ''))
      FROM tablas
    UNION ALL
    SELECT tabla, 1 + attnum, linea FROM filas
)
SELECT linea FROM salida ORDER BY tabla NULLS FIRST, orden, linea;
