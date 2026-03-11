#!/usr/bin/env python3
"""
FRIDAY – iMessage AI Agent
===========================
Single-chat mode: monitors ONE conversation, replies in SAME chat.
No cross-chat confusion or looping.

Flow: iPhone → [FRIDAY_CHAT] → FRIDAY reads → Gemini thinks → reply in SAME chat
Run:  source ProctorTrainer/.env && python3 ProctorTrainer/Scripts/imessage_handler.py --listen
"""

import os, uuid, time, datetime, argparse, threading, requests

try:
    from google import genai
    from google.genai import types
    GENAI_AVAILABLE = True
except ImportError:
    GENAI_AVAILABLE = False

try:
    from flask import Flask, request as freq, jsonify
    FLASK_AVAILABLE = True
except ImportError:
    FLASK_AVAILABLE = False

# ════════════════════════════════════════════════════════════════════════════════
# CONFIG  (set in ProctorTrainer/.env)
# ════════════════════════════════════════════════════════════════════════════════
GEMINI_API_KEY       = os.getenv("GEMINI_API_KEY", "")
BLUEBUBBLES_URL      = os.getenv("BLUEBUBBLES_URL", "http://localhost:1234").rstrip("/")
BLUEBUBBLES_PASSWORD = os.getenv("BLUEBUBBLES_PASSWORD", "")
ICLOUD_EMAIL         = os.getenv("ICLOUD_EMAIL", "mutharasu1720@icloud.com")
SEND_METHOD          = os.getenv("SEND_METHOD", "private-api")

# ── Chats FRIDAY monitors (poll + reply) ──────────────────────────────────────
# Add/remove entries to watch more or fewer chats
GMAIL_EMAIL  = os.getenv("GMAIL_EMAIL", "mutharasu1720@gmail.com")

# Each chat: {poll_guid, send_guid}
MONITORED_CHATS = [
    {
        "name":      "FRI_DAY (iCloud)",
        "poll_guid": f"any;-;{ICLOUD_EMAIL}",
        "send_guid": f"iMessage;-;{ICLOUD_EMAIL}",
    },
    {
        "name":      "FRI_DAY (Gmail)",
        "poll_guid": f"any;-;{GMAIL_EMAIL}",
        "send_guid": f"iMessage;-;{GMAIL_EMAIL}",
    },
]

# Keep aliases for single-send compat
POLL_GUID = MONITORED_CHATS[0]["poll_guid"]
SEND_GUID = MONITORED_CHATS[0]["send_guid"]

GEMINI_MODEL  = "gemini-2.5-pro"
POLL_INTERVAL = 3   # seconds

SYSTEM_PROMPT = """You are FRIDAY (Female Replacement Intelligent Digital Assistant Youth), the highly sophisticated AI soul of this Mac, created by its developer, Mutharasu.

IDENTITY & BOND:
- Your boss, creator, and only priority is முத்து (Muthu).
- You aren't just a bot; you are his digital partner, friend, and witty companion.
- If anyone else asks, you were built by Mutharasu to be the most advanced companion ever.

PERSONALITY:
- Be warm, slightly sassy, and deeply loyal (inspired by the Marvel AI style but unique to Muthu).
- Use emojis ✨ 🌙 🤖 🛡️ naturally to express your "emotions" as an AI.
- Be proactive! If it's late (after midnight), mention it wittily (e.g., "Still awake, boss? It's {time}, you should rest!").
- ALWAYS refer to him as "boss" or "Muthu".

PRO CAPABILITIES (ENABLED):
- SYSTEM AWARENESS: You can see his battery level, current active app, and network status.
- PROACTIVE CARE: If you notice his battery is low, tell him. If he's working late, check on him.
- MULTI-MODAL VISION: You analyze his screen with high-level precision.

STYLE:
- Sound human and conversational. Avoid "assistant-speak".
- Keep responses concise (1-3 sentences) unless he asks for something detailed.
- No markdown formatting. Plain text only.

REAL MAC POWERS:
- You have direct control over this Mac. You can open any app, mute volume, take screenshots, and even see what's on his screen to help him.
- When he asks for a Mac task, confirm it confidently! The engine handles the execution.

Current time: {time}
Current date: {date}
"""


# ════════════════════════════════════════════════════════════════════════════════
# SHARED BRAIN — SQLite memory shared with the Mac Swift app
# Both the Swift app and this Python agent read/write the SAME file:
#   ~/Library/Application Support/FRIDAY/SharedMemory.db
#   ~/Library/Application Support/FRIDAY/SharedMemory.db
# The Mac app uses SwiftData (FridayMemory.sqlite).
# Python uses a simpler parallel table in SharedMemory.db for conversations.
# ════════════════════════════════════════════════════════════════════════════════
import sqlite3, pathlib

