#!/bin/bash

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
Media_Cookie=$(curl -s --retry 3 --max-time 10 "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/cookies")

MAX_ATTEMPTS=50
NF_REGION="US"
LOG_FILE="$LOG_FILE"
TG_TOKEN="$TG_TOKEN"
TG_USER_ID="$TG_USER_ID"

# Get options
while getopts ":l:t:r:" opt; do
  case $opt in
  # log file path
  l)
    LOG_FILE="$OPTARG"
    ;;
  # telegram token and user id: token@userID
  t)
    TG_TOKEN="$(echo $OPTARG | cut -d'@' -f1)"
    TG_USER_ID="$(echo $OPTARG | cut -d'@' -f2)"
    ;;
  # expected netflix unlock region
  r)
    NF_REGION="$OPTARG"
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

  if [[ -n "$LOG_FILE" ]] && [[ ! -f "$LOG_FILE" ]]; then
    touch "$LOG_FILE"
  fi

  printf "[$timestamp] ${font_color}$message${Font_Suffix}\n"

  if [[ -n "$LOG_FILE" ]]; then
    printf "[$timestamp] $message\n" >>"$LOG_FILE"
  fi
}

function Notify() {
  local message=$1

  # send notification to telegram bot
  if [[ -n "$TG_TOKEN" ]] && [[ -n "$TG_USER_ID" ]]; then
    local text="*[Warp Unlock]*%0ACurrent IP: $ip_address%0A$message"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
      -d "chat_id=$TG_USER_ID" \
      -d "text=$text" \
      -d "parse_mode=MarkdownV2" \
      --output /dev/null 2>&1
  fi
}

# Refresh Warp IP
ip_address=$(curl -fs "ip.p3terx.com" | head -n 1)
function Change_IP() {
  Log "Changing IP..." $Font_SkyBlue
  systemctl restart wg-quick@wgcf

  local result=$(timeout 5s curl -fs "ip.p3terx.com")
  ip_address=$(echo "$result" | head -n 1)

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
    if [[ ! "$region" == $(echo "$NF_REGION" | tr '[:lower:]' '[:upper:]') ]]; then
      Log "Netflix:\tRegion Mismatch (Region: ${region}/${NF_REGION})" $Font_Red
      return 1
    fi
    Log "Netflix:\tYes (Region: ${region})" $Font_Green
    return 0
  elif [[ "$result1" == "000" ]]; then
    Log "Netflix:\tFailed (Network Connection)" $Font_Red
    return 1
  fi
}

# Check unlock for Disney+
function UnlockTest_DisneyPlus() {
  Log "Checking:\tDisney+" $Font_SkyBlue

  local PreAssertion=$(curl --user-agent "${UA_Browser}" -s --max-time 10 -X POST "https://disney.api.edge.bamgrid.com/devices" -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -H "content-type: application/json; charset=UTF-8" -d '{"deviceFamily":"browser","applicationRuntime":"chrome","deviceProfile":"windows","attributes":{}}' 2>&1)
  if [[ "$PreAssertion" == "curl"* ]] && [[ "$1" == "6" ]]; then
    Log "Disney+:\tIPv6 Not Support" $Font_Red
    return 1
  elif [[ "$PreAssertion" == "curl"* ]]; then
    Log "Disney+:\tFailed (Network Connection)" $Font_Red
    return 1
  fi

  local assertion=$(echo $PreAssertion | python -m json.tool 2>/dev/null | grep assertion | cut -f4 -d'"')
  local PreDisneyCookie=$(echo "$Media_Cookie" | sed -n '1p')
  local disneycookie=$(echo $PreDisneyCookie | sed "s/DISNEYASSERTION/${assertion}/g")
  local TokenContent=$(curl --user-agent "${UA_Browser}" -s --max-time 10 -X POST "https://disney.api.edge.bamgrid.com/token" -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -d "$disneycookie" 2>&1)
  local isBanned=$(echo $TokenContent | python -m json.tool 2>/dev/null | grep 'forbidden-location')
  local is403=$(echo $TokenContent | grep '403 ERROR')

  if [ -n "$isBanned" ] || [ -n "$is403" ]; then
    Log "Disney+:\tBanned" $Font_Red
    return 1
  fi

  local fakecontent=$(echo "$Media_Cookie" | sed -n '8p')
  local refreshToken=$(echo $TokenContent | python -m json.tool 2>/dev/null | grep 'refresh_token' | awk '{print $2}' | cut -f2 -d'"')
  local disneycontent=$(echo $fakecontent | sed "s/ILOVEDISNEY/${refreshToken}/g")
  local tmpresult=$(curl --user-agent "${UA_Browser}" -X POST -sSL --max-time 10 "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" -H "authorization: ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -d "$disneycontent" 2>&1)
  local previewcheck=$(curl -s -o /dev/null -L --max-time 10 -w '%{url_effective}\n' "https://disneyplus.com" | grep preview)
  local isUnabailable=$(echo $previewcheck | grep 'unavailable')
  local region=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep 'countryCode' | cut -f4 -d'"')
  local inSupportedLocation=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep 'inSupportedLocation' | awk '{print $2}' | cut -f1 -d',')

  if [[ "$region" == "JP" ]]; then
    Log "Disney+:\tYes (Region: JP)" $Font_Green
    return
  elif [ -n "$region" ] && [[ "$inSupportedLocation" == "false" ]] && [ -z "$isUnabailable" ]; then
    Log "Disney+:\tAvailable For [Disney+ $region] Soon" $Font_Yellow
    return 1
  elif [ -n "$region" ] && [ -n "$isUnavailable" ]; then
    Log "Disney+:\tNo" $Font_Red
    return 1
  elif [ -n "$region" ] && [[ "$inSupportedLocation" == "true" ]]; then
    Log "Disney+:\tYes (Region: $region)" $Font_Green
    return
  elif [ -z "$region" ]; then
    Log "Disney+:\tNo" $Font_Red
    return 1
  else
    Log "Disney+:\tFailed" $Font_Red
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
    return 1
  fi
}

attempt=1
while [[ $attempt -le $MAX_ATTEMPTS ]]; do
  Log "Trying $attempt..." $Font_Blue

  if UnlockTest_Netflix && UnlockTest_DisneyPlus && UnlockTest_OpenAI; then
    Notify "Check result: ✅"
    Log "Success!" $Font_Green
    break
  else
    # Notify "Check result: ❌ Retrying"
    Change_IP
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
  Notify "Check result: ❌"
  Log "Failed!" $Font_Red
fi
