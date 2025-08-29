#!/bin/bash

################################################################################
# SOGNI NFT Monitor - RTX 5090 Optimized (3-Minute Job Window, Clock-Skew Safe)
#   - Monitors a set of NFT workers for recent activity using the SOGNI API.
#   - Notifies via Pushover, Telegram, or ntfy if a worker goes offline, is kicked,
#     or encounters repeated API errors.
#
# HOW TO USE:
#   1. Fill out NFT_IDS and notification credentials in the CONFIGURATION section.
#   2. Make sure curl, jq, timeout, and date are installed.
#   3. Run the script on any Linux/Mac terminal.
#
# AUTHOR: owlyeagle
################################################################################

# ========== CONFIGURATION ==========
NFT_IDS=(123 456 789)     # <-- Add your NFT IDs here
API_ENDPOINT="https://socket.sogni.ai/api/v1/client/nft"
CHECK_INTERVAL=60                                 # Check every 60 seconds

# --- Notification Credentials ---
PUSHOVER_USER_KEY=""         # Fill in if using Pushover
PUSHOVER_API_TOKEN=""        # Fill in if using Pushover
NOTIFICATION_SERVICE="pushover"   # pushover | telegram | ntfy
TELEGRAM_BOT_TOKEN=""        # Fill in if using Telegram
TELEGRAM_CHAT_ID=""          # Fill in if using Telegram
NTFY_TOPIC=""                # Fill in if using ntfy.sh

DEBUG_MODE="false"           # Set to "true" for verbose logs
TIME_SYNC_TOLERANCE=7200     # 2 hours skew tolerance for clock issues
JOB_COMPLETION_WINDOW=180    # 3 minutes (180s) - RTX 5090 optimized

# ===== DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING =====

# ========== DEPENDENCY CHECK ==========
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
ORANGE='\033[38;5;214m'; WHITE='\033[1;37m'; BLUE='\033[1;34m'; RESET='\033[0m'

echo -e "${GREEN}🔍 Checking dependencies...${RESET}"
for dep in curl jq timeout date; do
    if ! command -v $dep >/dev/null 2>&1; then
        echo -e "${RED}❌ Missing dependency: $dep${RESET}"
        exit 1
    fi
done
echo -e "${GREEN}✅ All dependencies found${RESET}"

# ========== STATE ==========
declare -A prev_status prev_kick_time prev_jobfail_time first_run_done
declare -A consecutive_errors last_valid_status

# ========== NOTIFICATION FUNCTIONS ==========
send_pushover() {
    local title="$1"; local message="$2"; local priority="$3"
    if [[ -z "$PUSHOVER_USER_KEY" || -z "$PUSHOVER_API_TOKEN" ]]; then
        echo "⚠️  Pushover credentials not configured"; return 1
    fi
    curl -s --max-time 10 -F "token=$PUSHOVER_API_TOKEN" -F "user=$PUSHOVER_USER_KEY" \
         -F "title=$title" -F "message=$message" -F "priority=${priority:-0}" \
         https://api.pushover.net/1/messages.json > /dev/null
}
send_telegram() {
    local title="$1"; local message="$2"
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        echo "⚠️  Telegram credentials not configured"; return 1
    fi
    local full_message="🤖 *$title*%0A$message"
    curl -s --max-time 10 -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
         -d "chat_id=$TELEGRAM_CHAT_ID" -d "text=$full_message" -d "parse_mode=Markdown" > /dev/null
}
send_ntfy() {
    local title="$1"; local message="$2"; local priority="$3"
    if [[ -z "$NTFY_TOPIC" ]]; then
        echo "⚠️  ntfy topic not configured"; return 1
    fi
    curl -s --max-time 10 -H "Title: $title" -H "Priority: ${priority:-default}" \
         -H "Tags: computer,warning" -d "$message" "https://ntfy.sh/$NTFY_TOPIC" > /dev/null
}
send_notification() {
    local title="$1"; local message="$2"; local priority="$3"
    case "$NOTIFICATION_SERVICE" in
        "pushover") send_pushover "$title" "$message" "$priority" ;;
        "telegram") send_telegram "$title" "$message" ;;
        "ntfy") send_ntfy "$title" "$message" "$priority" ;;
        *) echo "⚠️  Unknown notification service: $NOTIFICATION_SERVICE" ;;
    esac
}