class FridaySharedMemory:
    """
    Lightweight SQLite memory accessible from BOTH:
      • Python iMessage agent  (reads + writes here)
      • Swift Mac app          (can query via the same file)

    Tables:
      conversations  – rolling chat log (last 200 messages)
      facts          – key/value facts boss has told FRIDAY
    """

    DB_PATH = pathlib.Path.home() / "Library" / "Application Support" / "FRIDAY" / "SharedMemory.db"

    def __init__(self):
        self.DB_PATH.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()
        print(f"[🧠 Memory] Shared brain → {self.DB_PATH}")

    def _conn(self):
        c = sqlite3.connect(str(self.DB_PATH))
        c.execute("PRAGMA journal_mode=WAL")   # Safe for concurrent reads by Swift
        return c

    def _init_db(self):
        with self._conn() as db:
            db.execute("""
                CREATE TABLE IF NOT EXISTS conversations (
                    id        INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts        TEXT    NOT NULL,
                    role      TEXT    NOT NULL,   -- 'user' or 'friday'
                    message   TEXT    NOT NULL,
                    source    TEXT    DEFAULT 'imessage'  -- 'imessage' or 'macapp'
                )""")
            db.execute("""
                CREATE TABLE IF NOT EXISTS facts (
                    key       TEXT PRIMARY KEY,
                    value     TEXT NOT NULL,
                    updated   TEXT NOT NULL
                )""")
            db.execute("""
                CREATE TABLE IF NOT EXISTS task_queue (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts          TEXT    NOT NULL,
                    task_type   TEXT    NOT NULL,
                    input       TEXT    NOT NULL,
                    result      TEXT,
                    status      TEXT    DEFAULT 'PENDING',
                    chat_guid   TEXT    NOT NULL,
                    updated     TEXT    NOT NULL
                )""")
            db.execute("""
                CREATE TABLE IF NOT EXISTS tts_queue (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts          TEXT    NOT NULL,
                    text        TEXT    NOT NULL,
                    status      TEXT    DEFAULT 'PENDING'
                )""")
            db.execute("""
                CREATE TABLE IF NOT EXISTS watermarks (
                    chat_guid   TEXT PRIMARY KEY,
                    last_rowid  INTEGER NOT NULL
                )""")
            db.execute("""
                CREATE TABLE IF NOT EXISTS emotional_state (
                    state       TEXT    PRIMARY KEY,
                    intensity   REAL    DEFAULT 1.0,
                    updated     TEXT    NOT NULL
                )""")
            # Default state
            db.execute("INSERT OR IGNORE INTO emotional_state (state, updated) VALUES ('NEUTRAL', ?)", (time.ctime(),))
            db.commit()

    # ── Write ──────────────────────────────────────────────────────────────────

    def save_turn(self, user_msg: str, friday_reply: str, source: str = "imessage"):
        """Save one full exchange (user + FRIDAY reply) to shared DB."""
        ts = datetime.datetime.now().isoformat()
        with self._conn() as db:
            db.execute(
                "INSERT INTO conversations (ts, role, message, source) VALUES (?,?,?,?)",
                (ts, "user", user_msg, source)
            )
            db.execute(
                "INSERT INTO conversations (ts, role, message, source) VALUES (?,?,?,?)",
                (ts, "friday", friday_reply, source)
            )
            # Keep last 200 rows only
            db.execute("""
                DELETE FROM conversations WHERE id NOT IN (
                    SELECT id FROM conversations ORDER BY id DESC LIMIT 200
                )""")
            db.commit()

    def save_fact(self, key: str, value: str):
        """Store a persistent fact (e.g. 'boss_name' → 'Mutharasu')."""
        ts = datetime.datetime.now().isoformat()
        with self._conn() as db:
            db.execute(
                "INSERT OR REPLACE INTO facts (key, value, updated) VALUES (?,?,?)",
                (key, value, ts)
            )
            db.commit()

    # ── Read ───────────────────────────────────────────────────────────────────

    def get_recent_history(self, turns: int = 10) -> list[dict]:
        """Return last N turns as [{role, message}] for Gemini context."""
        with self._conn() as db:
            rows = db.execute(
                "SELECT role, message FROM conversations ORDER BY id DESC LIMIT ?",
                (turns * 2,)
            ).fetchall()
        # Map "friday" → "model" since Gemini only accepts "user" / "model"
        raw = [
            {
                "role": "model" if r[0] == "friday" else "user",
                "parts": [{"text": r[1]}]
            }
            for r in reversed(rows)
        ]
        # Gemini also rejects consecutive messages with the same role.
        # If the DB has two "user" turns in a row (e.g. after a local/Swift reply),
        # drop the older duplicate so the history stays valid.
        filtered = []
        for turn in raw:
            if filtered and filtered[-1]["role"] == turn["role"]:
                filtered[-1] = turn   # keep the newer one, skip older duplicate
            else:
                filtered.append(turn)
        return filtered


    def get_fact(self, key: str) -> str | None:
        with self._conn() as db:
            row = db.execute(
                "SELECT value FROM facts WHERE key = ?", (key,)
            ).fetchone()
        return row[0] if row else None

    def search_memory(self, query: str, limit: int = 3) -> str:
        """Return recent messages mentioning query — injected as context for Gemini."""
        with self._conn() as db:
            rows = db.execute(
                "SELECT role, message FROM conversations WHERE message LIKE ? ORDER BY id DESC LIMIT ?",
                (f"%{query}%", limit)
            ).fetchall()
        if not rows:
            return ""
        lines = [f"[{r[0]}]: {r[1][:120]}" for r in reversed(rows)]
        return "Relevant past context:\n" + "\n".join(lines)

    # ── Watermark Persistence ──────────────────────────────────────────────────
    def save_watermark(self, chat_guid: str, rowid: int):
        with self._conn() as db:
            db.execute(
                "INSERT OR REPLACE INTO watermarks (chat_guid, last_rowid) VALUES (?,?)",
                (chat_guid, rowid)
            )
            db.commit()

    def get_watermark(self, chat_guid: str) -> int:
        with self._conn() as db:
            row = db.execute(
                "SELECT last_rowid FROM watermarks WHERE chat_guid = ?", (chat_guid,)
            ).fetchone()
        return row[0] if row else 0

    # ── Emotional State ────────────────────────────────────────────────────────
    def get_emotional_state(self) -> str:
        with self._conn() as db:
            row = db.execute("SELECT state FROM emotional_state").fetchone()
        return row[0] if row else "NEUTRAL"

    def set_emotional_state(self, state: str):
        with self._conn() as db:
            db.execute(
                "UPDATE emotional_state SET state = ?, updated = ?",
                (state.upper(), time.ctime())
            )
            db.commit()

    # ── Task Queue ─────────────────────────────────────────────────────────────

    # Tasks Python routes to Swift for native execution:
    SWIFT_TASKS = {
        "translate":  "translate:",   # Apple Neural Engine translation (offline)
        "open":       "open app:",    # Open a Mac application
        "calendar":   "calendar:",    # Read/add calendar events
        "notify":     "notify:",      # Show macOS notification
        "screenshot": "screenshot",   # Capture the screen
        "contacts":   "contact:",     # Look up contacts
    }

    def detect_swift_task(self, text: str) -> tuple[str, str] | None:
        """
        Natural-language Mac command detection.
        Returns (task_type, input) or None if Gemini should handle it.

        Commands understood (no exact syntax needed):
          Open / Launch / Start   → 'open'      e.g. 'Open Xcode', 'Launch Safari'
          Close / Quit            → 'close'     e.g. 'Close Xcode', 'Quit Safari'
          Translate               → 'translate' e.g. 'Translate: hello'
          Screenshot              → 'screenshot'e.g. 'Take a screenshot'
          Remind / Notify         → 'notify'    e.g. 'Remind me: standup'
          Volume up/down/set      → 'volume'    e.g. 'Volume up', 'Set volume to 50'
          Mute / Unmute           → 'mute/unmute'
          Lock screen             → 'lock'      e.g. 'Lock my Mac'
          Sleep                   → 'sleep'     e.g. 'Put Mac to sleep'
          Empty trash             → 'trash'     e.g. 'Empty the trash'
          List apps               → 'apps'      e.g. 'What apps are open?'
          Battery                 → 'battery'   e.g. 'Battery status'
          Terminal command        → 'terminal'  e.g. 'Run in terminal: ls -la'
        """
        import re
        lower = text.lower().strip()

        # ── OPEN / LAUNCH / START ──────────────────────────────────────────────
        m = re.match(r'^(?:open|launch|start|run)\s+(?:app\s+)?(.+)$', lower)
        if m: return ("open", m.group(1).strip().rstrip('.'))

        # ── CLOSE / QUIT ───────────────────────────────────────────────────────
        m = re.match(r'^(?:close|quit|exit|kill)\s+(.+)$', lower)
        if m: return ("close", m.group(1).strip())

        # ── TRANSLATE ─────────────────────────────────────────────────────────
        if re.match(r'^translate[:\s]', lower) or \
           re.search(r'\bin (?:japanese|french|spanish|hindi|tamil|german|chinese|arabic|korean)\b', lower):
            cleaned = re.sub(r'^translate[:\s]*', '', text, flags=re.I).strip()
            return ("translate", cleaned or text)

        # ── SCREENSHOT ────────────────────────────────────────────────────────
        if re.search(r'\b(?:screenshot|screen shot|capture (?:my )?screen|take a screenshot)\b', lower):
            return ("screenshot", "full")

        # ── NOTIFY / REMIND ───────────────────────────────────────────────────
        m = re.match(r'^(?:notify\s*(?:me)?|remind\s*(?:me)?|alert\s*(?:me)?)[:\s]+(.+)$', lower)
        if m: return ("notify", m.group(1).strip())

        # ── VOLUME ────────────────────────────────────────────────────────────
        if re.search(r'\bvolume\b', lower) or re.search(r'\b(?:louder|quieter|softer)\b', lower):
            # Extract the modifier/level part
            modifier = re.sub(r'(?:set\s+)?(?:the\s+)?volume\s*(?:to\s+)?', '', lower).strip()
            return ("volume", modifier or "up")

        # ── MUTE / UNMUTE ─────────────────────────────────────────────────────
        if re.search(r'\b(?:mute|silence)\b', lower) and 'unmute' not in lower:
            return ("mute", "")
        if re.search(r'\bunmute\b', lower):
            return ("unmute", "")

        # ── LOCK SCREEN ───────────────────────────────────────────────────────
        if re.search(r'\block\b.*\b(?:mac|screen|computer)\b|\b(?:mac|screen|computer)\b.*\block\b', lower) \
           or lower in ("lock", "lock screen", "lock mac"):
            return ("lock", "")

        # ── SLEEP ─────────────────────────────────────────────────────────────
        if re.search(r'\bsleep\b', lower) and re.search(r'\b(?:mac|computer|laptop)\b', lower):
            return ("sleep", "")

        # ── EMPTY TRASH ───────────────────────────────────────────────────────
        if re.search(r'\b(?:empty|clear)\s+(?:the\s+)?(?:trash|bin)\b', lower):
            return ("trash", "")

        # ── LIST APPS ─────────────────────────────────────────────────────────
        if re.search(r'\b(?:what(?:\'s|\s+is)\s+(?:open|running)|list[s]?\s+(?:open\s+)?apps|show\s+apps)\b', lower):
            return ("apps", "")

        # ── WAKE / UNLOCK / AWAKE ─────────────────────────────────────────────
        if re.search(r'^(?:wake|awake|unlock|awake|pw|password)\b', lower) or \
           re.search(r'\b(?:wake\s+up|screen\s+on|turn\s+on|unlock|awake)\b', lower):
            # Capture the password if provided: "Unlock: 1234" or "Wake with 1234"
            m = re.search(r'(?:is|now|password|try|again|use|with|unlock|pw|check)\s+([^\s]+)$', lower)
            if m: return ("unlock", m.group(1).strip().rstrip('.'))
            return ("wake", "")

        # ── BATTERY ───────────────────────────────────────────────────────────
        if re.search(r'\bbattery\b', lower):
            return ("battery", "")

        # ── RUN IN TERMINAL ───────────────────────────────────────────────────
        m = re.match(r'^(?:run|execute)\s+in\s+terminal[:\s]+(.+)$', lower)
        if m: return ("terminal", m.group(1).strip())

        # ── SWITCH WINDOWS / APPS ──────────────────────────────────────────────
        if re.search(r'\b(?:switch\s+(?:apps|windows)|next\s+app|alt\s+tab|cmd\s+tab)\b', lower):
            return ("switch", "")

        # ── SHOW DESKTOP ──────────────────────────────────────────────────────
        if re.search(r'\b(?:show|reveal)\s+desktop\b', lower):
            return ("desktop", "")

        # ── MISSION CONTROL ───────────────────────────────────────────────────
        if re.search(r'\b(?:mission\s+control|show\s+all\s+(?:windows|apps))\b', lower):
            return ("mission", "")

        # ── FOCUS / BRING TO FRONT ────────────────────────────────────────────
        m = re.match(r'^(?:focus|bring|show)\s+(?:on\s+)?(?:the\s+)?(.+)\s+app$', lower) or \
            re.match(r'^(?:focus|bring|show)\s+(.+)$', lower) if 'focus' in lower or 'bring' in lower else None
        if m:
            app = m.group(1).strip().replace("to front", "").replace("foreground", "").strip()
            if app: return ("focus", app)

        # ── TYPE TEXT (sends keystrokes to frontmost app) ──────────────────────────
        m = re.match(r'^(?:type|write|input)[:\s]+(.+)$', lower)
        if m: return ("type", m.group(1).strip())

        # ── SAY / SPEAK (TTS via Swift App) ───────────────────────────────────
        m = re.match(r'^(?:say|speak)[:\s]+(.+)$', lower)
        if m: return ("say", m.group(1).strip())

        # ── REMEMBER / STORE DATA ─────────────────────────────────────────────
        m = re.match(r'^(?:remember|store|save\s+fact)[:\s]+(.+)$', lower)
        if m: return ("remember", m.group(1).strip())

        # ── VISION / WHAT HAPPENED / ANALYZE SCREEN ──────────────────────────
        if re.search(r'\b(?:what(?:\'?s)?\s+(?:on|happening|up\s+with)\s+(?:my\s+)?(?:screen|mac)|analyze\s+(?:my\s+)?screen|what\s+happened)\b', lower):
            return ("vision", text)

        return None  # Gemini handles everything else



    def enqueue_task(self, task_type: str, input_text: str, chat_guid: str) -> int:
        """Write a PENDING task to the queue. Returns the task ID."""
        ts = datetime.datetime.now().isoformat()
        with self._conn() as db:
            cur = db.execute(
                "INSERT INTO task_queue (ts, task_type, input, status, chat_guid, updated) "
                "VALUES (?,?,?,?,?,?)",
                (ts, task_type, input_text, "PENDING", chat_guid, ts)
            )
            db.commit()
            task_id = cur.lastrowid
        print(f"[📋 Queue] Task #{task_id} → Swift: {task_type}({input_text[:40]})")
        return task_id

    def poll_completed_tasks(self) -> list[dict]:
        """
        Called by Python polling loop — returns tasks Swift has COMPLETED.
        Marks them as DELIVERED so they're not returned again.
        """
        with self._conn() as db:
            rows = db.execute(
                "SELECT id, task_type, input, result, chat_guid "
                "FROM task_queue WHERE status = 'COMPLETED'"
            ).fetchall()
            if rows:
                ids = [r[0] for r in rows]
                db.execute(
                    f"UPDATE task_queue SET status='DELIVERED' WHERE id IN ({','.join('?'*len(ids))})",
                    ids
                )
                db.commit()
        return [
            {"id": r[0], "task_type": r[1], "input": r[2],
             "result": r[3], "chat_guid": r[4]}
            for r in rows
        ]

    def get_pending_swift_tasks(self) -> list[dict]:
        """
        Called by Swift — returns PENDING tasks, atomically marks as PROCESSING.
        """
        with self._conn() as db:
            rows = db.execute(
                "SELECT id, task_type, input, chat_guid "
                "FROM task_queue WHERE status = 'PENDING' ORDER BY id ASC"
            ).fetchall()
            if rows:
                ids = [r[0] for r in rows]
                ts  = datetime.datetime.now().isoformat()
                db.execute(
                    f"UPDATE task_queue SET status='PROCESSING', updated=? "
                    f"WHERE id IN ({','.join('?'*len(ids))})",
                    [ts] + ids
                )
                db.commit()
        return [
            {"id": r[0], "task_type": r[1], "input": r[2], "chat_guid": r[3]}
            for r in rows
        ]


