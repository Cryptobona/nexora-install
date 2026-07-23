#!/usr/bin/env bash
# Nexora executor installer (onboarding v2)
# Usage:
#   curl -sSL https://raw.githubusercontent.com/Cryptobona/nexora-install/main/install.sh | sudo bash
#
# Installs in PAPER mode. Going live is a separate, deliberate step: `nexora live`.

set -uo pipefail

INSTALL_DIR="/root/nexora-executor"
REPO_PATH="Cryptobona/nexora-executor"
HELPER_URL="https://raw.githubusercontent.com/Cryptobona/nexora-install/main/nexora"
TG_FILE="/root/.nexora_tg"
UNIT_NAME="nexora-executor"
MAX_TRIES=3

C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_B=$'\033[1m'; C_0=$'\033[0m'
step() { printf '\n%s>> %s%s\n' "$C_B" "$1" "$C_0"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$1"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$C_R" "$C_0" "$1"; }
die()  { printf '\n%s✗ %s%s\n\n' "$C_R" "$1" "$C_0"; exit 1; }

# Secrets are read hidden and only ever shown masked. Nothing typed at a prompt
# reaches the screen, so terminal output can be copied to support without
# leaking a key. (Three real credential leaks in this project came from echo.)
mask() {
  local v="${1:-}" n=${#1}
  if   [ "$n" -eq 0 ]; then printf '(nothing entered)'
  elif [ "$n" -le 8 ]; then printf '**** (%d characters)' "$n"
  else printf '%s...%s (%d characters)' "${v:0:4}" "${v: -4}" "$n"; fi
}
redact_url() {
  case "${1:-}" in
    *@*) printf 'nats://***@%s' "${1##*@}" ;;
    *)   printf '%s' "${1:-}" ;;
  esac
}

# -4 is required: dual-stack servers answer with IPv6, but the NATS firewall
# rule and the Bitunix IP restriction both need the IPv4 address.
MY_IP="$(curl -4 -s --max-time 8 https://ifconfig.me 2>/dev/null || echo 'unknown')"

# ---------------------------------------------------------------- A. preflight
step "Checking this server"

[ "$(id -u)" -eq 0 ] || die "Please run this with sudo."

if [ -r /etc/os-release ]; then
  . /etc/os-release
  if [ "${ID:-}" = "ubuntu" ]; then
    ok "Ubuntu ${VERSION_ID:-?} detected"
    case "${VERSION_ID:-}" in
      24.*) : ;;
      *) warn "Nexora is tested on Ubuntu 24. Continuing anyway." ;;
    esac
  elif [ "${ID_LIKE:-}" = "debian" ] || [ "${ID:-}" = "debian" ]; then
    warn "Not Ubuntu (${PRETTY_NAME:-unknown}). Continuing, but untested."
  else
    die "Nexora needs Ubuntu 24. This server is ${PRETTY_NAME:-unknown}."
  fi
else
  die "Cannot identify this operating system. Nexora needs Ubuntu 24."
fi

ok "Server IP: ${MY_IP}"

# HARD STOP: this installer is for CUSTOMER servers only. Running it on Nexora
# infrastructure reconfigures the live executor (.env overwrite, git remote
# repoint, a second systemd executor beside the tmux one). Learned the hard way,
# 23 Jul 2026.
NEXORA_HOST=0
NEXORA_WHY=""
[ -d /root/nexora-signal-engine ] && { NEXORA_HOST=1; NEXORA_WHY="the signal engine is installed here"; }
case "$(hostname)" in
  nexora-signal-*|nexora-control-*|nexora-monitor-*)
    NEXORA_HOST=1; NEXORA_WHY="the hostname is Nexora infrastructure" ;;
esac
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx nats; then
  NEXORA_HOST=1; NEXORA_WHY="the NATS broker runs here"