# ========== UTILS ==========
truncate_text() {
    local text="$1"; local max_len="$2"
    if [ ${#text} -le $max_len ]; then echo "$text"
    else local half=$(( (max_len - 3) / 2 )); echo "${text:0:$half}...${text: -$half}"; fi
}
format_duration() {
    local sec="$1"
    if (( sec >= 2592000 )); then printf "%dmo" $((sec/2592000))
    elif (( sec >= 86400 )); then printf "%dd%dh" $((sec/86400)) $(((sec%86400)/3600))
    elif (( sec >= 3600 )); then printf "%dh%02dm" $((sec/3600)) $(((sec%3600)/60))
    elif (( sec >= 60 )); then printf "%dm%02ds" $((sec/60)) $((sec%60))
    else printf "%ds" "$sec"; fi
}
print_line() {
    for width in 4 8 13 22 7 25 8 8 8; do
        printf "+%*s" $((width+2)) "" | tr ' ' '-'
    done; printf "+\n"
}
get_timestamp_age() {
    local timestamp_ms="$1"; local now_ms="$2"
    if [[ -z "$timestamp_ms" || "$timestamp_ms" == "null" ]]; then echo "999999999"; return; fi
    local age_ms=$((now_ms - timestamp_ms)); local age_sec=$((age_ms / 1000))
    if (( age_sec > 31536000 )); then echo "999999999"; return; fi
    echo "$age_sec"
}

# ========== STATUS DETECTION ==========
determine_nft_status() {
    local response="$1"; local now_ms="$2"; local nft_id="$3"
    local last_job_time=$(echo "$response" | jq -r '.lastJobCompleteTime // empty')
    local connect_time=$(echo "$response" | jq -r '.connectTime // empty')
    local last_app_start_time=$(echo "$response" | jq -r '.lastAppStartTime // empty')
    local job_age=$(get_timestamp_age "$last_job_time" "$now_ms")
    local connect_age=$(get_timestamp_age "$connect_time" "$now_ms")
    local app_age=$(get_timestamp_age "$last_app_start_time" "$now_ms")
    local status="OFFLINE"
    # 1. Active job
    local active_job=$(echo "$response" | jq -r '.activeWorkerJob // empty')
    if [[ -n "$active_job" && "$active_job" != "null" ]]; then
        status="ONLINE"; echo "$status"; return
    fi
    # 2. Recent job completion (3min window)
    if [[ "$job_age" != "999999999" ]]; then
        if (( job_age >= -TIME_SYNC_TOLERANCE && job_age < JOB_COMPLETION_WINDOW )); then
            status="ONLINE"; echo "$status"; return
        fi
    fi
    # 3. Connection time (1 hour)
    if [[ "$connect_age" != "999999999" ]]; then
        if (( connect_age >= -TIME_SYNC_TOLERANCE && connect_age < 3600 )); then
            status="ONLINE"; echo "$status"; return
        fi
    fi
    # 4. App start time (1 hour)
    if [[ "$app_age" != "999999999" ]]; then
        if (( app_age >= -TIME_SYNC_TOLERANCE && app_age < 3600 )); then
            status="ONLINE"; echo "$status"; return
        fi
    fi
    # 5. Fallback: session job count
    local session_jobs=$(echo "$response" | jq -r '.sessionJobCount // 0')
    local completed_since_break=$(echo "$response" | jq -r '.completedJobsSinceBreak // 0')
    if [[ "$session_jobs" -gt 0 || "$completed_since_break" -gt 0 ]]; then
        if [[ "$job_age" != "999999999" ]] && (( job_age < 7200 )); then
            status="ONLINE"; echo "$status"; return
        fi
    fi
    echo "$status"
}

# ========== API CALL ==========
fetch_nft_data() {
    local nft_id="$1"; local response; local exit_code
    response=$(timeout 15 curl -s --max-time 10 --retry 2 --retry-delay 1 \
        --retry-max-time 5 "$API_ENDPOINT/$nft_id/status" 2>/dev/null)
    exit_code=$?
    case $exit_code in
        0) if echo "$response" | jq . >/dev/null 2>&1; then consecutive_errors[$nft_id]=0; echo "$response"; return 0
           else echo "ERROR: Invalid JSON for NFT $nft_id"; return 2; fi ;;
        124) echo "ERROR: Timeout for NFT $nft_id (>15s)"; return 1 ;;
        *) echo "ERROR: Network/curl error for NFT $nft_id (exit code: $exit_code)"; return 1 ;;
    esac
}