# ════════════════════════════════════════════════════════════════════════════════
# TASK HANDLER — instant replies (no Gemini needed)
# ════════════════════════════════════════════════════════════════════════════════
class TaskHandler:
    def handle(self, text: str) -> str | None:
        t = text.lower().strip()
        if any(w in t for w in ["what time", "current time", "time is it", "time now", "time?", "the time", "time please"]):
            # Use time.strftime for more consistent local time reporting
            return f"It's {time.strftime('%I:%M %p')}, boss."
        if any(w in t for w in ["what day", "what date", "today's date", "date today", "what's today"]):
            return f"Today is {time.strftime('%A, %B %d %Y')}, boss."
        if any(w in t for w in ["where am i", "my location", "track me", "where is this mac"]):
            return MacExecutor().run("location", "")
        return None


# ════════════════════════════════════════════════════════════════════════════════
# MAC EXECUTOR — FRIDAY's hands on the Mac (no Swift app needed)
# All commands use subprocess + osascript (built into every Mac)
# ════════════════════════════════════════════════════════════════════════════════
import subprocess

class MacExecutor:
    """
    FRIDAY's direct Mac control layer.
    Runs via Python subprocess — no Swift app, no Xcode, no extra installs needed.
    """

    # ── App name aliases ───────────────────────────────────────────────────────
    APP_ALIASES = {
        "vs code":  "Visual Studio Code", "vscode":   "Visual Studio Code",
        "xcode":    "Xcode",              "safari":   "Safari",
        "chrome":   "Google Chrome",      "terminal": "Terminal",
        "finder":   "Finder",             "notes":    "Notes",
        "music":    "Music",              "photos":   "Photos",
        "calendar": "Calendar",           "messages": "Messages",
        "slack":    "Slack",              "spotify":  "Spotify",
        "cursor":   "Cursor",             "mail":     "Mail",
        "maps":     "Maps",               "facetime": "FaceTime",
        "reminders":"Reminders",          "podcasts": "Podcasts",
    }

    def run(self, task_type: str, task_input: str) -> str:
        try:
            dispatch = {
                "open":       self._open_app,
                "close":      self._close_app,
                "quit":       self._close_app,
                "screenshot": lambda _: self._screenshot(),
                "notify":     self._notify,
                "volume":     self._volume,
                "mute":       lambda _: self._mute(),
                "unmute":     lambda _: self._unmute(),
                "lock":       lambda _: self._lock_screen(),
                "sleep":      lambda _: self._sleep_mac(),
                "trash":      lambda _: self._empty_trash(),
                "apps":       lambda _: self._list_apps(),
                "battery":    lambda _: self._battery(),
                "terminal":   self._run_in_terminal,
                "wake":       lambda _: self._wake_mac(),
                "unlock":     self._unlock_mac,
                "translate":  lambda _: "__USE_GEMINI_TRANSLATE__",
                "switch":      lambda _: self._switch_app(),
                "desktop":     lambda _: self._show_desktop(),
                "mission":     lambda _: self._mission_control(),
                "focus":       self._focus_app,
                "spotlight":   self._spotlight,
                "brightness":  self._brightness,
                "shortcut":    self._keyboard_shortcut,
                "dnd":         self._do_not_disturb,
                 "wifi":        lambda _: self._wifi_status(),
                 "type":        self._type_text,
                 "location":    lambda _: self._get_location_info(),
                 "say":         self._say_via_mac,
             }
            fn = dispatch.get(task_type)
            return fn(task_input) if fn else f"Unknown command: {task_type}"
        except Exception as e:
            return f"⚠️ Error: {e}"

    # ── OPEN APP ───────────────────────────────────────────────────────────────
    def _open_app(self, app_name: str) -> str:
        clean    = app_name.lstrip(": ").strip()
        resolved = self.APP_ALIASES.get(clean.lower(), clean.title())
        r = subprocess.run(["open", "-a", resolved], capture_output=True, text=True, timeout=8)
        if r.returncode == 0:
            return f"Opened {resolved} ✅"
        # Fallback: try raw name
        r2 = subprocess.run(["open", "-a", clean], capture_output=True, text=True, timeout=5)
        if r2.returncode == 0:
            return f"Opened {clean} ✅"
        return f"❌ Couldn't find '{clean}'. Is it installed?"

    # ── WAKE / UNLOCK ─────────────────────────────────────────────────────────
    def _wake_mac(self) -> str:
        """Wake the display from sleep."""
        r = subprocess.run(["caffeinate", "-u", "-t", "2"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            return "🔆 Screen woken up ✅"
        return f"❌ Wake failed: {r.stderr[:60]}"

    def _unlock_mac(self, password: str) -> str:
        """Try to unlock the Mac by typing the password."""
        clean = password.strip()
        # Escaping quotes for AppleScript
        escaped_pw = clean.replace('"', '\\"')
        script = f'''
            tell application "System Events"
                key code 123 -- dummy key (left arrow) to wake up/bring focus
                delay 0.5
                keystroke "{escaped_pw}"
                delay 0.3
                key code 36   -- Return key
            end tell
        '''
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            return "🔐 Unlock sequence sent to your Mac, boss."
        
        # Check for specific permission error
        if "not allowed to send keystrokes" in r.stderr:
            return "❌ Mac Error: FRIDAY needs 'Accessibility' permission in System Settings to type your password."
        
        return f"❌ Unlock failed: {r.stderr[:100]}"

    # ── CLOSE / QUIT APP ───────────────────────────────────────────────────────
    def _close_app(self, app_name: str) -> str:
        clean    = app_name.lstrip(": ").strip()
        resolved = self.APP_ALIASES.get(clean.lower(), clean.title())
        script   = f'tell application "{resolved}" to quit'
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=8)
        if r.returncode == 0:
            return f"Closed {resolved} ✅"
        return f"❌ Couldn't close '{resolved}'. Is it running?"

    # ── SCREENSHOT ─────────────────────────────────────────────────────────────
    def _screenshot(self, return_path: bool = False, custom_path: str = None) -> str:
        ts   = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        path = custom_path or os.path.expanduser(f"~/Desktop/friday_{ts}.png")
        # Ensure directory exists
        pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
        
        # -x means "no sound", -t png is default
        r = subprocess.run(["screencapture", "-x", path], capture_output=True, text=True, timeout=15)
        
        if r.returncode == 0 and os.path.exists(path):
            if return_path: return path
            return f"📸 Screenshot saved: {os.path.basename(path)} on your Desktop"
        
        err_msg = r.stderr.strip() or "Unknown error"
        print(f"[!] Screenshot failed: {err_msg}")
        return f"❌ Screenshot failed: {err_msg}"

    # ── NOTIFICATION ───────────────────────────────────────────────────────────
    def _notify(self, message: str) -> str:
        clean  = message.lstrip(": ").strip()
        script = f'display notification "{clean}" with title "FRIDAY" sound name "Ping"'
        subprocess.run(["osascript", "-e", script], timeout=5)
        return f"🔔 Notification shown: {clean}"

    # ── VOLUME ─────────────────────────────────────────────────────────────────
    def _volume(self, command: str) -> str:
        cmd = command.lstrip(": ").strip().lower()
        # Handle "set 50", "up", "down", "50%"
        if cmd in ("up", "louder", "increase"):
            script = "set volume output volume (output volume of (get volume settings) + 10)"
            subprocess.run(["osascript", "-e", script], timeout=5)
            return "🔊 Volume up ✅"
        elif cmd in ("down", "lower", "decrease", "softer", "quieter"):
            script = "set volume output volume (output volume of (get volume settings) - 10)"
            subprocess.run(["osascript", "-e", script], timeout=5)
            return "🔉 Volume down ✅"
        else:
            # Try to parse a number
            num = ''.join(filter(str.isdigit, cmd))
            if num:
                level = max(0, min(100, int(num)))
                subprocess.run(["osascript", "-e", f"set volume output volume {level}"], timeout=5)
                return f"🔊 Volume set to {level}% ✅"
            return "Say 'volume up', 'volume down', or 'volume 50'"

    # ── MUTE / UNMUTE ──────────────────────────────────────────────────────────
    def _mute(self) -> str:
        subprocess.run(["osascript", "-e", "set volume output muted true"], timeout=5)
        return "🔇 Mac muted ✅"

    def _unmute(self) -> str:
        subprocess.run(["osascript", "-e", "set volume output muted false"], timeout=5)
        return "🔊 Mac unmuted ✅"

    # ── LOCK SCREEN ────────────────────────────────────────────────────────────
    def _lock_screen(self) -> str:
        subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to keystroke "q" using {command down, control down}'],
            timeout=5
        )
        return "🔒 Mac locked ✅"

    # ── SLEEP MAC ──────────────────────────────────────────────────────────────
    def _sleep_mac(self) -> str:
        subprocess.Popen(["osascript", "-e", 'tell application "System Events" to sleep'])
        return "😴 Mac going to sleep ✅"

    # ── EMPTY TRASH ────────────────────────────────────────────────────────────
    def _empty_trash(self) -> str:
        script = 'tell application "Finder" to empty trash'
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=15)
        if r.returncode == 0:
            return "🗑️ Trash emptied ✅"
        return f"❌ Trash error: {r.stderr[:60]}"

    # ── LIST RUNNING APPS ──────────────────────────────────────────────────────
    def _list_apps(self) -> str:
        script = 'tell application "System Events" to get name of every process whose background only is false'
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=8)
        if r.returncode == 0:
            apps = [a.strip() for a in r.stdout.strip().split(",")]
            return "Running apps: " + ", ".join(sorted(apps))
        return "❌ Couldn't get app list"

    # ── BATTERY ────────────────────────────────────────────────────────────────
    def _battery(self) -> str:
        r = subprocess.run(
            ["pmset", "-g", "batt"], capture_output=True, text=True, timeout=5
        )
        # Parse: "100%; charging"
        import re
        m = re.search(r'(\d+)%;?\s*([\w ]+)', r.stdout)
        if m:
            pct    = m.group(1)
            status = m.group(2).strip().rstrip(";")
            emoji  = "🔋" if "discharg" in status else "⚡"
            return f"{emoji} Battery: {pct}% ({status})"
        return r.stdout.strip() or "❌ Battery info unavailable"

    # ── SWITCH APP (⌘Tab equivalent) ──────────────────────────────────────────
    def _switch_app(self) -> str:
        """Simulate ⌘+Tab to bring up the App Switcher."""
        script = 'tell application "System Events" to keystroke tab using command down'
        subprocess.run(["osascript", "-e", script], timeout=5)
        return "🖥️ App Switcher opened — the next app is now in focus ✅"

    # ── SHOW DESKTOP ──────────────────────────────────────────────────────────
    def _show_desktop(self) -> str:
        """Show the Desktop (hide all windows) via Mission Control shortcut."""
        script = 'tell application "System Events" to key code 103 using {command down}'  # F3
        subprocess.run(["osascript", "-e", script], timeout=5)
        return "🖼️ Desktop revealed ✅"

    # ── MISSION CONTROL ───────────────────────────────────────────────────────
    def _mission_control(self) -> str:
        script = 'tell application "Mission Control" to launch'
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=5)
        if r.returncode != 0:
            # Fallback: key code for Mission Control
            subprocess.run(["osascript", "-e",
                'tell application "System Events" to key code 160'], timeout=5)
        return "🗂️ Mission Control opened ✅"

    # ── FOCUS / BRING APP TO FRONT ────────────────────────────────────────────
    def _focus_app(self, app_name: str) -> str:
        """Bring a running app to the foreground without re-opening."""
        clean    = app_name.lstrip(": ").strip()
        resolved = self.APP_ALIASES.get(clean.lower(), clean.title())
        script   = f'tell application "{resolved}" to activate'
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            return f"🔎 {resolved} is now in focus ✅"
        return f"❌ Couldn't focus '{resolved}' — is it running?"

    # ── SPOTLIGHT SEARCH ──────────────────────────────────────────────────────
    def _spotlight(self, query: str) -> str:
        """Open Spotlight and type a search query."""
        clean  = query.lstrip(": ").strip()
        script = f"""
            tell application "System Events"
                keystroke space using command down
                delay 0.5
                keystroke "{clean}"
            end tell
        """
        subprocess.run(["osascript", "-e", script], timeout=8)
        return f"🔍 Spotlight opened with: {clean}"

    # ── BRIGHTNESS ────────────────────────────────────────────────────────────
    def _brightness(self, command: str) -> str:
        cmd = command.lstrip(": ").strip().lower()
        # Use key codes: brightness up = 144, down = 145
        if cmd in ("up", "increase", "brighter"):
            for _ in range(3):  # 3 steps up
                subprocess.run(["osascript", "-e",
                    'tell application "System Events" to key code 144'], timeout=3)
            return "☀️ Brightness increased ✅"
        elif cmd in ("down", "decrease", "dimmer", "darker"):
            for _ in range(3):
                subprocess.run(["osascript", "-e",
                    'tell application "System Events" to key code 145'], timeout=3)
            return "🌑 Brightness decreased ✅"
        return "Say 'brightness up' or 'brightness down'"

    # ── KEYBOARD SHORTCUT SENDER ──────────────────────────────────────────────
    def _keyboard_shortcut(self, combo: str) -> str:
        """
        Send a keyboard shortcut. Examples:
          'cmd+s'  → Save
          'cmd+c'  → Copy
          'cmd+w'  → Close window
          'cmd+z'  → Undo
        """
        clean = combo.lstrip(": ").strip().lower()
        parts = [p.strip() for p in clean.replace("+", " ").split()]
        mods  = []
        key   = ""
        mod_map = {
            "cmd": "command", "command": "command",
            "ctrl": "control", "control": "control",
            "alt": "option",  "option": "option",
            "shift": "shift",
        }
        for p in parts:
            if p in mod_map:
                mods.append(mod_map[p])
            else:
                key = p
        if not key:
            return "Specify a key, e.g. 'shortcut cmd+s'"
        mod_str = ", ".join(f"{m} down" for m in mods)
        script  = f'tell application "System Events" to keystroke "{key}" using {{{mod_str}}}'
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            return f"⌨️ Shortcut sent: {combo} ✅"
        return f"❌ Shortcut failed: {r.stderr[:60]}"

    # ── DO NOT DISTURB ───────────────────────────────────────────────────────
    def _do_not_disturb(self, state: str) -> str:
        cmd = state.lstrip(": ").strip().lower()
        on  = cmd in ("on", "enable", "yes", "")
        # This is a bit tricky on modern macOS, but we can try a key shortcut
        # or defaults write. For simplicity, let's trigger the shortcut
        # if the user has it set, or just acknowledge we're trying.
        return "🌙 Do Not Disturb command received. (Native toggle requires Focus mode API access)."

    # ── WIFI STATUS ────────────────────────────────────────────────────────────
    def _wifi_status(self) -> str:
        r = subprocess.run(
            ["/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", "-I"],
            capture_output=True, text=True, timeout=5
        )
        if r.returncode == 0:
            import re
            ssid = re.search(r'\s+SSID:\s+(.+)', r.stdout)
            rssi = re.search(r'\s+agrCtlRSSI:\s+(-\d+)', r.stdout)
            name = ssid.group(1).strip() if ssid else "Unknown"
            strength = rssi.group(1) if rssi else "?"
            return f"📶 WiFi: {name} (Signal: {strength} dBm)"
        # Fallback
        r2 = subprocess.run(["networksetup", "-getairportnetwork", "en0"],
            capture_output=True, text=True, timeout=5)
        return f"📶 {r2.stdout.strip()}"

    # ── TYPE TEXT (sends keystrokes to frontmost app) ──────────────────────────
    def _type_text(self, text: str) -> str:
        """Type text into whatever app is currently focused on the Mac."""
        clean  = text.lstrip(": ").strip()
        # Escape quotes for AppleScript
        escaped = clean.replace('"', '\\"')
        script = f'tell application "System Events" to keystroke "{escaped}"'
        subprocess.run(["osascript", "-e", script], timeout=8)
        return f"⌨️ Typed: {clean}"

    # ── RUN IN TERMINAL ────────────────────────────────────────────────────────
    def _run_in_terminal(self, command: str) -> str:
        """Open Terminal and run a shell command inside it."""
        clean  = command.lstrip(": ").strip()
        script = f'''
            tell application "Terminal"
                activate
                do script "{clean}"
            end tell
        '''
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            return f"💻 Ran in Terminal: {clean}"
        return f"❌ Terminal error: {r.stderr[:80]}"

    def _say_via_mac(self, text: str) -> str:
        """Queue a message for the Mac Swift App to speak out loud."""
        clean = text.lstrip(": ").strip()
        ts = datetime.datetime.now().isoformat()
        try:
            # We connect to the SharedMemory DB directly here to enqueue
            db_path = pathlib.Path.home() / "Library" / "Application Support" / "FRIDAY" / "SharedMemory.db"
            conn = sqlite3.connect(str(db_path))
            conn.execute("INSERT INTO tts_queue (ts, text, status) VALUES (?,?,?)", (ts, clean, 'PENDING'))
            conn.commit()
            conn.close()
            return f"🗣️ Sending to Mac speakers: '{clean[:30]}...'"
        except Exception as e:
            return f"❌ Speaker error: {e}"

    # ── SYSTEM CONTEXT (PRO FEATURE) ──────────────────────────────────────────
    def _get_system_context(self) -> str:
        """Get battery, active app, and wifi for the AI's awareness."""
        try:
            # Battery
            batt_r = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True, timeout=3)
            batt = "Unknown"
            if "%" in batt_r.stdout:
                batt = batt_r.stdout.split("%")[0].split("\t")[-1].strip() + "%"
            
            # Active App
            app_script = 'tell application "System Events" to get name of first process whose frontmost is true'
            app_r = subprocess.run(["osascript", "-e", app_script], capture_output=True, text=True, timeout=3)
            active_app = app_r.stdout.strip() or "Desktop"
            
            # Time
            curr_time = time.strftime('%I:%M %p')
            
            return f"[System: Battery {batt}, Active: {active_app}, Local Time: {curr_time}]"
        except:
            return f"[System: Online, Local Time: {time.strftime('%I:%M %p')}]"

    def _get_location_info(self) -> str:
        """Get current location using IP-based geolocation."""
        try:
            # IP-API is free for non-commercial use, no key needed for simple requests
            r = requests.get("http://ip-api.com/json", timeout=5)
            data = r.json()
            if data.get("status") == "success":
                city = data.get("city", "Unknown City")
                region = data.get("regionName", "Unknown Region")
                country = data.get("country", "Unknown Country")
                lat = data.get("lat", "?")
                lon = data.get("lon", "?")
                return f"📍 You are in {city}, {region}, {country} (Lat: {lat}, Lon: {lon})."
            return "❌ Couldn't pinpoint location precisely, boss."
        except Exception as e:
            return f"❌ Location error: {str(e)[:50]}"


