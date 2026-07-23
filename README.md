# Nexora Install

Installer for the Nexora executor.

Run this on a fresh Ubuntu 24 server (Hetzner CX22 or similar), as root:

```bash
curl -sSL https://raw.githubusercontent.com/Cryptobona/nexora-install/main/install.sh | sudo bash
```

You will be asked for six things, all of which Nexora sends you or you create
yourself:

1. Nexora license key
2. Nexora signal address (`nats://...`)
3. Bitunix API key
4. Bitunix API secret
5. Telegram bot token (optional)
6. Telegram chat id (optional)

The installer always starts in **paper mode** — no real orders. When you are
ready, run `nexora live`.

## After install

```
nexora status     how things are going
nexora logs       watch it work
nexora live       start real trading
nexora pause      stop trading
nexora update     install the newest version
nexora support    print a report to send to Nexora
```

Nexora never holds your funds. The Bitunix account, the API key and every
position are yours.
