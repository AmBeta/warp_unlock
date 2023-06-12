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

MAX_ATTEMPTS=10
LOG_FILE="./log.txt"

# Get options
while getopts ":l:t" opt; do
  case $opt in
  l)
    LOG_FILE="$OPTARG"
    ;;
  t)
    MAX_ATTEMPTS="$OPTARG"
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    exit 1
    ;;
  :)
    echo "Option -$OPTARG requires an argument." >&2
    exit 1
    ;;
  esac
done

function Log() {
  local message=$1
  local font_color=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
  fi

  printf "[$timestamp] ${font_color}$message${Font_Suffix}\n"
  printf "[$timestamp] $message\n" >>"$LOG_FILE"
}

# Refresh Warp IP
function Change_IP() {
  Log "Changing IP..." $Font_SkyBlue
  systemctl restart wg-quick@wgcf

  local result=$(timeout 5s curl -fs "ip.p3terx.com")
  local ip_address=$(echo "$result" | head -n 1)

  if [[ -n $ip_address ]]; then
    Log "Get new ip address: $ip_address" $Font_Green
  else
    Log "Failed to get new IP address, sleep 3 seconds then retry." $Font_Red
    sleep 3
    Change_IP
  fi
}

# Check unlock for Netflix
function UnlockTest_Netflix() {
  Log "Checking:\tNetflix" $Font_SkyBlue

  local result1=$(curl --user-agent "${UA_Browser}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81280792" 2>&1)
  local result2=$(curl --user-agent "${UA_Browser}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/70143836" 2>&1)

  if [[ "$result1" == "404" ]] && [[ "$result2" == "404" ]]; then
    Log "Netflix:\tOriginals Only" $Font_Yellow
    return 1
  elif [[ "$result1" == "403" ]] && [[ "$result2" == "403" ]]; then
    Log "Netflix:\tNo" $Font_Red
    return 1
  elif [[ "$result1" == "200" ]] || [[ "$result2" == "200" ]]; then
    local region=$(curl --user-agent "${UA_Browser}" -fs --max-time 10 --write-out %{redirect_url} --output /dev/null "https://www.netflix.com/title/80018499" 2>&1 | cut -d '/' -f4 | cut -d '-' -f1 | tr [:lower:] [:upper:])
    if [[ ! -n "$region" ]]; then
      region="US"
    fi
    Log "Netflix:\tYes (Region: ${region})" $Font_Green
    return 0
  elif [[ "$result1" == "000" ]]; then
    Log "Netflix:\tFailed (Network Connection)" $Font_Red
    return 1
  fi
}

# Check unlock for OpenAI
function UnlockTest_OpenAI() {
  Log "Checking:\tOpenAI" $Font_SkyBlue

  local result1=$(curl -sL --max-time 10 "https://chat.openai.com" | grep 'Sorry, you have been blocked')
  local result2=$(curl -sI --max-time 10 "https://chat.openai.com" | grep 'cf-mitigated: challenge')
  if [ -z "$result1" ] && [ -n "$result2" ]; then
    Log "OpenAI:\tYes" $Font_Green
    return
  else
    Log "OpenAI:\tNo" $Font_Red
    return
  fi
}

attempt=1
while [[ $attempt -le $MAX_ATTEMPTS ]]; do
  Log "Trying $attempt..." $Font_Blue

  if UnlockTest_Netflix && UnlockTest_OpenAI; then
    Log "Success!" $Font_Green
    break
  else
    Change_IP
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
  Log "\r${Font_Red}Failed!${Font_Suffix}" $Font_Red
  #TODO: send notification to telegram bot
fi
