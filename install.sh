#!/usr/bin/env bash
set -e

INSTALL_DIR="/usr/local/bin"
TARGET_BIN="wake-cron"

echo "[*] Preparing wake-cron local compilation and setup..."

# Check environment compatibility
if [ "$(uname)" != "Darwin" ]; then
    echo "Error: wake-cron depends strictly on macOS framework components (pmset)."
    exit 1
fi

# Double check write capabilities for targets
if [ ! -d "$INSTALL_DIR" ]; then
    echo "[*] Target binary path $INSTALL_DIR missing. Instantiating folder..."
    sudo mkdir -p "$INSTALL_DIR"
fi

echo "[*] Deploying system binaries to $INSTALL_DIR..."
sudo cp wake-cron "$INSTALL_DIR/$TARGET_BIN"
sudo chmod +x "$INSTALL_DIR/$TARGET_BIN"

echo "========================================================================"
echo "[SUCCESS] wake-cron is officially installed!"
echo "          Type 'wake-cron' in a fresh terminal to begin."
echo "========================================================================"