fi
if [ "$NEXORA_HOST" -eq 1 ]; then
  printf '\n%s✗ This is a Nexora server, not a customer server (%s).%s\n' "$C_R" "$NEXORA_WHY" "$C_0"
  printf '  Running the installer here would reconfigure the live executor.\n'
  printf '  Run it on the customer VPS instead.\n\n'
  printf '  hostname: %s   ip: %s\n\n' "$(hostname)" "$MY_IP"
  exit 1
fi

MODE_INSTALL="fresh"
if [ -f "${INSTALL_DIR}/.env" ]; then
  printf '\n  Nexora is already installed on this server.\n'
  printf '  [R] Reconfigure (re-enter your details)\n'
  printf '  [U] Update to the latest version, keep settings\n'
  printf '  [A] Abort\n\n'
  read -r -p "  Choose R, U or A: " CH </dev/tty
  case "${CH:-A}" in
    [Rr]) MODE_INSTALL="reconfigure" ;;
    [Uu]) MODE_INSTALL="update" ;;
    *) die "Aborted. Nothing was changed." ;;
  esac
fi

# ------------------------------------------------------- update-only fast path
if [ "$MODE_INSTALL" = "update" ]; then
  step "Updating Nexora"
  if [ -x "${INSTALL_DIR}/scripts/update.sh" ]; then
    "${INSTALL_DIR}/scripts/update.sh" || die "Update failed. Run 'nexora support' and send us the output."
  else
    ( cd "$INSTALL_DIR" && git pull --ff-only ) || die "Update failed. Run 'nexora support' and send us the output."
    systemctl restart "$UNIT_NAME"
  fi
  curl -sSL "$HELPER_URL" -o /usr/local/bin/nexora && chmod 755 /usr/local/bin/nexora
  ok "Updated. Run 'nexora status' to check."
  exit 0
fi

# ------------------------------------------------------------- B. system prep
step "Preparing the system (1-2 minutes)"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq git python3-pip python3-venv curl ca-certificates sqlite3 >/dev/null 2>&1 \
  || die "Could not install required system packages. Check this server has internet access."
ok "Required packages installed"

if [ "$(swapon --show --noheadings | wc -l)" -eq 0 ]; then
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ok "2GB swap enabled"
else
  ok "Swap already present"
fi

if [ -s /root/.ssh/authorized_keys ]; then
  if grep -qE '^\s*PasswordAuthentication\s+yes' /etc/ssh/sshd_config 2>/dev/null; then
    sed -i 's/^\s*PasswordAuthentication\s\+yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    ok "SSH hardened (key-only login)"
  else
    ok "SSH already hardened"
  fi
else
  warn "SSH password login left enabled (no SSH key found on this server)."
  warn "That is fine if you use the provider's web console. Add an SSH key later for extra safety."
fi

# ----------------------------------------------------------------- C. prompts
step "Your Nexora details"
printf '  Six short questions. Paste each value and press Enter.\n'

# 1. license key
LICENSE=""
for i in $(seq 1 $MAX_TRIES); do
  printf '\n  Paste your Nexora license key (hidden as you paste): '
  read -rs LICENSE </dev/tty; printf '\n'
  LICENSE="$(echo "$LICENSE" | tr -d '[:space:]')"
  printf '    got: %s\n' "$(mask "$LICENSE")"
  [ -n "$LICENSE" ] || { bad "Nothing entered."; continue; }
  if git ls-remote "https://x-access-token:${LICENSE}@github.com/${REPO_PATH}.git" HEAD >/dev/null 2>&1; then
    ok "License key accepted"
    break
  fi
  bad "That license key was not accepted. Check for missing characters and paste it again."
  [ "$i" -eq "$MAX_TRIES" ] && die "License key not accepted after ${MAX_TRIES} tries. Contact Nexora."
done

