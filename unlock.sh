#bin/bash!
Font_Black="\033[30m"
Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Blue="\033[34m"
Font_Purple="\033[35m"
Font_SkyBlue="\033[36m"
Font_White="\033[37m"
Font_Suffix="\033[0m"

UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36"
Netflix_Check_URL1="https://www.netflix.com/title/81280792"
Netflix_Check_URL2="https://www.netflix.com/title/70143836"
Netflix_Region_URL="https://www.netflix.com/title/80018499"

MAX_ATTEMPTS=10
LOG_FILE="./log.txt"

function Log() {
  local message=$1
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
  fi

  echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Refresh Warp IP
function Change_IP() {
  Log "Changing IP..."
  systemctl restart wg-quick@wgcf

  local result=$(timeout 5s curl -fs "ip.p3terx.com")
  local ip_address=$(echo "$result" | head -n 1)

  if [[ -n $ip_address ]]; then
    Log "Get new ip address: $ip_address"
  else
    Log "Failed to get new ip address, sleep 3 seconds then retry."
    sleep 3
    Change_IP
  fi
}

# Check unlock for Netflix
function UnlockTest_Netflix() {
  Log "Checking:\tNetflix"

  local result1=$(curl --user-agent "${UA_Browser}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "${Netflix_Check_URL1}" 2>&1)
  local result2=$(curl --user-agent "${UA_Browser}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "${Netflix_Check_URL2}" 2>&1)

  if [[ "$result1" == "404" ]] && [[ "$result2" == "404" ]]; then
    Log "Netflix:\tOriginals Only"
    return 1
  elif [[ "$result1" == "403" ]] && [[ "$result2" == "403" ]]; then
    Log "Netflix:\tNo"
    return 1
  elif [[ "$result1" == "200" ]] || [[ "$result2" == "200" ]]; then
    local region=$(curl --user-agent "${UA_Browser}" -fs --max-time 10 --write-out %{redirect_url} --output /dev/null "${Netflix_Region_URL}" 2>&1 | cut -d '/' -f4 | cut -d '-' -f1 | tr [:lower:] [:upper:])
    if [[ ! -n "$region" ]]; then
      region="US"
    fi
    Log "Netflix:\tYes (Region: ${region})"
    return 0
  elif [[ "$result1" == "000" ]]; then
    Log "Netflix:\tFailed (Network Connection)"
    return 1
  fi
}

attempt=1
while [[ $attempt -le $MAX_ATTEMPTS ]]; do
  Log "Trying $attempt..."
  if UnlockTest_Netflix; then
    Log "Success!"
    break
  else
    Change_IP
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
  Log "\r${Font_Red}Failed!${Font_Suffix}"
  #TODO: send notification to telegram bot
fi
