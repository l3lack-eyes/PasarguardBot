.PHONY: help clean install-deps install-service patch-service-env start-service stop-service restart-service status-service run logs-service logs-follow logs-app logs-all remove-service setup-service enable-service disable-service

# Service configuration
SERVICE_NAME = PasarguardBot
SERVICE_FILE = /etc/systemd/system/$(SERVICE_NAME).service
CURRENT_DIR = $(shell pwd)
UV_PATH = $(shell which uv)
# journalctl line count for logs-service (override: make logs-service LOG_LINES=1000)
LOG_LINES ?= 500
# Terminal width for Rich (systemd has no TTY → defaults to ~80 and wraps long lines)
COLUMNS ?= 500
# Merge Rich soft-wrap continuations when reading journal (leading whitespace only)
UNWRAP_AWK = awk 'BEGIN{b=""} /^[[:space:]]{10,}/ && !/(INFO|WARNING|ERROR|DEBUG|CRITICAL)/ {sub(/^[[:space:]]+/," ");b=b$$0;next} {if(b!=""){print b;b=""};b=$$0} END{if(b!="")print b}'

# Default target - show help
help:
	@echo "🚀 PasarguardBot Makefile Commands:"
	@echo ""
	@echo "🧪 Testing:"
	@echo "  make test              - Run pytest locally (no bot / DB required)"
	@echo "📦 Setup & Installation:"
	@echo "  make setup-service     - Complete setup (install deps + service + start)"
	@echo "  make install-deps      - Install dependencies with uv"
	@echo "  make install-service   - Create systemd service"
	@echo "  make enable-service    - Enable auto-start on boot"
	@echo "  make disable-service    - Disable auto-start on boot"
	@echo ""
	@echo "🔧 Service Management:"
	@echo "  make start-service     - Start the bot service"
	@echo "  make stop-service      - Stop the bot service"
	@echo "  make restart-service   - Restart the bot service"
	@echo "  make status-service    - Check service status"
	@echo ""
	@echo "📋 Logs & Monitoring:"
	@echo "  make run               - Foreground (uv run) — same as direct run, colored"
	@echo "  make logs-service      - Journal, last $(LOG_LINES) lines (LOG_LINES=N to override)"
	@echo "  make logs-follow       - Journal live stream"
	@echo "  make logs-app          - Tail ./logs/app.log (LOG_LINES=N for initial lines)"
	@echo "  make logs-all          - Full journal (no line limit)"
	@echo "  make patch-service-env - Apply COLUMNS to running systemd unit + restart"
	@echo ""
	@echo "🧹 Maintenance:"
	@echo "  make clean             - Clean Python cache files"
	@echo "  make remove-service    - Remove service completely"
	@echo ""
	@echo "💡 Quick Start:"
	@echo "  1. make setup-service"
	@echo "  2. Edit $(SERVICE_FILE) (add your env vars)"
	@echo "  3. make restart-service"
	@echo ""
	@echo "📝 Environment Variables to add:"
	@echo "  Environment=BOT_TOKEN=your_bot_token_here"
	@echo "  Environment=DB_URL=your_database_url_here"

# Default target
.DEFAULT_GOAL := help

# Cross-platform clean target (Linux / Windows)
clean:
	@echo "Cleaning Python cache files..."
ifeq ($(OS),Windows_NT)
	@echo "Detected Windows OS"
	@powershell -Command "Get-ChildItem -Recurse -Directory -Filter __pycache__ | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue"
	@powershell -Command "Get-ChildItem -Recurse -Include *.pyc,*.pyo | Remove-Item -Force -ErrorAction SilentlyContinue"
else
	@echo "Detected Unix-like OS"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@find . -name "*.pyo" -delete 2>/dev/null || true
endif
	@echo "Cleaning done!"

# Install uv if not installed
install-uv:
	@echo "Installing uv..."
	@if ! command -v uv >/dev/null 2>&1; then \
		curl -LsSf https://astral.sh/uv/install.sh | sh; \
		export PATH="$$HOME/.cargo/bin:$$PATH"; \
	fi
	@echo "uv installation completed!"

# Install dependencies
install-deps: install-uv
	@echo "Installing dependencies with uv..."
	@uv sync
	@echo "Dependencies installed successfully!"

# Create systemd service
install-service:
	@echo "Creating systemd service for $(SERVICE_NAME)..."
	@echo "[Unit]" > /tmp/$(SERVICE_NAME).service
	@echo "Description=$(SERVICE_NAME) Telegram Bot" >> /tmp/$(SERVICE_NAME).service
	@echo "After=network.target" >> /tmp/$(SERVICE_NAME).service
	@echo "Wants=network.target" >> /tmp/$(SERVICE_NAME).service
	@echo "" >> /tmp/$(SERVICE_NAME).service
	@echo "[Service]" >> /tmp/$(SERVICE_NAME).service
	@echo "Type=simple" >> /tmp/$(SERVICE_NAME).service
	@echo "User=root" >> /tmp/$(SERVICE_NAME).service
	@echo "WorkingDirectory=$(CURRENT_DIR)" >> /tmp/$(SERVICE_NAME).service
	@echo "ExecStart=$(UV_PATH) run main.py" >> /tmp/$(SERVICE_NAME).service
	@echo "Restart=always" >> /tmp/$(SERVICE_NAME).service
	@echo "RestartSec=10" >> /tmp/$(SERVICE_NAME).service
	@echo "StandardOutput=journal" >> /tmp/$(SERVICE_NAME).service
	@echo "StandardError=journal" >> /tmp/$(SERVICE_NAME).service
	@echo "SyslogIdentifier=$(SERVICE_NAME)" >> /tmp/$(SERVICE_NAME).service
	@echo "Environment=PYTHONUNBUFFERED=1" >> /tmp/$(SERVICE_NAME).service
	@echo "Environment=COLUMNS=$(COLUMNS)" >> /tmp/$(SERVICE_NAME).service
	@echo "" >> /tmp/$(SERVICE_NAME).service
	@echo "# Environment variables (uncomment and add your values)" >> /tmp/$(SERVICE_NAME).service
	@echo "# Environment=BOT_TOKEN=your_bot_token_here" >> /tmp/$(SERVICE_NAME).service
	@echo "# Environment=DB_URL=your_database_url_here" >> /tmp/$(SERVICE_NAME).service
	@echo "" >> /tmp/$(SERVICE_NAME).service
	@echo "[Install]" >> /tmp/$(SERVICE_NAME).service
	@echo "WantedBy=multi-user.target" >> /tmp/$(SERVICE_NAME).service
	@sudo mv /tmp/$(SERVICE_NAME).service $(SERVICE_FILE)
	@echo "Service file created at $(SERVICE_FILE)"
	@sudo systemctl daemon-reload
	@echo "Service installed successfully!"