# 2. NATS signal address
NATS_URL=""
for i in $(seq 1 $MAX_TRIES); do
  printf '\n  Paste your Nexora signal address, starts with nats:// (hidden): '
  read -rs NATS_URL </dev/tty; printf '\n'
  NATS_URL="$(echo "$NATS_URL" | tr -d '[:space:]')"
  printf '    got: %s\n' "$(redact_url "$NATS_URL")"
  case "$NATS_URL" in
    nats://*) : ;;
    *) bad "That does not look like a signal address. It must start with nats://"; continue ;;
  esac
  NHOSTPORT="${NATS_URL##*@}"; NHOST="${NHOSTPORT%%:*}"; NPORT="${NHOSTPORT##*:}"
  [ "$NPORT" = "$NHOSTPORT" ] && NPORT=4222
  if timeout 8 bash -c "echo > /dev/tcp/${NHOST}/${NPORT}" 2>/dev/null; then
    ok "Signal server reachable"
    break
  fi
  bad "Can't reach the signal server."
  printf '     Most likely Nexora has not allowlisted this server yet.\n'
  printf '     Send Nexora this IP address: %s%s%s and re-run once they confirm.\n' "$C_B" "$MY_IP" "$C_0"
  [ "$i" -eq "$MAX_TRIES" ] && die "Signal server unreachable. Send Nexora your IP: ${MY_IP}"
done

# 3 + 4. Bitunix keys (validated after clone)
printf '\n  Paste your Bitunix API key (hidden): '
read -rs BITUNIX_KEY </dev/tty; printf '\n'
BITUNIX_KEY="$(echo "$BITUNIX_KEY" | tr -d '[:space:]')"
printf '    got: %s\n' "$(mask "$BITUNIX_KEY")"
printf '  Paste your Bitunix API secret (hidden): '
read -rs BITUNIX_SECRET </dev/tty; printf '\n'
BITUNIX_SECRET="$(echo "$BITUNIX_SECRET" | tr -d '[:space:]')"
printf '    got: %s\n' "$(mask "$BITUNIX_SECRET")"
[ -n "$BITUNIX_KEY" ] && [ -n "$BITUNIX_SECRET" ] || die "Both the Bitunix API key and secret are required."
# Both are 32 chars on Bitunix, so the character count cannot catch the same
# clipboard value pasted twice. Only an equality check can.
[ "$BITUNIX_KEY" != "$BITUNIX_SECRET" ] || die "The API key and the API secret are the same value. You have pasted the same thing twice. Copy them separately from Bitunix and run this again."

# 5 + 6. Telegram (optional)
printf '\n  Telegram alerts let you see every trade on your phone. Strongly recommended.\n'
printf '  Telegram bot token, press Enter to skip (hidden): '
read -rs TG_TOKEN </dev/tty; printf '\n'
TG_TOKEN="$(echo "${TG_TOKEN:-}" | tr -d '[:space:]')"
[ -n "$TG_TOKEN" ] && printf '    got: %s\n' "$(mask "$TG_TOKEN")"
TG_CHAT=""
if [ -n "$TG_TOKEN" ]; then
  read -r -p '  Telegram chat id: ' TG_CHAT </dev/tty
  TG_CHAT="$(echo "${TG_CHAT:-}" | tr -d '[:space:]')"
fi

# ----------------------------------------------------------------- D. install
step "Installing Nexora"

if [ -d "${INSTALL_DIR}/.git" ]; then
  ( cd "$INSTALL_DIR" \
    && git remote set-url origin "https://x-access-token:${LICENSE}@github.com/${REPO_PATH}.git" \
    && git fetch -q origin \
    && BR="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)" \
    && git reset -q --hard "$BR" ) \
    || die "Could not refresh the Nexora software. Contact Nexora."
  ok "Nexora software refreshed"
else
  rm -rf "$INSTALL_DIR"
  git clone -q "https://x-access-token:${LICENSE}@github.com/${REPO_PATH}.git" "$INSTALL_DIR" \
    || die "Could not download the Nexora software. Contact Nexora."
  ok "Nexora software downloaded"
fi
VERSION="$(cd "$INSTALL_DIR" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"

