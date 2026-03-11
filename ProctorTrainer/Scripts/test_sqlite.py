import sqlite3, pathlib, os, datetime

DB_PATH = pathlib.Path.home() / "Library" / "Application Support" / "FRIDAY" / "SharedMemory_test.db"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

def test():
    db = sqlite3.connect(str(DB_PATH))
    db.execute("""
        CREATE TABLE IF NOT EXISTS conversations (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            ts        TEXT    NOT NULL,
            role      TEXT    NOT NULL,
            message   TEXT    NOT NULL,
            source    TEXT    DEFAULT 'imessage'
        )""")
    
    ts = datetime.datetime.now().isoformat()
    user_msg = "test msg"
    source = "imessage"
    
    db.execute(
        "INSERT INTO conversations (ts, role, message, source) VALUES (?,?,?,?)",
        (ts, "user", user_msg, source)
    )
    
    # Try the subquery with ordering and limit.
    db.execute("""
        DELETE FROM conversations WHERE id NOT IN (
            SELECT id FROM conversations ORDER BY id DESC LIMIT 200
        )""")
    db.commit()
    print("Success!")

if __name__ == "__main__":
    test()
