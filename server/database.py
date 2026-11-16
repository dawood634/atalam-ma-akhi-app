"""Small DB-API boundary for local SQLite and external PostgreSQL."""
import os
import re
import sqlite3
from urllib.parse import parse_qs, urlparse

try:
    import psycopg
    from psycopg.rows import dict_row
except ImportError:
    psycopg = None
    dict_row = None

INTEGRITY_ERRORS = (sqlite3.IntegrityError,) + ((psycopg.IntegrityError,) if psycopg else ())
DATABASE_ERRORS = (sqlite3.Error,) + ((psycopg.Error,) if psycopg else ())


class DatabaseSession:
    def __init__(self, target):
        self.target = str(target)
        self.postgres = self.target.startswith(('postgres://', 'postgresql://'))
        self.connection = None

    def __enter__(self):
        if self.postgres:
            if psycopg is None:
                raise RuntimeError('PostgreSQL driver is not installed')
            parsed = urlparse(self.target)
            mode = parse_qs(parsed.query).get('sslmode', ['require'])[0]
            local_test = (os.environ.get('CLASSROOM_ALLOW_LOCAL_DATABASE') == '1'
                          and parsed.hostname in ('127.0.0.1', 'localhost', '::1')
                          and mode == 'disable')
            if mode not in ('require', 'verify-ca', 'verify-full') and not local_test:
                raise RuntimeError('A TLS-protected PostgreSQL connection is required')
            self.connection = psycopg.connect(self.target, sslmode=mode, connect_timeout=10, row_factory=dict_row)
            # Preserve SQLite's single-writer transaction semantics across worker processes.
            # A small initial deployment is intended; throughput must be measured before scaling.
            self.connection.execute('SELECT pg_advisory_xact_lock(18530041)')
        else:
            self.connection = sqlite3.connect(self.target, timeout=10)
            self.connection.row_factory = sqlite3.Row
            self.connection.execute('PRAGMA foreign_keys=ON')
        return self

    def __exit__(self, kind, value, traceback):
        try:
            if kind is None:
                self.connection.commit()
            else:
                self.connection.rollback()
        finally:
            self.connection.close()
            self.connection = None

    def execute(self, statement, parameters=()):
        if self.postgres:
            if statement.strip().upper() == 'BEGIN IMMEDIATE':
                return self.connection.execute('SELECT 1')
            statement = statement.replace('?', '%s')
        return self.connection.execute(statement, parameters)

    def executescript(self, script):
        if self.postgres:
            script = re.sub(r'PRAGMA[^;]*;', '', script)
            script = script.replace('CREATE TABLE IF NOT EXISTS attempts(',
                                    'CREATE TABLE IF NOT EXISTS attempts(sequence_id BIGSERIAL,')
            self.connection.execute(script, prepare=False)
        else:
            self.connection.executescript(script)

    @property
    def attempt_order(self):
        return 'created,sequence_id' if self.postgres else 'created,rowid'