pip3 install -q -r "${INSTALL_DIR}/requirements.txt" --break-system-packages >/dev/null 2>&1 \
  || pip3 install -q -r "${INSTALL_DIR}/requirements.txt" >/dev/null 2>&1 \
  || die "Could not install Python dependencies. Run 'nexora support' and send us the output."
ok "Dependencies installed"

mkdir -p "${INSTALL_DIR}/data" "${INSTALL_DIR}/logs"

ENV_FILE="${INSTALL_DIR}/.env"
# Never destroy an existing config without a copy — a reconfigure that goes
# wrong must be recoverable.
[ -f "$ENV_FILE" ] && cp -a "$ENV_FILE" "${ENV_FILE}.bak.$(date -u +%Y%m%d-%H%M%S)" \
  && ok "Previous settings backed up"
LOG_FILE="${INSTALL_DIR}/logs/executor.log"
umask 077
# Only vars WITHOUT a safe code default are written here. BITUNIX_BASE_URL,
# NATS_SUBJECT, EXECUTOR_DB_PATH and EXECUTOR_HEARTBEAT all default correctly in
# executor/config.py — leaving them unset means a code update fixes every client
# at once instead of needing a per-client .env edit.
# EXECUTOR_MODE is written explicitly because config.py still defaults to "live".
{
  printf 'BITUNIX_API_KEY=%s\n'    "$BITUNIX_KEY"
  printf 'BITUNIX_API_SECRET=%s\n' "$BITUNIX_SECRET"
  printf 'BITUNIX_SYMBOL=%s\n'     "BTCUSDT"
  printf 'NATS_URL=%s\n'           "$NATS_URL"
  printf 'EXECUTOR_MODE=%s\n'      "paper"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
umask 022
ok "Settings saved (paper mode)"

# ---- Bitunix credential check (uses the repo's own client)
BITUNIX_OK=0
BITUNIX_MSG=""
BITUNIX_RESULT="$(
  cd "$INSTALL_DIR" && BK="$BITUNIX_KEY" BS="$BITUNIX_SECRET" python3 - <<'PY' 2>/dev/null
# Auth proof only. One signed private call: if this succeeds the key is valid,
# the secret matches, the IP lock allows this server, and futures access is on.
import asyncio, os, sys
sys.path.insert(0, '.')
from bitunix.client import BitunixClient

async def go():
    c = BitunixClient(os.environ["BK"], os.environ["BS"])
    await c.start()
    try:
        r = await c.get_pending_positions(symbol="BTCUSDT")
        if not isinstance(r, dict):
            print("FAIL|unexpected response from Bitunix"); return
        code = str(r.get("code", "0"))
        if code not in ("0", "00000", "None"):
            print("FAIL|%s" % (r.get("msg") or ("code " + code))); return
        print("OK|")
    finally:
        await c.close()

try:
    asyncio.run(go())
except Exception as e:
    print("FAIL|%s" % e)
PY
)"
case "$BITUNIX_RESULT" in
  OK\|*) BITUNIX_OK=1 ;;
  FAIL\|*) BITUNIX_MSG="${BITUNIX_RESULT#FAIL|}" ;;
  *) BITUNIX_MSG="no response from the Bitunix check" ;;
esac

if [ "$BITUNIX_OK" -eq 1 ]; then
  ok "Bitunix connected — key accepted, futures access verified"
else
  bad "Bitunix rejected the connection: ${BITUNIX_MSG}"
  case "$BITUNIX_MSG" in
    *[Ii][Pp]*) printf '     Your Bitunix key is restricted to a different IP address.\n     Add this server IP in Bitunix > API Management: %s%s%s\n' "$C_B" "$MY_IP" "$C_0" ;;
    *) printf '     Re-check that you copied BOTH the key and the secret in full,\n     and that the key has Futures Trading permission enabled.\n' ;;
  esac
fi

