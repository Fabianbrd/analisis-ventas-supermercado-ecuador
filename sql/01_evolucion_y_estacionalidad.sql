-- =====================================================================================================
-- PREGUNTA 1 · ¿Cómo evolucionan las ventas por año y mes? ¿Hay estacionalidad?
-- =====================================================================================================
-- Equivale a la Pregunta 1 del notebook 02_preguntas_de_negocio.ipynb.
--
-- Cómo ejecutarlo (desde la carpeta raíz del proyecto, con el entorno virtual activado):
--     python sql/ejecutar_consulta.py sql/01_evolucion_y_estacionalidad.sql
--
-- Recordatorios del notebook 01 (calidad de datos):
--   * Hasta mayo de 2015 hay "huecos de registro": 13 familias no se registran bien en muchos meses.
--     Para las tendencias largas (2013-2017) usamos solo las 20 FAMILIAS COMPLETAS.
--   * Para la estacionalidad semanal y por día del mes usamos el PERIODO CONFIABLE (desde el 1-jun-2015),
--     y ahí sí todas las familias.
--   * 2017 solo llega al 15 de agosto: para comparar años usamos el mismo periodo (1-ene a 15-ago).
--   * "sales" son UNIDADES vendidas, no dólares.
--
-- Conceptos de SQL que aparecen en este archivo:
--   * CREATE TEMP TABLE ... AS SELECT: guarda el resultado de una consulta en una tabla TEMPORAL. Solo
--     existe mientras dura la conexión: no modifica data/ventas.db. Nos evita repetir cálculos pesados.
--   * WITH nombre AS (...): una "CTE", una subconsulta con nombre que se usa como si fuera una tabla.
--   * strftime('%Y', date): extrae partes de una fecha (%Y año, %m mes, %d día, %w día de la semana).
--   * Funciones de ventana (... OVER (...)): calculan algo mirando otras filas SIN agrupar. Por ejemplo,
--     LAG(x) OVER (ORDER BY anio) devuelve el valor de x en la fila anterior (el año anterior).
-- =====================================================================================================


-- -----------------------------------------------------------------------------------------------------
-- Paso 0 · ¿Cuáles son las 20 familias completas?
-- -----------------------------------------------------------------------------------------------------
-- Aplicamos la misma regla del notebook 01: en 2014 hubo meses "sospechosos" (feb, abr, may, jun, ago)
-- en los que algunas familias casi no registran ventas. Comparamos el promedio de esos meses con el de
-- sus meses vecinos (ene, mar, jul, sep, oct). Si una familia vende menos del 60% en los meses
-- sospechosos, tiene huecos. Las demás son "completas".

DROP TABLE IF EXISTS temp.familias_completas;

CREATE TEMP TABLE familias_completas AS
WITH ventas_mes AS (
    -- 1) Ventas de cada familia en cada mes de 2014 (substr(date, 1, 7) = 'AAAA-MM')
    SELECT family,
           substr(date, 1, 7) AS mes,
           SUM(sales)         AS ventas
    FROM train
    WHERE date >= '2014-01-01' AND date < '2014-11-01'
    GROUP BY family, mes
),
ratios AS (
    -- 2) Promedio de los meses sospechosos dividido por el promedio de los meses vecinos.
    --    AVG(CASE WHEN ... THEN ventas END) promedia solo las filas que cumplen la condición
    --    (las demás dan NULL y AVG ignora los NULL).
    SELECT family,
           AVG(CASE WHEN mes IN ('2014-02', '2014-04', '2014-05', '2014-06', '2014-08') THEN ventas END)
         / AVG(CASE WHEN mes IN ('2014-01', '2014-03', '2014-07', '2014-09', '2014-10') THEN ventas END)
           AS ratio
    FROM ventas_mes
    GROUP BY family
)
-- 3) Nos quedamos con las familias cuyo ratio es de al menos 0,6.
--    BOOKS no vende nada en 2014: la división da NULL, y COALESCE(ratio, 0) lo convierte en 0 (con huecos).
SELECT family
FROM ratios
WHERE COALESCE(ratio, 0) >= 0.6;