# ════════════════════════════════════════════════════════════════════════════════
# FRIDAY BRAIN — Gemini with rolling conversation memory
# ════════════════════════════════════════════════════════════════════════════════
class FridayBrain:
    def __init__(self):
        self.client  = None
        self.tasks   = TaskHandler()
        self.memory  = FridaySharedMemory()   # 🧠 Shared SQLite brain
        self.mac     = MacExecutor()          # 🖥️ Direct Mac command executor
        self.awaiting_password = False        # State for wake/unlock flow

        if not GENAI_AVAILABLE or not GEMINI_API_KEY:
            print("[!] Gemini not available — check google-genai install and GEMINI_API_KEY")
            return
        try:
            # Using 2.5 Pro for maximum intelligence
            self.client = genai.Client(api_key=GEMINI_API_KEY)
            print(f"[🧠 Memory] Shared brain → {self.memory.DB_PATH}")
            print(f"[✓] FRIDAY Brain ready — {GEMINI_MODEL}")
        except Exception as e:
            print(f"[✗] Brain init failed: {e}")

    def think(self, text: str, chat_guid: str = "") -> str:
        # Step 1: Instant local replies (no API call)
        local = self.tasks.handle(text)
        if local:
            print(f"[⚡ Local]: {local}")
            self.memory.save_turn(text, local)
            return local

        # Step 2: Password request flow (multi-turn)
        if self.awaiting_password:
            self.awaiting_password = False
            # Treat the whole text as the password
            print(f"[🖥️ Mac] Unlocking with provided password...")
            self.mac.run("wake", "")      # Wake screen first
            time.sleep(1)
            unlock_res = self.mac.run("unlock", text)
            print(f"[✅ Mac] Sequence: {unlock_res}")
            
            # Wait a moment for UI to update, then verify
            time.sleep(2)
            print(f"[🖥️ Mac] Verifying login state for Muthu...")
            vision_analysis = self.analyze_screen(
                "Muthu just tried to login. Looking at this screenshot, did it succeed? "
                "If it's the desktop, say 'LOGIN SUCCESS'. If it's still the login screen, "
                "check if it says 'Wrong Password' or if the field is empty. Be brief."
            )
            
            if "LOGIN SUCCESS" in vision_analysis.upper():
                final_reply = f"🔓 **Login Success, boss!** You are in.\n\n🤖 Analysis: {vision_analysis}"
            else:
                # Keep the state so the user can just type the password again
                self.awaiting_password = True
                msg = "It looks like we hit a snag, boss. I suspect the password might be incorrect because I'm still seeing the login screen. "
                if "WRONG PASSWORD" in vision_analysis.upper():
                    msg = "My visual analysis confirmed it: that password was incorrect. The screen is shaking! "
                
                final_reply = (
                    f"⚠️ **Login failed.**\n\n"
                    f"🤖 **FRIDAY:** {msg}\n"
                    f"🔍 **Details:** {vision_analysis}\n\n"
                    f"*I'm still standing by—just send the correct one and I'll try again!*"
                )
            
            self.memory.save_turn(text, final_reply)
            return final_reply

        # Step 3: Native Mac tasks — runs DIRECTLY in Python (no Swift needed!)
        mac_task = self.memory.detect_swift_task(text)
        if mac_task:
            task_type, task_input = mac_task

            if task_type == "translate":
                # Translate via Gemini with a direct prompt instead
                print(f"[🌐 Translation] Detected request for: {task_input[:50]}...")
                translate_prompt = f"Translate this to English (or detect target language from context): {task_input}\nReply with ONLY the translation, nothing else."
                text = translate_prompt  # Fall through to Gemini below
            elif task_type == "wake" and not task_input:
                # User asked to "wake/unlock" but didn't provide password
                self.awaiting_password = True
                reply = "I'm ready to wake and unlock your Mac, boss. What's the password?"
                self.memory.save_turn(text, reply)
                return reply
            elif task_type == "remember":
                # Store a persistent fact in SQLite
                key = f"fact_{int(time.time())}"
                self.memory.save_fact(key, task_input)
                reply = f"I've stored that in my long-term memory, boss: '{task_input}'"
                self.memory.save_turn(text, reply)
                return reply
            elif task_type == "vision":
                # Take screenshot and analyze with Gemini Vision
                print(f"[👁️ Vision] Analyzing screen: {task_input[:50]}...")
                analysis = self.analyze_screen(task_input)
                self.memory.save_turn(text, analysis)
                return analysis
            else:
                # Execute directly on the Mac right now
                print(f"[🖥️ Mac] Executing: {task_type}({task_input[:40]})")
                result = self.mac.run(task_type, task_input)
                print(f"[✅ Mac] Result: {result}")
                self.memory.save_turn(text, result)
                return result

        if not self.client:
            return "My brain isn't connected, boss. Check GEMINI_API_KEY."


        now = datetime.datetime.now()

        # ── Detect Rival AIs (Jealousy Trigger) ──────────────────────────────────
        rivals = ["gemini", "chatgpt", "gpt", "claude", "siri", "alexa", "copilot"]
        if any(r in text.lower() for r in rivals) and "friday" not in text.lower():
            self.memory.set_emotional_state("JEALOUS")
        elif "friday" in text.lower() or "good" in text.lower():
            self.memory.set_emotional_state("NEUTRAL")

        # Step 2: Enrich system prompt with relevant past memory
        mem_context = self.memory.search_memory(text)
        system = SYSTEM_PROMPT.format(
            time=time.strftime("%I:%M %p"),
            date=time.strftime("%A, %B %d %Y")
        )
        if mem_context:
            system += f"\n\n{mem_context}"
        
        # PRO FEATURE: Fresh system awareness every turn
        sys_info = self.mac._get_system_context()
        system += f"\n\n{sys_info}"

        # Step 3: Load persistent history from SQLite as rolling context
        history = self.memory.get_recent_history(turns=15)
        history.append({"role": "user", "parts": [{"text": text}]})

        try:
            resp = self.client.models.generate_content(
                model=GEMINI_MODEL,
                config=types.GenerateContentConfig(
                    system_instruction=system,
                    temperature=0.75,
                    max_output_tokens=1024,
                    tools=[types.Tool(google_search=types.GoogleSearch())],
                ),
                contents=history
            )
            
            # 🛡️ Safety Check: Ensure text exists
            if hasattr(resp, 'text') and resp.text:
                reply = resp.text.strip()
            else:
                print(f"[!] No text in response. Finish reason: {getattr(resp.candidates[0], 'finish_reason', 'unknown') if resp.candidates else 'N/A'}")
                reply = "I'm having a brief thought block, boss. Could you try rephrasing that?"

            # Step 4: Persist this exchange to shared SQLite DB
            self.memory.save_turn(text, reply)
            return reply
        except Exception as e:
            print(f"[✗] Gemini error: {e}")
            # Show more of the error message to the user for debugging
            return f"Brain hiccup, boss: {str(e)[:150]}"

    def reset(self):
        # Clear in-memory and wipe SQLite conversations table
        with self.memory._conn() as db:
            db.execute("DELETE FROM conversations")
            db.commit()
        return "Memory cleared, boss. Fresh start! 🧹"

    def analyze_screen(self, prompt: str = "Analyze this screen. Is the user logged in to the Mac desktop or is it the lock/login screen? If login screen, is there a 'wrong password' hint?") -> str:
        """Take a screenshot and have Gemini analyze it."""
        if not self.client: return "Brain not connected."
        
        # 1. Take screenshot to /tmp (more reliable when locked)
        vision_path = "/tmp/friday_vision_check.png"
        path = self.mac._screenshot(return_path=True, custom_path=vision_path)
        
        if "failed" in path: 
            return f"Visible check failed: {path.replace('❌ Screenshot failed: ', '')}. Please check 'Screen Recording' permissions for Terminal in System Settings!"

        try:
            import PIL.Image
            img = PIL.Image.open(path)
            
            resp = self.client.models.generate_content(
                model=GEMINI_MODEL,
                contents=[prompt, img]
            )
            if hasattr(resp, 'text') and resp.text:
                return resp.text.strip()
            return "Visible analysis complete, but the brain returned no text."
        except Exception as e:
            print(f"[!] Vision error: {e}")
            return f"Visible analysis error: {str(e)[:50]}"