# ---- NATS auth check (nats-py is installed now)
NATS_OK=0
NATS_MSG="$(
  cd "$INSTALL_DIR" && NU="$NATS_URL" python3 - <<'PY' 2>/dev/null
import asyncio, os
import nats
async def go():
    nc = await nats.connect(os.environ["NU"], connect_timeout=8, max_reconnect_attempts=1)
    await nc.close()
    print("OK|")
try:
    asyncio.run(go())
except Exception as e:
    print("FAIL|%s" % e)
PY
)"
case "$NATS_MSG" in
  OK\|*) NATS_OK=1; ok "Nexora signal feed connected (authenticated)" ;;
  *) bad "Signal credentials rejected — contact Nexora."
     printf '     (network reach already passed, so this is an account issue, not a firewall one)\n' ;;
esac

# ---- Telegram
TG_OK=0
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
  umask 077
  { printf 'TG_TOKEN=%s\n' "$TG_TOKEN"; printf 'TG_CHAT=%s\n' "$TG_CHAT"; } > "$TG_FILE"
  chmod 600 "$TG_FILE"
  umask 022
  if curl -s --max-time 10 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
       -d chat_id="${TG_CHAT}" -d text="Nexora installed on this server ✓" | grep -q '"ok":true'; then
    TG_OK=1; ok "Telegram alerts working — check your phone"
  else
    bad "Telegram did not accept the token/chat id. Alerts are off; everything else still works."
  fi
else
  warn "Telegram alerts skipped. You can add them later — ask Nexora how."
fi

# ----------------------------------------------------------------- E. service
step "Starting Nexora"

UNIT_SRC="${INSTALL_DIR}/scripts/${UNIT_NAME}.service"
[ -f "$UNIT_SRC" ] || die "Service file missing from the Nexora software. Contact Nexora."
cp "$UNIT_SRC" "/etc/systemd/system/${UNIT_NAME}.service"
systemctl daemon-reload

# The unit appends to logs/executor.log (not journald). Mark where this run
# starts so a re-install can't match an "Executor ready" from a previous run.
touch "$LOG_FILE"
LOG_OFFSET="$(wc -l < "$LOG_FILE")"

# Log rotation: the unit appends forever with no rotation of its own.
cat > /etc/logrotate.d/nexora <<EOF
${LOG_FILE} {
    daily
    rotate 14
    compress
    missingok
    notifempty
    copytruncate
}
EOF

if [ "$BITUNIX_OK" -eq 1 ]; then
  systemctl enable --now "$UNIT_NAME" >/dev/null 2>&1
  sleep 10
else
  # Bitunix rejected these credentials. Starting anyway leaves an enabled unit
  # crash-looping on Restart=always, and (in paper) a bot that looks healthy for
  # days and only fails when the customer switches to live.
  systemctl disable --now "$UNIT_NAME" >/dev/null 2>&1 || true
  bad "Nexora was NOT started, because Bitunix rejected these credentials."
  printf "     Nothing is running and nothing will trade. Fix the key, then\n     run this installer again and choose [R].\n"
fi

RUN_OK=0
ACCT_OK=1
NEW_LOG=""
if systemctl is-active --quiet "$UNIT_NAME"; then
  NEW_LOG="$(tail -n "+$((LOG_OFFSET + 1))" "$LOG_FILE" 2>/dev/null || true)"
  if printf '%s\n' "$NEW_LOG" | grep -q "Executor ready"; then
    RUN_OK=1; ok "Executor running (version ${VERSION})"
  else
    RUN_OK=1; warn "Executor started but has not reported ready yet — check 'nexora status' in a minute"
  fi
else
  bad "Executor did not start"
  tail -n 5 "$LOG_FILE" 2>/dev/null | sed 's/^/     /'
fi

