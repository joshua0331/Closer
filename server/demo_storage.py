"""Atomic persistent records for demo access and quota reservations."""
from contextlib import closing
import copy
import hashlib
import json
import os
import sqlite3
from pathlib import Path


class SQLiteRecords:
    """Local development only; Cloud Run must use Firestore."""
    def __init__(self, path):
        self.path = str(path)
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        with closing(sqlite3.connect(self.path)) as db:
            db.execute('CREATE TABLE IF NOT EXISTS records (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
            db.commit()

    def transaction(self, keys, update):
        with closing(sqlite3.connect(self.path, timeout=10, isolation_level=None)) as db:
            db.execute('BEGIN IMMEDIATE')
            try:
                state = {}
                for key in keys:
                    row = db.execute('SELECT value FROM records WHERE key=?', (key,)).fetchone()
                    state[key] = json.loads(row[0]) if row else None
                result, changes = update(copy.deepcopy(state))
                for key, value in changes.items():
                    if key not in keys:
                        raise ValueError('Unreserved record')
                    db.execute('INSERT INTO records(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', (key, json.dumps(value)))
                db.execute('COMMIT')
                return result
            except BaseException:
                db.execute('ROLLBACK')
                raise


class FirestoreRecords:
    def __init__(self, project=None, collection='closer_demo_security', database='closer-demo-backend'):
        from google.cloud import firestore
        self.firestore = firestore
        self.client = firestore.Client(project=project, database=database)
        self.collection = self.client.collection(collection)

    def transaction(self, keys, update):
        references = {key: self.collection.document(hashlib.sha256(key.encode()).hexdigest()) for key in keys}
        @self.firestore.transactional
        def run(transaction):
            # Read all documents before writing; Firestore retries the whole reservation.
            state = {}
            for key, reference in references.items():
                snapshot = reference.get(transaction=transaction)
                state[key] = snapshot.to_dict() if snapshot.exists else None
            result, changes = update(copy.deepcopy(state))
            for key, value in changes.items():
                if key not in references:
                    raise ValueError('Unreserved record')
                transaction.set(references[key], value)
            return result
        return run(self.client.transaction())


def make_records():
    mode = os.environ.get('BUDGET_STORE', 'firestore')
    if os.environ.get('K_SERVICE') and mode != 'firestore':
        raise RuntimeError('Hosted Cloud Run requires Firestore for persistent quotas.')
    if mode == 'firestore':
        return FirestoreRecords(os.environ.get('GOOGLE_CLOUD_PROJECT'), os.environ.get('BUDGET_COLLECTION', 'closer_demo_security'), os.environ.get('FIRESTORE_DATABASE', 'closer-demo-backend'))
    if mode == 'sqlite':
        return SQLiteRecords(os.environ.get('DEMO_DB_PATH', '.local/us_demo.db'))
    raise RuntimeError('Unknown budget store')
