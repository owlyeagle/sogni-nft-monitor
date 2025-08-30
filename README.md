# SOGNI NFT Monitor Template

A robust, universal Bash script to monitor SOGNI NFT worker status and receive real-time notifications for status changes, job failures, and connectivity issues.  
**Optimized for ultra-fast GPUs (like RTX 5090), but works for any setup.**  
Supports [Pushover](https://pushover.net/), Telegram, and [ntfy.sh](https://ntfy.sh/) notifications.

---

## Features

- **Ultra-fast detection:** 3-minute job window, suitable for modern GPUs.
- **Configurable clock skew tolerance:** By default, handles up to 2 hours of time difference between your server and workers (adjustable via `TIME_SYNC_TOLERANCE`).
- **Color terminal output:** Clean and readable dashboard.
- **Notification options:** Pushover, Telegram, or ntfy.sh.
- **False positive resistance:** Reduces noisy alerts with layered detection logic.
- **Easy configuration:** Specify NFT IDs, notification method, and monitoring interval.
- **Extensible:** Add new notification methods or monitoring logic as needed.

---

## Requirements

- `bash`
- `curl`
- `jq`
- `timeout`
- `date`

**To install dependencies on Debian/Ubuntu:**
```bash
sudo apt-get update
sudo apt-get install -y jq curl coreutils
```

---

## Quick Start

1. **Clone this repository:**
   ```bash
   git clone https://github.com/owlyeagle/sogni-nft-monitor.git
   cd sogni-nft-monitor
   ```

2. **Configure the script:**
   - Open `sogni_nft_monitor_template.sh` in your editor.
   - Enter your NFT IDs in the `NFT_IDS` array.
   - Provide your notification credentials (Pushover, Telegram, or ntfy.sh).
   - Select your preferred notification method with `NOTIFICATION_SERVICE`.
   - (Optional) Adjust `JOB_COMPLETION_WINDOW` (default: 180s) and `CHECK_INTERVAL` (default: 60s).

3. **Make the script executable:**
   ```bash
   chmod +x sogni_nft_monitor_template.sh
   ```

4. **Run the script:**
   ```bash
   ./sogni_nft_monitor_template.sh
   ```

---

## Notification Setup

### Pushover
- Create an account at [pushover.net](https://pushover.net/).
- Create an application to get your API token.
- Configure:
  ```bash
  PUSHOVER_USER_KEY="your_pushover_user_key"
  PUSHOVER_API_TOKEN="your_pushover_api_token"
  NOTIFICATION_SERVICE="pushover"
  ```

### Telegram
- Create a bot with [@BotFather](https://t.me/BotFather).
- Get your bot token and your chat ID (see [userinfobot](https://t.me/userinfobot)).
- Configure:
  ```bash
  TELEGRAM_BOT_TOKEN="your_telegram_bot_token"
  TELEGRAM_CHAT_ID="your_telegram_chat_id"
  NOTIFICATION_SERVICE="telegram"
  ```

### ntfy.sh
- Pick a topic (e.g., `my-sogni-monitor`).
- Configure:
  ```bash
  NTFY_TOPIC="my-sogni-monitor"
  NOTIFICATION_SERVICE="ntfy"
  ```
- Subscribe to the topic via app or browser.

---

## Time Zone & Clock Synchronization

- The script uses a `TIME_SYNC_TOLERANCE` setting (default: 7200 seconds = 2 hours) to account for differences between your server and NFT worker clocks.
- **Adjustability:** If your environment requires a larger time difference, increase `TIME_SYNC_TOLERANCE` in the script configuration. Setting this value higher may decrease detection accuracy.
- Accurate clocks are recommended for both the monitoring server and NFT workers. Use NTP or similar tools for best results.
- The script is tested with Central European Summer Time (CEST, UTC+2), but works in any time zone as long as clocks are within the specified `TIME_SYNC_TOLERANCE`.
- If you see frequent `"sync?"` or `"now"` values in the time columns, check your system time settings or adjust `TIME_SYNC_TOLERANCE`.

---

## Running in the Background

- Consider using [tmux](https://github.com/tmux/tmux/wiki), [screen](https://www.gnu.org/software/screen/), or a [systemd service](https://www.freedesktop.org/software/systemd/man/systemd.service.html) for persistent, unattended monitoring.

---

## Customization

- **Add more NFTs:**  
  Append their IDs to the `NFT_IDS` array.
- **Change job window:**  
  Increase `JOB_COMPLETION_WINDOW` (seconds) for slower GPUs or higher latency.
- **Change check interval:**  
  Modify `CHECK_INTERVAL` (seconds) for faster or slower polling.
- **Add new notifications:**  
  Extend the notification functions to support Slack, Discord, email, etc.
- **Adapt detection logic:**  
  Adjust status detection logic for unique environments.

---

## Security & Best Practices

- Do not share your notification tokens or credentials. Keep all secrets private.
- The default polling interval (60s) is safe; avoid much faster polling to prevent API rate limiting.
- The script reports only on state changes, not the initial status.

---

## Troubleshooting

- **No notifications:**  
  Double-check credentials and try sending a test message.
- **Script exits at startup:**  
  Verify all dependencies are installed.
- **False offline alerts:**  
  Increase `JOB_COMPLETION_WINDOW` or check server/API/network stability.
- **Frequent “sync?” or negative times:**  
  Check your server and worker clocks.

---

## Contributing

Contributions and suggestions are welcome.  
Open an [issue](https://github.com/owlyeagle/sogni-nft-monitor/issues) or submit a pull request for improvements.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Credits

Developed by owlyeagle.  
Inspired by the SOGNI and GPU worker community.

---