# Enable service for auto-start
enable-service:
	@echo "Enabling $(SERVICE_NAME) service..."
	@sudo systemctl enable $(SERVICE_NAME)
	@echo "Service enabled for auto-start on boot"

# Disable service for auto-start
disable-service:
	@echo "disabling $(SERVICE_NAME) service..."
	@sudo systemctl disable $(SERVICE_NAME)
	@echo "Service disabled for auto-start on boot"

# Start service
start-service:
	@echo "Starting $(SERVICE_NAME) service..."
	@sudo systemctl start $(SERVICE_NAME)
	@echo "Service started successfully!"

# Stop service
stop-service:
	@echo "Stopping $(SERVICE_NAME) service..."
	@sudo systemctl stop $(SERVICE_NAME)
	@echo "Service stopped successfully!"

# Restart service
restart-service:
	@echo "Restarting $(SERVICE_NAME) service..."
	@sudo systemctl restart $(SERVICE_NAME)
	@echo "Service restarted successfully!"

# Check service status
status-service:
	@echo "Checking $(SERVICE_NAME) service status..."
	@sudo systemctl status $(SERVICE_NAME)

# Foreground run — identical to: uv run main.py (TTY → app logger colors work)
run:
	@COLUMNS=$(COLUMNS) PYTHONUNBUFFERED=1 uv run main.py

# Local test suite — no Telethon session or production DB needed
test:
	@uv run pytest -v

# Journal: raw stdout/stderr, unwrap Rich line breaks, last LOG_LINES lines
logs-service:
	@echo "Journal logs for $(SERVICE_NAME) (last $(LOG_LINES) lines, LOG_LINES=N to override)..."
	@sudo journalctl -u $(SERVICE_NAME) -n $(LOG_LINES) --no-pager -o cat | $(UNWRAP_AWK)

# Journal live stream (unwrap continuations)
logs-follow:
	@echo "Following $(SERVICE_NAME) (Ctrl+C to exit). Colored/full width: make run"
	@sudo journalctl -u $(SERVICE_NAME) -f -o cat | $(UNWRAP_AWK)

# Re-apply service env (COLUMNS etc.) without full reinstall — run after editing Makefile
patch-service-env:
	@sudo mkdir -p /etc/systemd/system/$(SERVICE_NAME).service.d
	@echo '[Service]' | sudo tee /etc/systemd/system/$(SERVICE_NAME).service.d/override.conf >/dev/null
	@echo 'Environment=PYTHONUNBUFFERED=1' | sudo tee -a /etc/systemd/system/$(SERVICE_NAME).service.d/override.conf >/dev/null
	@echo 'Environment=COLUMNS=$(COLUMNS)' | sudo tee -a /etc/systemd/system/$(SERVICE_NAME).service.d/override.conf >/dev/null
	@sudo systemctl daemon-reload
	@echo "Override written. Run: make restart-service"

# File on disk written by the app (not journal)
logs-app:
	@test -f logs/app.log || (echo "logs/app.log not found." && exit 1)
	@tail -n $(LOG_LINES) -f logs/app.log

# Full journal since service was installed
logs-all:
	@echo "Full journal for $(SERVICE_NAME)..."
	@sudo journalctl -u $(SERVICE_NAME) --no-pager -o cat | $(UNWRAP_AWK)

# Remove service completely
remove-service:
	@echo "Removing $(SERVICE_NAME) service..."
	@sudo systemctl stop $(SERVICE_NAME) 2>/dev/null || true
	@sudo systemctl disable $(SERVICE_NAME) 2>/dev/null || true
	@sudo rm -f $(SERVICE_FILE)
	@sudo systemctl daemon-reload
	@echo "Service removed successfully!"

# Complete setup: install deps, create service, enable, and start
setup-service: install-deps install-service enable-service start-service
	@echo ""
	@echo "🎉 Setup complete! Bot should be running now."
	@echo ""
	@echo "📝 Next steps:"
	@echo "1. Edit $(SERVICE_FILE) and add your environment variables"
	@echo "2. Run 'make restart-service' to apply changes"
	@echo ""
	@echo "🔧 Useful commands:"
	@echo "- make status-service  # Check status"
	@echo "- make logs-service     # View logs"
	@echo "- make restart-service  # Restart bot"