-- RESULTADO: Paso 0 · Las familias completas (deben ser 20)
SELECT COUNT(*) AS familias_completas,
       group_concat(family, ', ') AS lista
FROM familias_completas;


-- -----------------------------------------------------------------------------------------------------
-- Paso 1 · Tabla diaria de ventas del país
-- -----------------------------------------------------------------------------------------------------
-- Una fila por día con:
--   * ventas:                    todas las familias
--   * ventas_familias_completas: solo las 20 familias completas
-- Así recorremos los 3 millones de filas de train una sola vez y las consultas siguientes son rápidas.

DROP TABLE IF EXISTS temp.ventas_diarias;

CREATE TEMP TABLE ventas_diarias AS
SELECT date,
       SUM(sales) AS ventas,
       -- CASE WHEN: si la familia está en la lista de completas sumamos sus ventas, si no sumamos 0.
       SUM(CASE WHEN family IN (SELECT family FROM familias_completas) THEN sales ELSE 0 END)
           AS ventas_familias_completas
FROM train
GROUP BY date;


-- -----------------------------------------------------------------------------------------------------
-- Paso 1.1 · Ventas por año (mismo periodo: 1-ene a 15-ago de cada año)
-- -----------------------------------------------------------------------------------------------------

-- RESULTADO: Paso 1.1 · Ventas del 1-ene al 15-ago de cada año y crecimiento anual (%)
WITH por_anio AS (
    SELECT CAST(strftime('%Y', date) AS INTEGER) AS anio,
           SUM(ventas)                           AS ventas_total,
           SUM(ventas_familias_completas)        AS ventas_familias_completas
    FROM ventas_diarias
    WHERE strftime('%m-%d', date) <= '08-15'     -- mismo periodo del año en todos los años
    GROUP BY anio
)
SELECT anio,
       ROUND(ventas_total)              AS ventas_total,
       ROUND(ventas_familias_completas) AS ventas_familias_completas,
       -- Crecimiento = (este año / año anterior - 1) * 100. LAG trae el valor del año anterior.
       ROUND((ventas_total / LAG(ventas_total) OVER (ORDER BY anio) - 1) * 100, 2)
           AS crec_total_pct,
       ROUND((ventas_familias_completas / LAG(ventas_familias_completas) OVER (ORDER BY anio) - 1) * 100, 2)
           AS crec_familias_completas_pct
FROM por_anio
ORDER BY anio;
-- Lectura: la columna que vale es crec_familias_completas_pct. El total "ingenuo" (crec_total_pct)
-- sale inflado en 2014 y 2016 por los huecos de registro.


-- -----------------------------------------------------------------------------------------------------
-- Paso 1.3 · Estacionalidad anual: cada mes comparado con el promedio de su año (100 = mes promedio)
-- -----------------------------------------------------------------------------------------------------
-- 1) Para cada año y mes calculamos la venta PROMEDIO POR DÍA (así meses de 28 y 31 días son comparables).
-- 2) Dividimos cada mes por el promedio de los meses de su año. AVG(...) OVER (PARTITION BY anio) calcula
--    ese promedio "por año" y lo pone al lado de cada fila, sin agrupar.
-- 3) Ponemos los meses como columnas (una tabla año x mes, como el mapa de calor del notebook).