# The executor verifies the Bitunix account settings itself at boot. Surface
# that here: ONE_WAY is not optional — the executor is written for it, and a
# HEDGE account (Bitunix's default) would mismanage real positions.
#
# THREE states, never two. If the executor never reached Bitunix it emits no
# mismatch warning, and treating that silence as "verified" would report a
# health this install does not have. Absence of a warning is not a pass.
ACCT_STATE="unknown"
POS_LINE="$(printf '%s\n' "$NEW_LOG" | grep -m1 'POSITION MODE MISMATCH' | sed 's/.*MISMATCH | *//')"
LEV_LINE="$(printf '%s\n' "$NEW_LOG" | grep -m1 'LEVERAGE MISMATCH'      | sed 's/.*MISMATCH | *//')"
if printf '%s\n' "$NEW_LOG" | grep -q 'Bitunix connected'; then
  if [ -n "$POS_LINE" ] || [ -n "$LEV_LINE" ]; then ACCT_STATE="bad"; else ACCT_STATE="ok"; fi
fi

case "$ACCT_STATE" in
  ok)  ok "Bitunix account settings verified (ONE_WAY, 50x CROSS)" ;;
  bad)
    ACCT_OK=0
    bad "Your Bitunix account settings need changing"
    if [ -n "$POS_LINE" ]; then
      printf '     %s\n' "$POS_LINE"
      printf '     Fix in Bitunix: Futures screen > settings > Position Mode > One-way\n'
    fi
    if [ -n "$LEV_LINE" ]; then
      printf '     %s\n' "$LEV_LINE"
      printf '     Fix in Bitunix: open BTCUSDT > leverage button > 50x, margin mode Cross\n'
    fi
    printf '     Change both, then run this installer again and choose [R].\n'
    ;;
  *)   warn "Bitunix account settings NOT checked — the executor could not reach Bitunix" ;;
esac

curl -sSL "$HELPER_URL" -o /usr/local/bin/nexora 2>/dev/null && chmod 755 /usr/local/bin/nexora \
  && ok "'nexora' command installed" \
  || warn "Could not install the 'nexora' helper command — contact Nexora"

# ------------------------------------------------------------------ F. output
FAILED=0
printf '\n%s──────────────────────────────────────────────────────────%s\n' "$C_B" "$C_0"
printf '%s  NEXORA INSTALL%s\n\n' "$C_B" "$C_0"
ok "System prepared (swap, security)"
ok "Nexora executor installed (version ${VERSION})"
if [ "$BITUNIX_OK" -eq 1 ]; then ok "Bitunix connected — key accepted, futures access verified"
else bad "Bitunix NOT connected"; FAILED=1; fi
if [ "$NATS_OK" -eq 1 ]; then ok "Nexora signal feed connected (authenticated)"
else bad "Signal feed NOT connected"; FAILED=1; fi
if [ "$TG_OK" -eq 1 ]; then ok "Telegram alerts working"
else warn "Telegram alerts not set up"; fi
case "$ACCT_STATE" in
  ok)  ok "Bitunix account settings correct (ONE_WAY, 50x CROSS)" ;;
  bad) bad "Bitunix account settings MUST be changed (see above)"; FAILED=1 ;;
  *)   warn "Bitunix account settings unchecked (fix the Bitunix connection first)" ;;
esac
if [ "$RUN_OK" -eq 1 ]; then ok "Running in PAPER mode — no real trades yet"
else bad "Executor NOT running"; FAILED=1; fi
printf '%s──────────────────────────────────────────────────────────%s\n' "$C_B" "$C_0"

if [ "$FAILED" -eq 0 ]; then
cat <<EOM

  NEXT: let it run about 24 hours. You will get [PAPER] Telegram messages
  when signals fire — that proves everything works, with zero risk.

  Useful commands:
    nexora status     how things are going
    nexora logs       watch it work
    nexora live       start real trading (asks you to confirm the risks)

EOM
  exit 0
else
cat <<EOM

  Some checks failed (marked ✗ above). Fix what is listed, then run this
  installer again — re-running is safe.

  If you are stuck, run:   nexora support
  and send Nexora the output.

EOM
  exit 1
fi
