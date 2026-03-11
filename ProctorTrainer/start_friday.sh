#!/bin/bash
# ─────────────────────────────────────────────
#  FRIDAY iMessage AI Agent — Start Script
# ─────────────────────────────────────────────

# Go to the workspace root
cd "$(dirname "$0")/.." || exit 1

echo "-------------------------------------------------------"
echo "  🤖 Starting FRIDAY Agent..."
echo "  📱 Listening for iMessages from your iPhone"
echo "-------------------------------------------------------"

# Check if another instance of this script is already running
SCRIPT_PID=$$
OTHER_PIDS=$(pgrep -f "start_friday.sh" | grep -v "$SCRIPT_PID")
if [ -n "$OTHER_PIDS" ]; then
    echo "Found another FRIDAY monitor running. Cleaning up before starting..."
    echo "$OTHER_PIDS" | xargs kill -9 2>/dev/null
    sleep 1
fi

# Clean up any lingering python agents
lsof -ti :5001 | xargs kill -9 2>/dev/null

# Activate Python environment
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
elif [ -f "../../.venv/bin/activate" ]; then
    source ../../.venv/bin/activate
fi

# Load Environment Variables
if [ -f "ProctorTrainer/.env" ]; then
    source ProctorTrainer/.env
elif [ -f ".env" ]; then
    source .env
fi

echo "Starting FRIDAY with Heartbeat Monitor Active."

while true; do
    echo "[$(date +'%H:%M:%S')] Cleaning up port 5001..."
    lsof -ti :5001 | xargs kill -9 2>/dev/null
    # Kill any stale python handler processes that might not be on the port
    pgrep -f "imessage_handler.py" | xargs kill -9 2>/dev/null
    sleep 2
    
    echo "[$(date +'%H:%M:%S')] Starting FRIDAY Agent..."
    python3 ProctorTrainer/Scripts/imessage_handler.py --listen --port 5001
    
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
        echo "FRIDAY shut down gracefully."
        break
    else
        echo "FRIDAY crashed with code $EXIT_CODE. Restarting in 5 seconds..."
        sleep 5
    fi
done
