"""Visit-counter API backed by PostgreSQL.

Type 2 of three in this stack: a stateless JSON API. It owns no data itself,
which is what lets it be restarted or scaled freely.

Dhruv Davda - 24BCS10203
"""
import os
import time

import psycopg
from flask import Flask, jsonify

app = Flask(__name__)

# Never hardcode the DSN: compose injects it, so the same image works in any
# environment. The default here only helps when running the file directly.
DSN = os.environ.get("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/postgres")


def connect_with_retry(attempts: int = 15, delay: float = 2.0):
    """Postgres accepts TCP before it is ready to serve queries.

    depends_on only waits for the container to start, not for the database to
    finish initialising, so the application has to tolerate early failures.
    """
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            return psycopg.connect(DSN)
        except psycopg.OperationalError as exc:
            last_error = exc
            print(f"database not ready (attempt {attempt}/{attempts}): {exc}", flush=True)
            time.sleep(delay)
    raise RuntimeError(f"could not reach the database: {last_error}")


def init_schema() -> None:
    with connect_with_retry() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS visits (
                    id         SERIAL PRIMARY KEY,
                    seen_at    TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
            )
        conn.commit()
    print("schema ready", flush=True)


@app.get("/api/health")
def health():
    """Liveness probe that also proves the database link works."""
    try:
        with psycopg.connect(DSN, connect_timeout=3) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT version()")
                version = cur.fetchone()[0]
        return jsonify(status="ok", database=version.split(",")[0])
    except Exception as exc:
        return jsonify(status="degraded", error=str(exc)), 503


@app.post("/api/visit")
@app.get("/api/visit")
def visit():
    """Record a visit and return the running total."""
    with psycopg.connect(DSN) as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO visits DEFAULT VALUES")
            cur.execute("SELECT count(*) FROM visits")
            total = cur.fetchone()[0]
        conn.commit()
    return jsonify(owner="Dhruv Davda", roll="24BCS10203", group="A", visits=total)


if __name__ == "__main__":
    init_schema()
    app.run(host="0.0.0.0", port=5000)
