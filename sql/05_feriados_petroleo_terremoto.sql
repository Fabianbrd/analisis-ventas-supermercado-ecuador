-- =====================================================================================================
-- PREGUNTA 5 · ¿Los feriados, el petróleo y el terremoto de 2016 afectaron las ventas?
-- =====================================================================================================
-- Equivale a la Pregunta 5 del notebook 02_preguntas_de_negocio.ipynb.
--
-- Cómo ejecutarlo (desde la carpeta raíz del proyecto, con el entorno virtual activado):
--     python sql/ejecutar_consulta.py sql/05_feriados_petroleo_terremoto.sql
--
-- Este archivo es el más largo porque reproduce en SQL dos pasos de limpieza del notebook 01:
--   * Reglas de feriados de Kaggle: un feriado con transferred = 1 se trata como DÍA NORMAL; el día con
--     type = 'Transfer' es el FERIADO REAL. 'Bridge' cuenta como feriado y 'Work Day' como día normal.
--   * Petróleo: los días sin cotización se rellenan con el último precio conocido.
--
-- Como estas comparaciones abarcan 2013-2017, usamos las 20 FAMILIAS COMPLETAS (sin huecos de registro).
-- =====================================================================================================


-- -----------------------------------------------------------------------------------------------------
-- Paso 0 · Las 20 familias completas (misma regla que en 01_evolucion_y_estacionalidad.sql)
-- -----------------------------------------------------------------------------------------------------
-- Una familia es "completa" si en los meses sospechosos de 2014 vende al menos el 60% de lo que vende
-- en los meses vecinos. Ver la explicación detallada en el archivo de la pregunta 1.

DROP TABLE IF EXISTS temp.familias_completas;

CREATE TEMP TABLE familias_completas AS
WITH ventas_mes AS (
    SELECT family, substr(date, 1, 7) AS mes, SUM(sales) AS ventas
    FROM train
    WHERE date >= '2014-01-01' AND date < '2014-11-01'
    GROUP BY family, mes
)
SELECT family
FROM ventas_mes
GROUP BY family
HAVING COALESCE(
           AVG(CASE WHEN mes IN ('2014-02', '2014-04', '2014-05', '2014-06', '2014-08') THEN ventas END)
         / AVG(CASE WHEN mes IN ('2014-01', '2014-03', '2014-07', '2014-09', '2014-10') THEN ventas END),
       0) >= 0.6;


-- -----------------------------------------------------------------------------------------------------
-- Paso 1 · Feriados nacionales limpios: una fila por fecha
-- -----------------------------------------------------------------------------------------------------
-- 1) Clasificamos cada registro de holidays_events en un "tipo de día" con las reglas de Kaggle.
--    El orden de las condiciones del CASE importa: se usa la PRIMERA que se cumple.
-- 2) Para las ventas de todo el país usamos solo los registros nacionales (locale = 'National').
-- 3) Si una fecha tiene varios registros, nos quedamos con uno, priorizando
--    Feriado > Adicional > Evento > Día normal. ROW_NUMBER() OVER (PARTITION BY date ORDER BY prioridad)
--    numera los registros de cada fecha empezando por el más prioritario. En caso de empate usamos el orden
--    del CSV (rowid = número de fila con el que se cargó), igual que el notebook.

DROP TABLE IF EXISTS temp.feriados_nacionales;

CREATE TEMP TABLE feriados_nacionales AS
WITH clasificados AS (
    SELECT rowid AS orden_csv,
           date,
           description,
           CASE
               WHEN transferred = 1                         THEN 'Dia normal'  -- se movió a otra fecha
               WHEN type = 'Work Day'                       THEN 'Dia normal'  -- día laborable de recuperación
               WHEN type IN ('Holiday', 'Transfer', 'Bridge') THEN 'Feriado'
               WHEN type = 'Additional'                     THEN 'Adicional'   -- ej. Navidad-1 (24 de dic.)
               ELSE 'Evento'                                                    -- type = 'Event'
           END AS tipo_dia
    FROM holidays_events
    WHERE locale = 'National'
),
numerados AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY date
               ORDER BY CASE tipo_dia WHEN 'Feriado' THEN 1 WHEN 'Adicional' THEN 2
                                      WHEN 'Evento'  THEN 3 ELSE 4 END,
                        orden_csv
           ) AS n
    FROM clasificados
)
SELECT date, tipo_dia, description
FROM numerados
WHERE n = 1;


