import os
import psycopg
from dotenv import load_dotenv

load_dotenv("psswrds.env")
database_url = os.environ["DATABASE_URL"]

def get_connection():
    return psycopg.connect(database_url)

if __name__ == "__main__":
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT current_database(), NOW()")
            print(cur.fetchone())