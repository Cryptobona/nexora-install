# Nexora — Quick Start

Getting Nexora running takes about **20 minutes**, most of which is waiting.
You do not need to know anything about Linux. You will copy and paste a few
things. That's it.

Follow the steps in order. Don't skip step 3.

---

## What you need before you start

| | Where it comes from |
|---|---|
| A server (VPS) | You create it — step 1, about €5/month |
| Your Nexora **license key** | We send it to you after purchase |
| Your Nexora **signal address** | We send it to you after purchase |
| A **Bitunix** account with funds | You create it — step 3 |
| A **Telegram** bot | You create it — step 4, 2 minutes |

Keep all of these in one place before you begin — the installer asks for
them one after another and it's easier if you're not hunting.

**Never send your license key, signal address or Bitunix secret to anyone,
including anyone claiming to be Nexora support. We will never ask for them.**

---

## Step 1 — Create your server

Nexora runs on a small server that stays on 24/7. Your laptop can be off.

1. Sign up at [hetzner.com/cloud](https://www.hetzner.com/cloud)
2. Create a new project, then **Add Server**
3. Choose:
   - **Location:** Nuremberg or Falkenstein (Germany)
   - **Image:** Ubuntu 24.04
   - **Type:** CX22 (2 vCPU, 4 GB RAM) — about €5/month
   - **Everything else:** leave as it is
4. Click **Create & Buy now**

After a minute you'll see your server with an **IP address** like
`203.0.113.45`. Write it down.

> Any Ubuntu 22.04 or 24.04 server works — Hetzner is just the one we've
> tested and the cheapest we've found. Do not use a shared or "web hosting"
> plan; you need a real server you can log into.

**To open a terminal:** in the Hetzner panel, click your server, then the
**`>_` Console** button in the top right. A black window opens in your
browser. That's the terminal. You never have to install anything on your own
computer.

---

## Step 2 — Send us your server's IP address

Message us the IP address from step 1.

We add it to our signal server's firewall. **Until we confirm this, the
install will not complete** — your server won't be allowed to receive
signals. It usually takes us a few minutes.

Wait for our confirmation before moving on.

---

## Step 3 — Set up Bitunix (don't skip this)

Nexora trades **your** Bitunix account. We never hold, move or withdraw your
money. You can stop it or close positions yourself at any time.

### 3a. Create the account

Sign up with the link we sent you, complete verification, and deposit the
amount you intend to trade.

### 3b. Set position mode and leverage — **required**

Bitunix ships with settings Nexora cannot use. You must change two of them.

In the Bitunix **USDT-M Futures / BTCUSDT** trading screen:

1. Find **Position Mode** and set it to **One-way** *(the default is Hedge —
   Nexora will refuse to start on Hedge)*
2. Set **Margin Mode** to **Cross**
3. Set **Leverage** to **50x**

You cannot change position mode while you have an open position or open
order on BTCUSDT. Close everything first.

> Almost everyone gets stopped here, because Hedge is the default and it
> looks fine until the installer rejects it. Do it now and the rest is smooth.

### 3c. Create an API key

In Bitunix: **Account → API Management → Create API**

- **Permissions:** enable **Futures Trading**. Leave **Withdrawal** OFF.
  If withdrawal cannot be disabled on your account, stop and message us.
- **IP restriction:** enter your server's IP address from step 1. This means
  the key only works from your own server and is useless to anyone else.

Bitunix shows you the **API key** and the **secret key**.

**The secret is shown once and never again.** Copy both somewhere safe right
now. If you lose the secret, delete the key and make a new one.

---

## Step 4 — Create your Telegram bot

This is how Nexora tells you what it's doing. Two minutes.

1. In Telegram, search for **@BotFather** and open the chat
2. Send `/newbot`
3. Give it any name, then any username ending in `bot`
4. BotFather replies with a **token** that looks like
   `8123456789:AAF...`. Copy it.
5. Search for **@userinfobot**, open it, and press **Start**. It replies with
   your **Id** — a number like `481923756`. Copy that too.
6. Go back to your own bot and press **Start**, or send it any message.
   *(A bot cannot message you until you've messaged it first.)*

---

## Step 5 — Install Nexora

Open the console (step 1) and log in as `root` with the password Hetzner
emailed you. It will ask you to set a new password the first time.

Then paste this single line and press Enter:

```
curl -sSL https://raw.githubusercontent.com/Cryptobona/nexora-install/main/install.sh | sudo bash
```

The installer sets everything up and then asks **six short questions**:

1. Your Nexora **license key**
2. Your Nexora **signal address** (starts with `nats://`)
3. Your Bitunix **API key**
4. Your Bitunix **API secret**
5. Your Telegram **bot token**
6. Your Telegram **chat id**

**Your typing will not appear on screen.** That's deliberate — secrets stay
out of your terminal history and out of any screenshot. After each one you'll
see a masked confirmation with a character count, like
`abcd...wxyz (93 characters)`. Check the count matches what you copied — this
is what catches a half-copied paste.

Each answer is checked before you move on, so a wrong value is caught right
there rather than three steps later.

When it finishes you'll see a green checklist and:

```
✓ Nexora executor installed
✓ Mode: PAPER — no real trades
```

**Nexora starts in paper mode.** It follows every signal and records what it
would have done, but places no real orders. This is on purpose.

---

## Step 6 — Check it's alive

```
nexora status
```

You should see the service running, mode PAPER, and a heartbeat a few seconds
old. To watch it work:

```
nexora logs
```

Press **Ctrl+C** to stop watching. That stops the watching, not the bot.

---

## Step 7 — Go live when you're ready

Leave it in paper mode for at least a few days. Watch the Telegram messages.
Get used to what a normal day looks like before real money is involved.

When you're ready:

```
nexora live
```

You'll get a risk warning and have to type **YES** in capitals. Nothing else
is accepted. From that moment Nexora places real orders in your account
automatically, without asking you first.

To go back at any time:

```
nexora paper
```

---

## The commands you'll actually use

| Command | What it does |
|---|---|
| `nexora status` | How things are going right now |
| `nexora logs` | Watch it work live (Ctrl+C to stop watching) |
| `nexora pause` | Stop trading. Open positions keep their stop and target |
| `nexora resume` | Start trading again |
| `nexora live` | Switch to real trading (asks you to confirm) |
| `nexora paper` | Switch back to practice mode |
| `nexora update` | Install the newest version |
| `nexora support` | Print a report to send us |
| `nexora uninstall` | Remove Nexora from the server |

Run them in the same console window. All of them are safe to run at any time.

---

## If something goes wrong

Run:

```
nexora support
```

Copy the whole output and send it to us. It contains no passwords or keys —
just the version, the mode, and the last few log lines. It's safe to paste.

**A few things worth knowing:**

- **"Executor refuses to start — position mode"** → step 3b. You're on Hedge.
- **"Cannot connect to signal server"** → step 2. We haven't added your IP
  yet, or you've rebuilt the server and the IP changed. Message us the new one.
- **"Bitunix token invalid"** → the key or secret is wrong, or the API key's
  IP restriction doesn't match your server. Re-run the installer and choose
  **[R] Reconfigure**.
- **Nexora isn't trading** → check your Bitunix balance. With too little
  margin it will correctly refuse every signal rather than send a bad order.
- **You rebuilt or moved the server** → your IP changed. Tell us before you
  reinstall.

---

## Things to remember

- **Only trade money you can afford to lose entirely.** Leveraged BTC
  perpetuals are high risk. Paper results and past performance do not predict
  future results.
- Nexora is software. It is not investment advice, not a managed fund, and
  not a guarantee of profit.
- Your account, your keys, your positions. We never hold your funds and can
  never withdraw them.
- Don't trade the same Bitunix account manually while Nexora is running —
  it will get confused about what's open. Use a separate account if you want
  to trade by hand.
- Leave the server on. If you shut it down, Nexora stops, and open positions
  keep only the stop and target already sitting on Bitunix.

---

## Screenshots

<!-- TODO before first customer:
     1. Hetzner: server creation screen with CX22 + Ubuntu 24.04 selected
     2. Hetzner: the >_ Console button
     3. Bitunix: Position Mode selector showing One-way  ← the important one
     4. Bitunix: API creation, Futures Trading on / Withdrawal off / IP field
     5. BotFather: the /newbot reply with the token blurred
     6. Terminal: the finished green checklist
     Blur every real key. -->

*Screenshots for each step are being added — if any step above is unclear,
message us and we'll walk you through it on a call.*