# ========== TIME DISPLAY ==========
format_time_display() {
    local timestamp_ms="$1"; local now_ms="$2"
    if [[ -z "$timestamp_ms" || "$timestamp_ms" == "null" ]]; then echo "-"; return; fi
    local age_sec=$(get_timestamp_age "$timestamp_ms" "$now_ms")
    if [[ "$age_sec" == "999999999" ]]; then echo "-"; return; fi
    if (( age_sec < -60 )); then echo "sync?"
    elif (( age_sec < 0 )); then echo "now"
    else format_duration "$age_sec"; fi
}

# ========== MAIN MONITOR LOOP ==========
monitor_nfts() {
    clear
    echo -e "${CYAN}SOGNI NFT Monitor - $(date)${RESET}"
    echo -e "${YELLOW}📱 Notifications: $NOTIFICATION_SERVICE | ⚡ RTX 5090 - 3min job window${RESET}\n"
    print_line
    printf "| %-4s | %-8s | %-13s | %-22s | %-7s | %-25s | %-8s | %-8s | %-8s |\n" \
        "NFT" "Status" "Worker" "GPU" "Speed" "Model" "LastJob" "LastKick" "JobFail"
    print_line
    offline_nfts=(); api_errors=0; now_ms=$(($(date +%s) * 1000))
    for nft_id in "${NFT_IDS[@]}"; do
        response=$(fetch_nft_data "$nft_id"); fetch_result=$?
        if [[ $fetch_result -ne 0 ]]; then
            consecutive_errors[$nft_id]=$((consecutive_errors[$nft_id] + 1)); api_errors=$((api_errors + 1))
            if [[ -v last_valid_status[$nft_id] ]]; then status="${last_valid_status[$nft_id]}"; error_suffix=" (cached)"
            else status="UNKNOWN"; error_suffix=""; fi
            [[ $fetch_result -eq 1 ]] && error_type="TIMEOUT" || error_type="API_ERR"
            echo -e "${RED}${error_type} for NFT $nft_id${error_suffix}${RESET}"
            printf "| %b | %b | %b | %b | %b | %b | %b | %b | %b |\n" \
                "${YELLOW}$(printf "%-4s" "$nft_id")${RESET}" \
                "${RED}$(printf "%-8s" "$error_type")${RESET}" \
                "${RED}$(printf "%-13s" "API Error")${RESET}" \
                "${RED}$(printf "%-22s" "Connection Failed")${RESET}" \
                "${RED}$(printf "%-7s" "-")${RESET}" \
                "${RED}$(printf "%-25s" "Error #${consecutive_errors[$nft_id]}${error_suffix}")${RESET}" \
                "${RED}$(printf "%-8s" "-")${RESET}" \
                "${RED}$(printf "%-8s" "-")${RESET}" \
                "${RED}$(printf "%-8s" "-")${RESET}"
            if [[ ${consecutive_errors[$nft_id]} -ge 5 ]] && [[ -v first_run_done[$nft_id] ]]; then
                send_notification "🚨 NFT $nft_id API ERROR" \
                    "Persistent API failures (${consecutive_errors[$nft_id]} consecutive)" "1"
                echo -e "${RED}📱 Sent: NFT $nft_id has persistent API errors${RESET}"
                consecutive_errors[$nft_id]=0
            fi; continue
        fi
        consecutive_errors[$nft_id]=0
        status=$(determine_nft_status "$response" "$now_ms" "$nft_id")
        last_valid_status[$nft_id]="$status"
        worker=$(echo "$response" | jq -r '.image // "-"')
        gpu=$(echo "$response" | jq -r '.gpu // "-"')
        speed_val=$(echo "$response" | jq -r '.speedVsBaseline // "-"')
        [[ "$speed_val" != "-" && "$speed_val" != "null" ]] && speed="⚡${speed_val}x" || speed="-"
        model=$(echo "$response" | jq -r '.loadedModelID // "-"')
        last_job_time=$(echo "$response" | jq -r '.lastJobCompleteTime // empty')
        last_worker_kick_time=$(echo "$response" | jq -r '.lastWorkerKickTime // empty')
        last_timeout_time=$(echo "$response" | jq -r '.lastJobTimeoutTime // empty')
        lastjob=$(format_time_display "$last_job_time" "$now_ms")
        lastkick=$(format_time_display "$last_worker_kick_time" "$now_ms")
        jobfail=$(format_time_display "$last_timeout_time" "$now_ms")
        if [[ -v first_run_done[$nft_id] ]] && [[ -v prev_status[$nft_id] ]] && [[ "${prev_status[$nft_id]}" != "$status" ]]; then
            if [[ "$status" == "OFFLINE" ]]; then
                send_notification "🔴 NFT $nft_id OFFLINE" "Worker has gone offline" "1"
                echo -e "${RED}📱 Sent: NFT $nft_id went OFFLINE${RESET}"
            elif [[ "$status" == "ONLINE" ]]; then
                send_notification "🟢 NFT $nft_id ONLINE" "Worker back online\nGPU: $gpu\nModel: $model" "0"
                echo -e "${GREEN}📱 Sent: NFT $nft_id came ONLINE${RESET}"
            fi
        fi
        prev_status[$nft_id]="$status"
        if [[ -n "$last_worker_kick_time" && "$last_worker_kick_time" != "null" ]] && [[ -v first_run_done[$nft_id] ]]; then
            kick_age_sec=$(get_timestamp_age "$last_worker_kick_time" "$now_ms")
            if [[ -v prev_kick_time[$nft_id] ]] && [[ "${prev_kick_time[$nft_id]}" != "$last_worker_kick_time" ]] && \
               [[ "$kick_age_sec" != "999999999" ]] && (( kick_age_sec >= 0 && kick_age_sec < 600 )); then
                send_notification "⚠️ NFT $nft_id KICKED" "Worker kicked $lastkick ago\nGPU: $gpu" "1"
                echo -e "${YELLOW}📱 Sent: NFT $nft_id KICKED${RESET}"
            fi
        fi
        prev_kick_time[$nft_id]="$last_worker_kick_time"
        if [[ -n "$last_timeout_time" && "$last_timeout_time" != "null" ]] && [[ -v first_run_done[$nft_id] ]]; then
            timeout_age_sec=$(get_timestamp_age "$last_timeout_time" "$now_ms")
            if [[ -v prev_jobfail_time[$nft_id] ]] && [[ "${prev_jobfail_time[$nft_id]}" != "$last_timeout_time" ]] && \
               [[ "$timeout_age_sec" != "999999999" ]] && (( timeout_age_sec >= 0 && timeout_age_sec < 600 )); then
                send_notification "❌ NFT $nft_id JOB FAILED" "Job timeout $jobfail ago\nGPU: $gpu" "1"
                echo -e "${RED}📱 Sent: NFT $nft_id JOB FAILED${RESET}"
            fi
        fi
        prev_jobfail_time[$nft_id]="$last_timeout_time"
        first_run_done[$nft_id]="true"
        [[ "$status" == "OFFLINE" ]] && offline_nfts+=("$nft_id")
        worker=$(truncate_text "$worker" 13)
        gpu=$(truncate_text "$gpu" 22)
        model=$(truncate_text "$model" 25)
        [[ "$status" == "ONLINE" ]] && status_color="${GREEN}" || status_color="${RED}"
        printf "| %b | %b | %b | %b | %b | %b | %b | %b | %b |\n" \
            "${YELLOW}$(printf "%-4s" "$nft_id")${RESET}" \
            "${status_color}$(printf "%-8s" "$status")${RESET}" \
            "${GREEN}$(printf "%-13s" "$worker")${RESET}" \
            "${WHITE}$(printf "%-22s" "$gpu")${RESET}" \
            "${ORANGE}$(printf "%-7s" "$speed")${RESET}" \
            "${BLUE}$(printf "%-25s" "$model")${RESET}" \
            "${CYAN}$(printf "%-8s" "$lastjob")${RESET}" \
            "${RED}$(printf "%-8s" "$lastkick")${RESET}" \
            "${RED}$(printf "%-8s" "$jobfail")${RESET}"
    done
    print_line
    echo; echo -e "${GREEN}✅ All ${#NFT_IDS[@]} NFTs monitored${RESET}"
    if (( ${#offline_nfts[@]} > 0 )); then
        echo -en "${RED}❌ OFFLINE NFT(s): "; for id in "${offline_nfts[@]}"; do echo -n "$id "; done; echo -e "${RESET}"
    fi
    if (( api_errors > 0 )); then
        echo -e "${ORANGE}⚠️  API Errors this cycle: $api_errors${RESET}"
    fi
    echo -e "${YELLOW}🔄 Next refresh in ${CHECK_INTERVAL} seconds... (Press Ctrl+C to exit)${RESET}"
}

# ========== STARTUP ==========
cleanup() { echo -e "\n${YELLOW}Shutting down monitor...${RESET}"; exit 0; }
trap cleanup SIGINT SIGTERM
validate_config() {
    case "$NOTIFICATION_SERVICE" in
        "pushover") [[ -z "$PUSHOVER_USER_KEY" || -z "$PUSHOVER_API_TOKEN" ]] && { echo -e "${RED}❌ Pushover not configured${RESET}"; return 1; } ;;
        "telegram") [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && { echo -e "${RED}❌ Telegram not configured${RESET}"; return 1; } ;;
        "ntfy") [[ -z "$NTFY_TOPIC" ]] && { echo -e "${RED}❌ ntfy not configured${RESET}"; return 1; } ;;
        *) echo -e "${RED}❌ Invalid notification service${RESET}"; return 1 ;;
    esac; return 0
}
echo -e "${GREEN}🚀 SOGNI NFT Monitor Template (RTX 5090, 3min window)...${RESET}"
echo -e "${CYAN}Monitoring ${#NFT_IDS[@]} NFTs every ${CHECK_INTERVAL} seconds${RESET}"
echo -e "${YELLOW}Job completion window: ${JOB_COMPLETION_WINDOW} seconds (3 minutes)${RESET}"
echo -e "${YELLOW}Time sync tolerance: ${TIME_SYNC_TOLERANCE} seconds${RESET}"
validate_config || { echo -e "${RED}Exiting due to config errors${RESET}"; exit 1; }
send_notification "🚀 NFT Monitor Started" "RTX 5090 optimized - 3min job window\nMonitoring ${#NFT_IDS[@]} NFTs every ${CHECK_INTERVAL}s" "0"
while true; do monitor_nfts; sleep $CHECK_INTERVAL; done
