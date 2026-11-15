"""
00 · Cargar los CSV de data/raw en una base de datos SQLite (data/ventas.db)

Ejecutar desde la carpeta raíz del proyecto, con el entorno virtual activado:

    .venv\\Scripts\\activate          (Windows)
    python sql/00_cargar_datos.py

Qué hace este script:
1. Crea (o vuelve a crear desde cero) el archivo data/ventas.db.
2. Crea una tabla por cada CSV de Kaggle, con el tipo de dato correcto en cada columna.
3. Copia las filas de cada CSV a su tabla.
4. Crea índices para que las consultas sobre train (3 millones de filas) sean rápidas.

La base queda dentro de data/, que está en .gitignore, así que no se sube a GitHub.
Solo usa librerías que vienen con Python (sqlite3 y csv): no hace falta instalar nada.
"""

import csv
import sqlite3
import time
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
RAW = RAIZ / "data" / "raw"
DB = RAIZ / "data" / "ventas.db"


# --- 1. Definición de las tablas ------------------------------------------------------------
# Para cada tabla indicamos: el archivo CSV, la sentencia CREATE TABLE y una función que convierte
# cada fila del CSV (que llega como texto) al tipo de dato correcto.
#
# Las fechas se guardan como texto 'AAAA-MM-DD'. SQLite no tiene un tipo "fecha", pero ese formato
# se ordena y compara bien (por ejemplo, date >= '2015-06-01') y funciona con strftime().


def numero_o_nulo(texto):
    """Convierte un texto en número decimal; si está vacío devuelve None (NULL en SQL)."""
    return float(texto) if texto != "" else None


TABLAS = {
    "train": {
        "csv": "train.csv",
        "crear": """
            CREATE TABLE train (
                id          INTEGER PRIMARY KEY,
                date        TEXT    NOT NULL,   -- fecha 'AAAA-MM-DD'
                store_nbr   INTEGER NOT NULL,   -- número de tienda (1 a 54)
                family      TEXT    NOT NULL,   -- familia de productos
                sales       REAL    NOT NULL,   -- ventas en UNIDADES (no dólares)
                onpromotion INTEGER NOT NULL    -- productos de la familia en promoción ese día
            )""",
        "convertir": lambda f: (int(f["id"]), f["date"], int(f["store_nbr"]), f["family"],
                                float(f["sales"]), int(f["onpromotion"])),
    },
    "stores": {
        "csv": "stores.csv",
        "crear": """
            CREATE TABLE stores (
                store_nbr INTEGER PRIMARY KEY,
                city      TEXT NOT NULL,
                state     TEXT NOT NULL,        -- provincia
                type      TEXT NOT NULL,        -- tipo de tienda (A a E)
                cluster   INTEGER NOT NULL
            )""",
        "convertir": lambda f: (int(f["store_nbr"]), f["city"], f["state"], f["type"], int(f["cluster"])),
    },
    "oil": {
        "csv": "oil.csv",
        "crear": """
            CREATE TABLE oil (
                date       TEXT PRIMARY KEY,
                dcoilwtico REAL                 -- precio WTI; NULL en los días sin cotización
            )""",
        "convertir": lambda f: (f["date"], numero_o_nulo(f["dcoilwtico"])),
    },
    "holidays_events": {
        "csv": "holidays_events.csv",
        "crear": """
            CREATE TABLE holidays_events (
                date        TEXT NOT NULL,
                type        TEXT NOT NULL,      -- Holiday, Transfer, Bridge, Work Day, Additional, Event
                locale      TEXT NOT NULL,      -- National, Regional o Local
                locale_name TEXT NOT NULL,
                description TEXT NOT NULL,
                transferred INTEGER NOT NULL    -- 1 = el feriado se trasladó (ese día fue normal), 0 = no
            )""",
        # En el CSV viene como el texto 'True' / 'False'; lo guardamos como 1 / 0.
        "convertir": lambda f: (f["date"], f["type"], f["locale"], f["locale_name"], f["description"],
                                1 if f["transferred"] == "True" else 0),
    },
    "transactions": {
        "csv": "transactions.csv",
        "crear": """
            CREATE TABLE transactions (
                date         TEXT    NOT NULL,
                store_nbr    INTEGER NOT NULL,
                transactions INTEGER NOT NULL   -- número de tickets de caja
            )""",
        "convertir": lambda f: (f["date"], int(f["store_nbr"]), int(f["transactions"])),
    },
}

# Índices: son como el índice de un libro, permiten encontrar filas sin leer toda la tabla.
INDICES = [
    "CREATE INDEX idx_train_date ON train (date)",
    "CREATE INDEX idx_train_store_family_date ON train (store_nbr, family, date)",
    "CREATE INDEX idx_train_family_date ON train (family, date)",
    "CREATE INDEX idx_transactions_date ON transactions (date, store_nbr)",
    "CREATE INDEX idx_holidays_date ON holidays_events (date)",
]


def cargar_tabla(conexion, nombre, definicion):
    """Crea la tabla y copia en ella todas las filas del CSV."""
    conexion.execute(definicion["crear"])
    # PRAGMA table_info devuelve una fila por columna de la tabla recién creada.
    columnas = len(conexion.execute(f"PRAGMA table_info({nombre})").fetchall())
    marcadores = ", ".join(["?"] * columnas)                  # '?, ?, ?, ...' (un ? por columna)
    with open(RAW / definicion["csv"], newline="", encoding="utf-8") as archivo:
        filas = (definicion["convertir"](f) for f in csv.DictReader(archivo))
        conexion.executemany(f"INSERT INTO {nombre} VALUES ({marcadores})", filas)
    total = conexion.execute(f"SELECT COUNT(*) FROM {nombre}").fetchone()[0]
    print(f"  {nombre:<16} {total:>10,} filas")


def main():
    faltan = [d["csv"] for d in TABLAS.values() if not (RAW / d["csv"]).exists()]
    if faltan:
        raise SystemExit(f"Faltan archivos en {RAW}: {faltan}. Revisa la sección 'Cómo descargar los datos' "
                         "del README.")

    # Empezamos siempre desde cero para que el resultado sea idéntico cada vez que se ejecuta.
    if DB.exists():
        DB.unlink()

    inicio = time.time()
    print(f"Creando {DB.relative_to(RAIZ)} ...")
    conexion = sqlite3.connect(DB)
    try:
        with conexion:                                        # todo en una transacción: más rápido
            for nombre, definicion in TABLAS.items():
                cargar_tabla(conexion, nombre, definicion)
            print("Creando índices ...")
            for sentencia in INDICES:
                conexion.execute(sentencia)
        conexion.execute("ANALYZE")                           # estadísticas para el optimizador
    finally:
        conexion.close()
    print(f"Listo en {time.time() - inicio:.0f} s. Tamaño: {DB.stat().st_size / 1e6:,.0f} MB")


if __name__ == "__main__":
    main()