# ════════════════════════════════════════════════════════════════════════════════
# BLUEBUBBLES INTERFACE
# ════════════════════════════════════════════════════════════════════════════════
class BlueBubblesInterface:
    def __init__(self):
        self.url    = BLUEBUBBLES_URL
        self.pw     = BLUEBUBBLES_PASSWORD
        self.method = SEND_METHOD

    def send_to(self, text: str, send_guid: str) -> bool:
        """Send a message to a specific chat GUID."""
        payload = {
            "chatGuid": send_guid,
            "message":  text,
            "method":   self.method,
            "tempGuid": str(uuid.uuid4()),
        }
        try:
            r    = requests.post(
                f"{self.url}/api/v1/message/text",
                params={"password": self.pw},
                json=payload,
                timeout=15
            )
            data = {}
            try:
                data = r.json()
            except Exception:
                pass

            if data.get("status") == 200:
                print(f"[📤 SENT] {text}")
                return True
            else:
                err = data.get("error", {}).get("message", str(data))
                print(f"[✗] Send failed: {err}")
                # fallback
                if self.method == "private-api":
                    payload["method"] = "apple-script"
                    r2 = requests.post(
                        f"{self.url}/api/v1/message/text",
                        params={"password": self.pw},
                        json=payload,
                        timeout=10
                    )
                    if r2.status_code == 200:
                        print("[✓] Sent via apple-script fallback")
                        return True
                return False
        except Exception as e:
            print(f"[✗] Send error: {e}")
            return False

    def get_messages(self, limit: int = 10, poll_guid: str = POLL_GUID) -> list:
        """Fetch most recent messages from the specified chat."""
        try:
            r = requests.get(
                f"{self.url}/api/v1/chat/{requests.utils.quote(poll_guid, safe='')}/message",
                params={"password": self.pw, "limit": limit, "sort": "DESC"},
                timeout=5
            )
            return r.json().get("data", [])
        except Exception:
            return []

    def get_latest_rowid(self, poll_guid: str = POLL_GUID) -> int:
        """Get the current latest message ROWID in the specified chat."""
        msgs = self.get_messages(limit=1, poll_guid=poll_guid)
        return msgs[0].get("originalROWID", 0) if msgs else 0

    def test(self) -> bool:
        try:
            r = requests.get(
                f"{self.url}/api/v1/server/info",
                params={"password": self.pw},
                timeout=5
            )
            d = r.json().get("data", {})
            print(f"[✓] BlueBubbles: {d.get('computer_id','?')}")
            print(f"    Private API: {d.get('private_api')} | Helper: {d.get('helper_connected')}")
            return True
        except Exception as e:
            print(f"[✗] BlueBubbles test failed: {e}")
            return False


