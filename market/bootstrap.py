"""Initialize the market schema, restricted roles, and Grafana metadata database."""

import os
from pathlib import Path

import psycopg
from psycopg import sql


def initialize():
    with psycopg.connect(os.environ["ADMIN_DATABASE_URL"], autocommit=True) as connection:
        for role, setting in (("market_writer", "WRITER_PASSWORD"), ("market_reader", "READER_PASSWORD"), ("market_grafana", "GRAFANA_DB_PASSWORD")):
            password = os.environ[setting]
            if len(password) < 24:
                raise ValueError("Use generated database passwords of at least 24 characters")
            exists = connection.execute("SELECT 1 FROM pg_roles WHERE rolname=%s", (role,)).fetchone()
            command = "ALTER ROLE {} LOGIN PASSWORD {}" if exists else "CREATE ROLE {} LOGIN PASSWORD {}"
            connection.execute(sql.SQL(command).format(sql.Identifier(role), sql.Literal(password)))
        existing = connection.execute("SELECT to_regclass('market.schema_version')").fetchone()[0]
        if existing and connection.execute("SELECT version FROM market.schema_version").fetchall() != [(1,)]:
            raise ValueError("Unsupported server schema; database preserved")
        connection.execute(Path(__file__).with_name("schema.sql").read_text())
        connection.execute("GRANT USAGE ON SCHEMA market TO market_writer")
        connection.execute("GRANT SELECT ON market.schema_version TO market_writer")
        connection.execute("GRANT SELECT,INSERT,UPDATE ON market.uploads,market.observations,market.item_catalog,market.scan_times TO market_writer")
        connection.execute("GRANT USAGE ON SCHEMA reporting TO market_reader")
        connection.execute("GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO market_reader")
        connection.execute("ALTER ROLE market_reader SET statement_timeout='5s'")
        if not connection.execute("SELECT 1 FROM pg_database WHERE datname='profit_grafana'").fetchone():
            connection.execute("CREATE DATABASE profit_grafana OWNER market_grafana")


if __name__ == "__main__":
    initialize()
    print("Initialized market schema, writer/reader roles and Grafana metadata database.")
