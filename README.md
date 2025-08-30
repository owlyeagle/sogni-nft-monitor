# SOGNI NFT Monitor Template

A robust, universal Bash script to monitor SOGNI NFT worker status and receive real-time notifications for status changes, job failures, and connectivity issues.  
**Optimized for ultra-fast GPUs (like RTX 5090), but works for any setup.**  
Supports [Pushover](https://pushover.net/), Telegram, and [ntfy.sh](https://ntfy.sh/) notifications.

---

## 🚀 Features

- **Ultra-fast detection:** 3-minute job window, perfect for modern GPUs
- **Time zone & clock-skew tolerant:** Handles up to 2 hours of clock difference
- **Color terminal output:** Clean and readable dashboard
- **Notification options:** Pushover, Telegram, or ntfy.sh
- **False positive resistant:** Avoids noisy alerts with layered detection logic
- **Easy to configure:** NFT IDs, notification method, and monitoring interval
- **Extensible:** Add new notification methods or monitoring logic easily

---

## 🛠️ Requirements

- `bash`
- `curl`
- `jq`
- `timeout`
- `date`

**Install dependencies (Debian/Ubuntu):**
```bash
sudo apt-get update
sudo apt-get install -y jq curl coreutils
```

---

## ⚡ Quick Start

1. **Clone this repository:**
   ```bash
   git clone https://github.com/owlyeagle/sogni-nft-monitor.git
   cd sogni-nft-monitor
   ```

2. **Configure the script:**
   - Open `sogni_nft_monitor_template.sh` in your editor.
   - Fill in your NFT IDs in the `NFT_IDS` array.
   - Set up your notification credentials (Pushover, Telegram, or ntfy.sh).
   - Choose your preferred notification method (`NOTIFICATION_SERVICE`).
   - (Optional) Adjust `JOB_COMPLETION_WINDOW` (default: 180s = 3 minutes) and `CHECK_INTERVAL` (default: 60s).

3. **Make the script executable:**
   ```bash
   chmod +x sogni_nft_monitor_template.sh
   ```

4. **Run the script:**
   ```bash
   ./sogni_nft_monitor_template.sh
   ```

---

## 🔔 Notification Setup

### Pushover
- Create an account at [pushover.net](https://pushover.net/).
- Create an application to get your API token.
- Fill in:
  ```bash
  PUSHOVER_USER_KEY="your_pushover_user_key"
  PUSHOVER_API_TOKEN="your_pushover_api_token"
  NOTIFICATION_SERVICE="pushover"
  ```

### Telegram
- Create a bot with [@BotFather](https://t.me/BotFather).
- Get your bot token and your chat ID (see [userinfobot](https://t.me/userinfobot)).
- Fill in:
  ```bash
  TELEGRAM_BOT_TOKEN="your_telegram_bot_token"
  TELEGRAM_CHAT_ID="your_telegram_chat_id"
  NOTIFICATION_SERVICE="telegram"
  ```

### ntfy.sh
- Pick a topic (e.g., `my-sogni-monitor`).
- Fill in:
  ```bash
  NTFY_TOPIC="my-sogni-monitor"
  NOTIFICATION_SERVICE="ntfy"
  ```
- Subscribe to the topic via app or browser.

---

## ⏰ Time Zone & Clock Sync Notes

- The script tolerates up to **2 hours** of time difference between your server and the SOGNI API (default: `TIME_SYNC_TOLERANCE=7200`).
- Accurate clocks are **recommended** for both your monitoring server and NFT workers.  
  Use NTP or similar tools for best reliability.
- The script is tested with Central European Summer Time (CEST, UTC+2), but works in any time zone as long as clocks are not off by more than 2 hours.
- If you see frequent `"sync?"` or `"now"` values in the time columns, check your system time settings or increase `TIME_SYNC_TOLERANCE`.

---

## 🖥️ Running in Background

- Use [tmux](https://github.com/tmux/tmux/wiki), [screen](https://www.gnu.org/software/screen/), or a [systemd service](https://www.freedesktop.org/software/systemd/man/systemd.service.html) for 24/7 monitoring.

---

## 🧩 Customization Tips

- **Add more NFTs:**  
  Just append their IDs to the `NFT_IDS` array.
- **Change job window:**  
  For slower GPUs or higher latency, increase `JOB_COMPLETION_WINDOW` (seconds).
- **Change check interval:**  
  Modify `CHECK_INTERVAL` (seconds) for faster or slower polling.
- **Add new notifications:**  
  Extend the notification functions to support Slack, Discord, email, etc.
- **Tune for your environment:**  
  Adjust status detection logic if your setup is unique.

---

## 🛡️ Security & Best Practices

- **Do not share your notification tokens/credentials.**  
  Keep your script and keys private.
- **API rate limits:**  
  Default interval (60s) is safe; avoid much faster polling to prevent bans.
- **First-run:**  
  The script only alerts on state changes, not the initial status.

---

## 🩺 Troubleshooting

- **No notifications?**  
  Double-check credentials and try sending a test message.
- **Script exits at startup?**  
  Verify all dependencies are installed.
- **False offline alerts?**  
  Increase `JOB_COMPLETION_WINDOW` or check server/API/network stability.
- **Frequent “sync?” or negative times?**  
  Check your server and worker clocks.

---

## 🤝 Contributing

Pull requests, issues, and suggestions are welcome!  
Open an [issue](https://github.com/owlyeagle/sogni-nft-monitor/issues) or submit a PR for improvements.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.

---

## 🙏 Credits

Developed by owlyeagle.  
Inspired by the SOGNI and GPU worker community.

---