-- RESULTADO: Paso 1.3 · Índice de estacionalidad año x mes (familias completas, 100 = mes promedio del año)
WITH por_mes AS (
    SELECT CAST(strftime('%Y', date) AS INTEGER) AS anio,
           CAST(strftime('%m', date) AS INTEGER) AS mes,
           AVG(ventas_familias_completas)        AS venta_diaria_promedio
    FROM ventas_diarias
    GROUP BY anio, mes
),
indice AS (
    SELECT anio,
           mes,
           venta_diaria_promedio / AVG(venta_diaria_promedio) OVER (PARTITION BY anio) * 100 AS indice
    FROM por_mes
)
SELECT anio,
       ROUND(MAX(CASE WHEN mes = 1  THEN indice END)) AS ene,
       ROUND(MAX(CASE WHEN mes = 2  THEN indice END)) AS feb,
       ROUND(MAX(CASE WHEN mes = 3  THEN indice END)) AS mar,
       ROUND(MAX(CASE WHEN mes = 4  THEN indice END)) AS abr,
       ROUND(MAX(CASE WHEN mes = 5  THEN indice END)) AS may,
       ROUND(MAX(CASE WHEN mes = 6  THEN indice END)) AS jun,
       ROUND(MAX(CASE WHEN mes = 7  THEN indice END)) AS jul,
       ROUND(MAX(CASE WHEN mes = 8  THEN indice END)) AS ago,
       ROUND(MAX(CASE WHEN mes = 9  THEN indice END)) AS sep,
       ROUND(MAX(CASE WHEN mes = 10 THEN indice END)) AS oct,
       ROUND(MAX(CASE WHEN mes = 11 THEN indice END)) AS nov,
       ROUND(MAX(CASE WHEN mes = 12 THEN indice END)) AS dic
FROM indice
GROUP BY anio
ORDER BY anio;
-- Lectura: diciembre es el mes más alto todos los años. 2017 no tiene diciembre (los datos llegan a agosto).


-- -----------------------------------------------------------------------------------------------------
-- Paso 1.4 · Estacionalidad semanal (periodo confiable, todas las familias)
-- -----------------------------------------------------------------------------------------------------
-- strftime('%w', date) da el día de la semana como número: 0 = domingo, 1 = lunes, ..., 6 = sábado.
-- Para ordenar de lunes a domingo usamos (número + 6) % 7, que convierte lunes en 0 y domingo en 6.

-- RESULTADO: Paso 1.4 · Índice por día de la semana desde jun-2015 (100 = día promedio)
WITH por_dia AS (
    SELECT (CAST(strftime('%w', date) AS INTEGER) + 6) % 7 AS orden,
           AVG(ventas)                                    AS venta_promedio
    FROM ventas_diarias
    WHERE date >= '2015-06-01'                           -- periodo confiable
    GROUP BY orden
)
SELECT CASE orden WHEN 0 THEN 'Lun' WHEN 1 THEN 'Mar' WHEN 2 THEN 'Mié' WHEN 3 THEN 'Jue'
                  WHEN 4 THEN 'Vie' WHEN 5 THEN 'Sáb' ELSE 'Dom' END AS dia_semana,
       ROUND(venta_promedio)                                         AS venta_promedio,
       ROUND(venta_promedio / AVG(venta_promedio) OVER () * 100)     AS indice
FROM por_dia
ORDER BY orden;
-- OVER () sin nada adentro significa "el promedio de TODAS las filas del resultado".


-- -----------------------------------------------------------------------------------------------------
-- Paso 1.4 (b) · Estacionalidad por día del mes (periodo confiable, todas las familias)
-- -----------------------------------------------------------------------------------------------------

-- RESULTADO: Paso 1.4 (b) · Índice por día del mes desde jun-2015 (100 = día promedio)
WITH por_dia_mes AS (
    SELECT CAST(strftime('%d', date) AS INTEGER) AS dia_mes,
           AVG(ventas)                           AS venta_promedio
    FROM ventas_diarias
    WHERE date >= '2015-06-01'
    GROUP BY dia_mes
)
SELECT dia_mes,
       ROUND(venta_promedio / AVG(venta_promedio) OVER () * 100) AS indice
FROM por_dia_mes
ORDER BY dia_mes;
-- Lectura: suben los días de pago (fin e inicio de mes, y un repunte alrededor del 15).
