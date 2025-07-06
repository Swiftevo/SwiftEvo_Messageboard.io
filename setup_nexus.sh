#!/usr/bin/env bash
set -e

# ────────────────────────── Args ──────────────────────────
NODE_ID="$1"
[ -z "$NODE_ID" ] && { echo "Usage: $0 <node-id>"; exit 1; }

# ───── Step 1: 自动释放 apt 锁（如果存在）─────
echo "🔍 Checking for apt lock..."
# APT_LOCK="/var/lib/dpkg/lock-frontend"
# LOCK_PID=$(lsof -t "$APT_LOCK" 2>/dev/null)

if [ -n "$LOCK_PID" ]; then
  echo "⚠️  apt is locked by process $LOCK_PID. Killing..."
  sudo kill -9 "$LOCK_PID"
  sleep 1
  echo "🧹 Cleaning up apt locks..."
  sudo rm -f /var/lib/dpkg/lock
  sudo rm -f /var/lib/dpkg/lock-frontend
  sudo dpkg --configure -a
else
  echo "✅ No apt lock detected. Continuing..."
fi

# ─────────────────── Apt deps (auto-yes) ──────────────────
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
  build-essential pkg-config libssl-dev git-all protobuf-compiler curl tmux
echo "✅ Finshed Apt deps. Continuing..."


# ─────────────── Install Rust & load cargo env ─────────────
if ! command -v cargo >/dev/null 2>&1; then
  echo "🚀 Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
. "$HOME/.cargo/env"
echo "✅ cargo installed. Continuing..."

# ───────────────────── Build nexus-cli ─────────────────────
git clone https://github.com/nexus-xyz/nexus-cli.git
cd nexus-cli/clients/cli
cargo build --release
echo "✅ builded nexus-cli. Continuing..."

# ───────────────── Run in tmux (auto detach) ───────────────
cd target/release

#─────────────────────── Swap Check ───────────────────────
SWAP_EXISTS=$(swapon --show | wc -l)
if [ "$SWAP_EXISTS" -eq 0 ]; then
  echo "🔄 No swap found. Creating 8G swap..."
  sudo fallocate -l 8G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=8192
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo "✅ Swap created and activated."
else
  echo "✅ Swap already exists."
fi

# 如果 tmux 会话已存在就 kill 掉它
tmux has-session -t nexus 2>/dev/null && tmux kill-session -t nexus

echo "🧱 Launching nexus-network inside tmux session: nexus"
tmux new-session -d -s nexus "./nexus-network start --node-id $NODE_ID"
echo "✅ nexus-network started in tmux. Use: tmux attach -t nexus"

# 可选提示资源状态
ps aux | grep nex