-- -----------------------------------------------------------------------------------------------------
-- Paso 2 · Tabla diaria del país: ventas, tipo de día y precio del petróleo
-- -----------------------------------------------------------------------------------------------------
-- Petróleo: para cada día buscamos el último precio conocido en esa fecha o antes
-- (ORDER BY date DESC LIMIT 1 = "el más reciente"). El 1-ene-2013 no tiene precio anterior, así que
-- usamos el siguiente disponible. COALESCE devuelve el primer valor que no sea NULL.

DROP TABLE IF EXISTS temp.diaria;

CREATE TEMP TABLE diaria AS
WITH ventas_dia AS (
    SELECT date,
           SUM(sales) AS ventas_familias_completas
    FROM train
    WHERE family IN (SELECT family FROM familias_completas)
    GROUP BY date
)
SELECT v.date,
       CAST(strftime('%Y', v.date) AS INTEGER) AS anio,
       CAST(strftime('%m', v.date) AS INTEGER) AS mes,
       CAST(strftime('%w', v.date) AS INTEGER) AS dia_semana,     -- 0 = domingo ... 6 = sábado
       v.ventas_familias_completas,
       COALESCE(f.tipo_dia, 'Dia normal')      AS tipo_dia,        -- sin registro de feriado = día normal
       f.description                           AS descripcion_feriado,
       COALESCE(
           (SELECT o.dcoilwtico FROM oil AS o
             WHERE o.date <= v.date AND o.dcoilwtico IS NOT NULL ORDER BY o.date DESC LIMIT 1),
           (SELECT o.dcoilwtico FROM oil AS o
             WHERE o.date >  v.date AND o.dcoilwtico IS NOT NULL ORDER BY o.date ASC  LIMIT 1)
       )                                       AS precio_petroleo
FROM ventas_dia AS v
LEFT JOIN feriados_nacionales AS f ON f.date = v.date;   -- LEFT JOIN: conserva todos los días, aunque no sean feriado


-- -----------------------------------------------------------------------------------------------------
-- Paso 3 · Índice de cada día vs. un día normal comparable
-- -----------------------------------------------------------------------------------------------------
-- índice = ventas del día / MEDIANA de las ventas de los días normales del mismo día de la semana, mes y año.
-- 1,0 = un día normal | 1,3 = 30% más | 0,8 = 20% menos.
-- La mediana se calcula a mano como en 04_promociones.sql (ROW_NUMBER + COUNT, tomando el valor del medio).

DROP TABLE IF EXISTS temp.diaria_indice;

CREATE TEMP TABLE diaria_indice AS
WITH normales AS (
    SELECT anio, mes, dia_semana, ventas_familias_completas AS ventas,
           ROW_NUMBER() OVER (PARTITION BY anio, mes, dia_semana ORDER BY ventas_familias_completas) AS posicion,
           COUNT(*)     OVER (PARTITION BY anio, mes, dia_semana)                                   AS n
    FROM diaria
    WHERE tipo_dia = 'Dia normal'
),
referencia AS (
    SELECT anio, mes, dia_semana,
           AVG(CASE WHEN posicion IN ((n + 1) / 2, (n + 2) / 2) THEN ventas END) AS venta_referencia
    FROM normales
    GROUP BY anio, mes, dia_semana
)
SELECT d.*,
       r.venta_referencia,
       d.ventas_familias_completas / r.venta_referencia AS indice
FROM diaria AS d
LEFT JOIN referencia AS r USING (anio, mes, dia_semana);

-- RESULTADO: 5A · Índice promedio por tipo de día (1,0 = día normal)
SELECT tipo_dia,
       ROUND(AVG(indice), 2) AS indice_promedio,
       COUNT(indice)         AS dias
FROM diaria_indice
GROUP BY tipo_dia
ORDER BY tipo_dia;


