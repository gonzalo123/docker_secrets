import os
from pathlib import Path

from dotenv import load_dotenv

from lib.secrets import get_secret

BASE_DIR = Path(__file__).resolve().parent
ENVIRONMENT = os.getenv('ENVIRONMENT', 'local')

load_dotenv(BASE_DIR / 'env' / ENVIRONMENT / '.env')

DB_PASSWORD = get_secret("db_password", os.getenv('DEFAULT_PASSWORD'))
