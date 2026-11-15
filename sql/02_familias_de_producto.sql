-- =====================================================================================================
-- PREGUNTA 2 · ¿Qué familias de producto venden más y cuáles crecen o caen?
-- =====================================================================================================
-- Equivale a la Pregunta 2 del notebook 02_preguntas_de_negocio.ipynb.
--
-- Cómo ejecutarlo (desde la carpeta raíz del proyecto, con el entorno virtual activado):
--     python sql/ejecutar_consulta.py sql/02_familias_de_producto.sql
--
-- Decisiones de calidad de datos que respetamos:
--   * Ranking: usamos el PERIODO CONFIABLE (desde el 1-jun-2015). Antes, familias grandes como PRODUCE o
--     BEVERAGES tenían huecos y su peso saldría subestimado.
--   * Crecimiento: comparamos los últimos 12 meses (16-ago-2016 a 15-ago-2017) con los 12 anteriores
--     (16-ago-2015 a 15-ago-2016), solo en las tiendas que ya vendían en agosto de 2015 ("tiendas
--     comparables"), para que el crecimiento no venga de tiendas nuevas.
-- =====================================================================================================


-- -----------------------------------------------------------------------------------------------------
-- Paso 2.1 · Ranking de familias (periodo confiable)
-- -----------------------------------------------------------------------------------------------------
-- 1) Sumamos las ventas de cada familia desde jun-2015.
-- 2) Participación = ventas de la familia / ventas de todas las familias * 100.
--    SUM(ventas) OVER () es el total de todas las filas (todas las familias), puesto al lado de cada fila.
-- 3) Acumulado: SUM(...) OVER (ORDER BY ventas DESC) va sumando fila por fila, de la más grande a la más
--    chica. Sirve para ver cuántas familias hacen falta para llegar al 80% de las ventas.

-- RESULTADO: Paso 2.1 · Ranking de familias desde jun-2015 (participación y acumulado, %)
WITH por_familia AS (
    SELECT family,
           SUM(sales) AS ventas
    FROM train
    WHERE date >= '2015-06-01'                    -- periodo confiable
    GROUP BY family
)
SELECT ROW_NUMBER() OVER (ORDER BY ventas DESC)                                   AS puesto,
       family,
       ROUND(ventas)                                                              AS ventas,
       ROUND(ventas / SUM(ventas) OVER () * 100, 2)                               AS participacion_pct,
       ROUND(SUM(ventas) OVER (ORDER BY ventas DESC) / SUM(ventas) OVER () * 100, 2) AS acumulado_pct
FROM por_familia
ORDER BY ventas DESC;


-- -----------------------------------------------------------------------------------------------------
-- Paso 2.2 · ¿Qué familias crecen o caen? (últimos 12 meses vs. 12 meses anteriores)
-- -----------------------------------------------------------------------------------------------------
-- Usamos tablas temporales (solo existen durante esta ejecución, no cambian data/ventas.db).

-- a) Tiendas comparables: las que tuvieron ventas en agosto de 2015 (deben ser 52).
DROP TABLE IF EXISTS temp.tiendas_comparables;

CREATE TEMP TABLE tiendas_comparables AS
SELECT store_nbr
FROM train
WHERE date >= '2015-08-01' AND date < '2015-09-01'
GROUP BY store_nbr
HAVING SUM(sales) > 0;                            -- HAVING filtra DESPUÉS de agrupar

-- b) Ventas de cada familia en cada periodo de 12 meses, solo en tiendas comparables.
--    Ponemos los dos periodos como dos columnas con SUM(CASE WHEN ...).
DROP TABLE IF EXISTS temp.crecimiento_familias;

CREATE TEMP TABLE crecimiento_familias AS
SELECT family,
       SUM(CASE WHEN date <  '2016-08-16' THEN sales ELSE 0 END) AS anterior,      -- 16-ago-2015 a 15-ago-2016
       SUM(CASE WHEN date >= '2016-08-16' THEN sales ELSE 0 END) AS ultimo_anio    -- 16-ago-2016 a 15-ago-2017
FROM train
WHERE date >= '2015-08-16'
  AND store_nbr IN (SELECT store_nbr FROM tiendas_comparables)
GROUP BY family;

-- RESULTADO: Paso 2.2 · Tiendas comparables (deben ser 52) y crecimiento total del último año (%)
SELECT (SELECT COUNT(*) FROM tiendas_comparables)                       AS tiendas_comparables,
       ROUND((SUM(ultimo_anio) / SUM(anterior) - 1) * 100, 1)          AS crecimiento_total_pct
FROM crecimiento_familias;

-- RESULTADO: Paso 2.2 · Cambio por familia (%), todas las familias, de la que más cae a la que más crece
SELECT family,
       ROUND(anterior)                                  AS anterior,
       ROUND(ultimo_anio)                               AS ultimo_anio,
       ROUND((ultimo_anio / anterior - 1) * 100, 2)     AS cambio_pct
FROM crecimiento_familias
ORDER BY cambio_pct;
-- Ojo: las familias muy pequeñas (BOOKS, BABY CARE) tienen cambios enormes porque venden muy poco.
-- BOOKS sale con cambio_pct vacío (NULL): no vendió nada en el periodo anterior, y en SQLite dividir
-- por cero da NULL en vez de un error.

-- c) Igual que en el notebook, para conclusiones nos quedamos con las familias "relevantes":
--    las que pesan al menos 0,5% de las ventas en el periodo confiable.

-- RESULTADO: Paso 2.2 · Cambio por familia (%), solo familias relevantes (>= 0,5% de las ventas)
WITH participacion AS (
    SELECT family,
           SUM(sales) / (SELECT SUM(sales) FROM train WHERE date >= '2015-06-01') * 100 AS participacion_pct
    FROM train
    WHERE date >= '2015-06-01'
    GROUP BY family
)
SELECT c.family,
       ROUND(p.participacion_pct, 2)                        AS participacion_pct,
       ROUND((c.ultimo_anio / c.anterior - 1) * 100, 1)     AS cambio_pct,
       CASE WHEN c.ultimo_anio >= c.anterior THEN 'crece' ELSE 'cae' END AS tendencia
FROM crecimiento_familias AS c
JOIN participacion        AS p ON p.family = c.family     -- JOIN une las dos tablas por la familia
WHERE p.participacion_pct >= 0.5
ORDER BY cambio_pct DESC;