-- -----------------------------------------------------------------------------------------------------
-- Paso 5A.2 · ¿Qué feriados mueven más las ventas?
-- -----------------------------------------------------------------------------------------------------
-- Agrupamos los días alrededor de un mismo feriado limpiando la descripción:
--   * 'Navidad-1', 'Navidad+1' -> 'Navidad': quitamos un sufijo final de signo + dígitos.
--     rtrim(texto, '0123456789') borra los dígitos del final. Si después de eso el texto termina en
--     '-' o '+', era un sufijo y quitamos también el signo. Si no, dejamos la descripción como estaba.
--   * Quitamos las palabras 'Traslado ' y 'Puente ' (ej. 'Traslado Batalla de Pichincha').
--   * Todos los partidos del Mundial se agrupan como 'Mundial de fútbol 2014' y todos los días del
--     terremoto como 'Terremoto Manabí'.

-- RESULTADO: 5A.2 · Índice promedio por feriado o evento (ordenado de menor a mayor)
WITH especiales AS (
    SELECT indice,
           CASE
               WHEN descripcion_feriado LIKE 'Mundial%'   THEN 'Mundial de fútbol 2014'
               WHEN descripcion_feriado LIKE 'Terremoto%' THEN 'Terremoto Manabí'
               ELSE trim(replace(replace(
                        CASE WHEN substr(rtrim(descripcion_feriado, '0123456789'), -1) IN ('-', '+')
                                  AND rtrim(descripcion_feriado, '0123456789') <> descripcion_feriado
                             THEN substr(rtrim(descripcion_feriado, '0123456789'), 1,
                                         length(rtrim(descripcion_feriado, '0123456789')) - 1)
                             ELSE descripcion_feriado
                        END,
                    'Traslado ', ''), 'Puente ', ''))
           END AS feriado
    FROM diaria_indice
    WHERE tipo_dia <> 'Dia normal'
)
SELECT feriado,
       ROUND(AVG(indice), 2)            AS indice_promedio,
       ROUND((AVG(indice) - 1) * 100)   AS cambio_vs_dia_normal_pct,
       COUNT(*)                         AS dias
FROM especiales
GROUP BY feriado
ORDER BY indice_promedio;
-- Lectura: cada feriado aparece pocas veces (columna "dias"), así que los efectos son orientativos.


-- -----------------------------------------------------------------------------------------------------
-- Paso 5B · Petróleo: correlación de niveles vs. correlación de cambios
-- -----------------------------------------------------------------------------------------------------
-- 1) Promedio mensual de las ventas diarias (familias completas) y del precio del petróleo.
-- 2) Cambio % mes a mes y cambio % contra el mismo mes del año anterior, con LAG(x, 1) y LAG(x, 12).
-- 3) Correlación de Pearson. SQLite no la trae, así que usamos su fórmula con promedios:
--        corr(x, y) = (AVG(x*y) - AVG(x)*AVG(y)) / sqrt( (AVG(x*x) - AVG(x)^2) * (AVG(y*y) - AVG(y)^2) )
--    Va de -1 (se mueven en sentido opuesto) a +1 (se mueven juntas); 0 = sin relación lineal.

-- RESULTADO: 5B · Correlación ventas vs. petróleo (niveles, cambios mes a mes y cambios anuales)
WITH mensual AS (
    SELECT substr(date, 1, 7)             AS anio_mes,   -- 'AAAA-MM' (no lo llamamos "mes": ya existe esa columna)
           AVG(ventas_familias_completas) AS ventas,
           AVG(precio_petroleo)           AS petroleo
    FROM diaria
    GROUP BY anio_mes
),
cambios AS (
    SELECT anio_mes, ventas, petroleo,
           ventas   / LAG(ventas, 1)    OVER (ORDER BY anio_mes) - 1 AS ventas_mm,     -- mes a mes
           petroleo / LAG(petroleo, 1)  OVER (ORDER BY anio_mes) - 1 AS petroleo_mm,
           ventas   / LAG(ventas, 12)   OVER (ORDER BY anio_mes) - 1 AS ventas_aa,     -- vs. mismo mes año anterior
           petroleo / LAG(petroleo, 12) OVER (ORDER BY anio_mes) - 1 AS petroleo_aa
    FROM mensual
)
SELECT 'Niveles (engañosa)' AS comparacion,
       COUNT(*) AS meses,
       ROUND((AVG(ventas * petroleo) - AVG(ventas) * AVG(petroleo))
             / sqrt((AVG(ventas * ventas) - AVG(ventas) * AVG(ventas))
                  * (AVG(petroleo * petroleo) - AVG(petroleo) * AVG(petroleo))), 2) AS correlacion