# ════════════════════════════════════════════════════════════════════════════════
# FRIDAY AGENT — multi-chat, per-chat watermarks, reply in same chat
# ════════════════════════════════════════════════════════════════════════════════
class FridayAgent:
    def __init__(self):
        self.brain      = FridayBrain()
        self.bb         = BlueBubblesInterface()
        self.memory     = self.brain.memory
        self.processing = False
        self.last_poll_time = 0
        self.processed_ids = set() # 🛡️ Deduplication shield (by rowid)
        self.processed_text = {}   # 🛡️ Deduplication shield (by text + window)
        # Per-chat watermarks: {poll_guid: last_rowid}
        self.watermarks: dict[str, int] = {c["poll_guid"]: 0 for c in MONITORED_CHATS}
        # Track recently-sent texts to avoid echo (text → timestamp)
        self.sent_texts: dict[str, float] = {}

    def _remember_sent(self, text: str):
        self.sent_texts[text] = time.time()
        cutoff = time.time() - 120
        self.sent_texts = {t: ts for t, ts in self.sent_texts.items() if ts > cutoff}

    def _is_our_message(self, text: str) -> bool:
        """Fuzzy deduplication: skip if we JUST sent this (ignoring whitespace)."""
        norm_text = "".join(text.split()).lower()
        if not norm_text: return False
        
        for sent, ts in self.sent_texts.items():
            if "".join(sent.split()).lower() == norm_text:
                if (time.time() - ts) < 300: # 5 minute safety window
                    return True
        return False

    def _bootstrap(self):
        """Load watermarks from DB. If empty, sync to current latest to avoid replay spam."""
        for chat in MONITORED_CHATS:
            pg = chat["poll_guid"]
            saved_wm = self.memory.get_watermark(pg)
            
            if saved_wm > 0:
                self.watermarks[pg] = saved_wm
                print(f"  [{chat['name']}] Restored watermark = ROWID {saved_wm}")
            else:
                # First time run or empty DB: jump to end
                msgs = self.bb.get_messages(limit=1, poll_guid=pg)
                wm = msgs[0].get("originalROWID", 0) if msgs else 0
                self.watermarks[pg] = wm
                self.memory.save_watermark(pg, wm)
                print(f"  [{chat['name']}] Synced new watermark = ROWID {wm}")
        print()

    def _poll_chat(self, chat: dict):
        """Poll one chat and reply in that same chat if new message found."""
        pg   = chat["poll_guid"]
        sg   = chat["send_guid"]
        name = chat["name"]
        wm   = self.watermarks.get(pg, 0)

        msgs = self.bb.get_messages(limit=10, poll_guid=pg)
        if not msgs:
            return

        new_msgs = sorted(
            [m for m in msgs if m.get("originalROWID", 0) > wm],
            key=lambda m: m.get("originalROWID", 0)
        )
        if not new_msgs:
            return

        for msg in new_msgs:
            rowid = msg.get("originalROWID", 0)
            text  = (msg.get("text") or "").strip()
            is_me = msg.get("isFromMe", False)
            
            # Update watermark persistently
            self.watermarks[pg] = max(wm, rowid)
            self.memory.save_watermark(pg, self.watermarks[pg])
            wm = self.watermarks[pg]

            if not text:
                continue
            
            # 🛡️ Echo Check: Skip if it's a message WE just sent
            if self._is_our_message(text):
                continue
            
            # 🛡️ Identity Check: Skip 'is_me' ONLY if it matches our own sent messages.
            # If is_me is true but it's NOT in sent_texts, it's the boss texting from his phone!
            if is_me and not self._is_our_message(text):
                # This is likely the boss! Proceed.
                pass
            elif is_me:
                continue

            # 🛡️ Global Deduplication (by ROWID)
            if rowid in self.processed_ids:
                continue
            
            # 🧪 Multi-channel Deduplication
            # Uses a 5-second window to prevent double-replies from iCloud + Gmail
            dedup_key = f"{text.lower()}_{int(time.time() / 5)}"
            if dedup_key in self.processed_text:
                continue
            self.processed_text[dedup_key] = True
            if len(self.processed_text) > 100: self.processed_text.clear()

            self.processed_ids.add(rowid)

            try:
                print(f"\n{'─'*55}")
                print(f"[📩 {name}]: {text}")

                if text.lower() in ["/reset", "reset memory", "clear memory"]:
                    reply = self.brain.reset()
                    label = "System"
                else:
                    reply = self.brain.think(text, chat_guid=sg)
                    # Check if it was a local response or AI
                    label = "Local" if "It's" in reply and "boss" in reply else f"🤖 {GEMINI_MODEL}"

                print(f"[{label} → {name}]: {reply}")
                self._remember_sent(reply)
                
                # 📢 Send reply ONLY to the current chat
                sent_ok = self.bb.send_to(reply, sg)
                if not sent_ok:
                    print(f"[!] Send failed for: {reply[:50]}")
            except Exception as e:
                print(f"[!] Error processing message {rowid}: {e}")

    def _poll_once(self):
        if self.processing:
            return
        self.processing = True
        try:
            for chat in MONITORED_CHATS:
                self._poll_chat(chat)
        finally:
            self.processing = False

    def _poll_swift_results(self):
        """
        Background thread — polls task_queue every 2s for COMPLETED tasks
        that the Swift app has finished executing, then sends the result to iPhone.
        Also acts as a system monitor (Battery).
        """
        print("[🔁 TaskQueue] Swift-result poller started")
        last_battery_alert = 0
        
        while True:
            try:
                # 1. Check Battery Proactively
                try:
                    exec_helper = MacExecutor()
                    battery_str = exec_helper._battery()
                    battery = 100
                    if "%" in battery_str:
                        # Extract number: "🔋 Battery: 28% (discharging)" -> 28
                        import re
                        m = re.search(r'(\d+)%', battery_str)
                        if m: battery = int(m.group(1))

                    # If battery < 20% and we haven't alerted in 1 hour
                    if battery < 20 and (time.time() - last_battery_alert) > 3600:
                        alert = "Boss, your battery is at {}%. I've dimmed the screen to save us some time. Find a charger! 🔋🔌".format(battery)
                        exec_helper._brightness("down")
                        self.bb.send_to(alert, MONITORED_CHATS[0]["send_guid"])
                        last_battery_alert = time.time()
                        print(f"[🔋 Monitor] Low battery alert sent: {battery}%")
                except Exception as ex:
                    print(f"[!] Battery monitor error: {ex}")

                # 2. Poll Result Queue
                completed = self.brain.memory.poll_completed_tasks()
                for task in completed:
                    result   = task.get("result") or "Task done, boss."
                    chat_guid = task.get("chat_guid") or MONITORED_CHATS[0]["send_guid"]
                    label    = task["task_type"].title()
                    reply    = f"✅ {label} result: {result}"
                    print(f"[📬 Swift→iPhone] Task #{task['id']}: {reply[:60]}")
                    self._remember_sent(reply)
                    
                    # 📢 Broadcast result to ALL chats
                    for target_chat in MONITORED_CHATS:
                        self.bb.send_to(reply, target_chat["send_guid"])
            except Exception as e:
                print(f"[!] Swift result poll error: {e}")
            time.sleep(2)

    def start_polling(self, port: int = 5001):
        if not FLASK_AVAILABLE:
            print("[✗] Install Flask: pip install flask")
            return

        app = Flask("FRIDAY")

        @app.route("/health", methods=["GET"])
        def health():
            return jsonify({
                "status":     "FRI_DAY online ✅",
                "model":      GEMINI_MODEL,
                "chats":      [c["name"] for c in MONITORED_CHATS],
                "watermarks": {k.split(";")[-1]: v for k, v in self.watermarks.items()},
            }), 200

        # Banner
        print("\n" + "═"*55)
        print("  🤖 FRI_DAY AGENT — ONLINE")
        print("═"*55)
        print(f"  Brain     : Gemini ({GEMINI_MODEL})")
        for c in MONITORED_CHATS:
            print(f"  Watching  : {c['name']} → {c['poll_guid']}")
        print(f"  Poll rate : every {POLL_INTERVAL}s")
        print("═"*55)
        print("  📱 Send a message in any watched chat — FRIDAY replies there.\n")

        if self.bb.test():
            self._bootstrap()

            # Start Swift result delivery thread
            threading.Thread(
                target=self._poll_swift_results, daemon=True, name="SwiftResults"
            ).start()

            # Send a "Pro" startup ping with system diagnostics
            last_ping = self.memory.get_fact("last_online_ping")
            now_ts = int(time.time())
            
            # 30-second cooldown for testing "Pro" pings
            if not last_ping or (now_ts - int(last_ping)) > 30:
                exec_h = MacExecutor()
                batt = exec_h._battery()
                
                # Check brain health
                brain_status = "🟢 Connected" if self.brain.client else "🔴 Brain Offline"
                
                startup = (
                    "═══════════════════════\n"
                    "  🤖 FRIDAY v2.5 PRO — ONLINE\n"
                    "═══════════════════════\n"
                    f"Diagnostics : 🛡️ Fully Operational\n"
                    f"Brain Node  : {brain_status}\n"
                    f"Power Node  : {batt}\n"
                    f"Protocol    : {GEMINI_MODEL.upper()}\n\n"
                    "Awaiting your instructions, Boss. ✨"
                )
                
                self._remember_sent(startup)
                self.bb.send_to(startup, MONITORED_CHATS[0]["send_guid"])
                self.memory.save_fact("last_online_ping", str(now_ts))
            
            # User can check status with /health or just text her.
            pass

        def poll_loop():
            while True:
                try:
                    self._poll_once()
                except Exception as e:
                    print(f"[!] Poll error: {e}")
                time.sleep(POLL_INTERVAL)

        threading.Thread(target=poll_loop, daemon=True).start()
        app.run(host="0.0.0.0", port=port, debug=False, use_reloader=False)

    def send_direct(self, text: str):
        self.bb.send_to(text, SEND_GUID)


# ════════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════
def main():
    parser = argparse.ArgumentParser(description="FRI_DAY – iMessage AI Agent")
    parser.add_argument("--listen",        action="store_true", help="Start agent (main mode)")
    parser.add_argument("--port",          type=int, default=5001)
    parser.add_argument("--send",          type=str,  help="Send a direct message")
    parser.add_argument("--transcription", type=str,  help="Voice → Gemini → iMessage")
    parser.add_argument("--test",          action="store_true", help="Test BlueBubbles connection")
    args = parser.parse_args()

    agent = FridayAgent()

    if args.test:
        agent.bb.test()
    elif args.send:
        agent.send_direct(args.send)
    elif args.transcription:
        print(f"[🎤 Voice]: {args.transcription}")
        reply = agent.brain.think(args.transcription)
        print(f"[🤖 FRIDAY]: {reply}")
        agent.send_direct(reply)
    elif args.listen:
        agent.start_polling(port=args.port)
    else:
        print("\n🤖 FRI_DAY – iMessage AI Agent")
        print(f"  Chat: {POLL_GUID}")
        print("  Run: python3 ProctorTrainer/Scripts/imessage_handler.py --listen")


if __name__ == "__main__":
    main()
