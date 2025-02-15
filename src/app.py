from flask import Flask

from settings import DB_PASSWORD

app = Flask(__name__)


@app.get("/")
def home():
    return dict(SECRET=DB_PASSWORD)