FROM cambios
UNION ALL                                           -- UNION ALL pega los resultados uno debajo del otro
SELECT 'Cambios mes a mes',
       COUNT(*),
       ROUND((AVG(ventas_mm * petroleo_mm) - AVG(ventas_mm) * AVG(petroleo_mm))
             / sqrt((AVG(ventas_mm * ventas_mm) - AVG(ventas_mm) * AVG(ventas_mm))
                  * (AVG(petroleo_mm * petroleo_mm) - AVG(petroleo_mm) * AVG(petroleo_mm))), 2)
FROM cambios
WHERE ventas_mm IS NOT NULL                         -- el primer mes no tiene mes anterior
UNION ALL
SELECT 'Cambios vs. mismo mes del año anterior',
       COUNT(*),
       ROUND((AVG(ventas_aa * petroleo_aa) - AVG(ventas_aa) * AVG(petroleo_aa))
             / sqrt((AVG(ventas_aa * ventas_aa) - AVG(ventas_aa) * AVG(ventas_aa))
                  * (AVG(petroleo_aa * petroleo_aa) - AVG(petroleo_aa) * AVG(petroleo_aa))), 2)
FROM cambios
WHERE ventas_aa IS NOT NULL;                        -- los primeros 12 meses no tienen año anterior
-- Lectura: la correlación de los niveles sale fuerte solo porque ambas series tienen tendencia
-- (correlación espuria). Al usar cambios, desaparece.


-- -----------------------------------------------------------------------------------------------------
-- Paso 5C · Terremoto del 16 de abril de 2016
-- -----------------------------------------------------------------------------------------------------

-- RESULTADO: 5C · Ventas de cada día vs. un día normal comparable (10-abr a 1-may de 2016)
SELECT date,
       CASE dia_semana WHEN 0 THEN 'Dom' WHEN 1 THEN 'Lun' WHEN 2 THEN 'Mar' WHEN 3 THEN 'Mié'
                       WHEN 4 THEN 'Jue' WHEN 5 THEN 'Vie' ELSE 'Sáb' END AS dia,
       ROUND(indice, 2)               AS indice,
       ROUND((indice - 1) * 100)      AS cambio_vs_dia_normal_pct
FROM diaria_indice
WHERE date BETWEEN '2016-04-10' AND '2016-05-01'    -- BETWEEN incluye ambos extremos
ORDER BY date;

-- ¿Qué productos se dispararon? Semana después del terremoto (17 al 23 de abril) vs. el promedio semanal
-- de las 3 semanas anteriores (27 de marzo al 16 de abril, dividido entre 3). Aquí usamos todas las
-- familias: abril de 2016 está dentro del periodo confiable.

-- RESULTADO: 5C · Total del país: semana posterior vs. promedio semanal de las 3 semanas anteriores
SELECT ROUND(SUM(CASE WHEN date <= '2016-04-16' THEN sales END) / 3) AS semana_promedio_antes,
       ROUND(SUM(CASE WHEN date >= '2016-04-17' THEN sales END))     AS semana_despues,
       ROUND((SUM(CASE WHEN date >= '2016-04-17' THEN sales END)
              / (SUM(CASE WHEN date <= '2016-04-16' THEN sales END) / 3) - 1) * 100) AS cambio_pct
FROM train
WHERE date BETWEEN '2016-03-27' AND '2016-04-23';

-- RESULTADO: 5C · Las 8 familias con más unidades extra en la semana posterior al terremoto
WITH semanas AS (
    SELECT family,
           SUM(CASE WHEN date <= '2016-04-16' THEN sales END) / 3 AS semana_promedio_antes,
           SUM(CASE WHEN date >= '2016-04-17' THEN sales END)     AS semana_despues
    FROM train
    WHERE date BETWEEN '2016-03-27' AND '2016-04-23'
    GROUP BY family
)
SELECT family,
       ROUND(semana_promedio_antes)                                AS semana_promedio_antes,
       ROUND(semana_despues)                                       AS semana_despues,
       ROUND((semana_despues / semana_promedio_antes - 1) * 100, 1) AS cambio_pct,
       ROUND(semana_despues - semana_promedio_antes)               AS unidades_extra
FROM semanas
ORDER BY unidades_extra DESC
LIMIT 8;
