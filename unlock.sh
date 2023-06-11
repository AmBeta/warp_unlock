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

# 更换 Warp IP
function Change_IP() {
  echo -n -e "\r ${Font_Blue}Changing IP...${Font_Suffix}"
  # systemctl restart wg-quick@wgcf
  
  local result = $(curl -fs --max-time 5 "ip.p3terx.com")
  local ip_address = $(echo "$result" | head -n 1)

  if [[ -n $ip_address ]]; then
    echo -n -e "\r ${Font_Green}Get new ip address: $ip_address ${Font_Suffix}"
  else
    echo -n -e "\r ${Font_Red}Failed to get new ip address, sleep 3 seconds then retry.${Font_Suffix}"
    sleep 3
    Change_IP
  fi
}

# 检查 Netflix 联通性
function UnlockTest_Netflix() {
  echo "\r Checking:\tNetflix"

  local result1=$(curl --user-agent "${UA_Browser}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "${Netflix_Check_URL1}" 2>&1)
  local result2=$(curl --user-agent "${UA_Browser}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "${Netflix_Check_URL2}" 2>&1)

  if [[ "$result1" == "404" ]] && [[ "$result2" == "404" ]]; then
    echo -n -e "\r Netflix:\t${Font_Yellow}Originals Only${Font_Suffix}\n"
    return 1
  elif [[ "$result1" == "403" ]] && [[ "$result2" == "403" ]]; then
    echo -n -e "\r Netflix:\t${Font_Red}No${Font_Suffix}\n"
    return 1
  elif [[ "$result1" == "200" ]] || [[ "$result2" == "200" ]]; then
    local region=$(curl --user-agent "${UA_Browser}" -fs --max-time 10 --write-out %{redirect_url} --output /dev/null "${Netflix_Region_URL}" 2>&1 | cut -d '/' -f4 | cut -d '-' -f1 | tr [:lower:] [:upper:])
    if [[ ! -n "$region" ]]; then
      region="US"
    fi
    echo -n -e "\r Netflix:\t${Font_Green}Yes (Region: ${region})${Font_Suffix}\n"
    return 0
  elif [[ "$result1" == "000" ]]; then
    echo -n -e "\r Netflix:\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
    return 1
  fi
}

attempt=1
while [[ $attempt -le $MAX_ATTEMPTS ]]; do
  echo "\r${Font_Blue}Trying $attempt...${Font_Suffix}"
  if UnlockTest_Netflix; then
    echo -n -e "\r${Font_Green}Success!${Font_Suffix}"
    break
  else
    Change_IP
    attempt=$((attempt + 1))
  fi
done

if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
  echo -n -e "\r${Font_Red}Failed!${Font_Suffix}"
  #TODO: 发送到 telegram
fi