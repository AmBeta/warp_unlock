#!/usr/bin/env bash

# 默认配置文件路径
DEFAULT_CONFIG_FILE="./warp_unlock.conf"

# 解析命令行参数
while getopts "c:" opt; do
  case $opt in
    c)
      CONFIG_FILE="$OPTARG"
      ;;
    \?)
      echo "无效的选项: -$OPTARG" >&2
      echo "用法: $0 [-c 配置文件路径]"
      exit 1
      ;;
    :)
      echo "选项 -$OPTARG 需要参数" >&2
      echo "用法: $0 [-c 配置文件路径]"
      exit 1
      ;;
  esac
done

# 如果未通过命令行指定配置文件，使用默认值
[ -z "$CONFIG_FILE" ] && CONFIG_FILE="$DEFAULT_CONFIG_FILE"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件 $CONFIG_FILE 不存在，请先创建配置文件"
    exit 1
fi

# 从配置文件读取配置
source "$CONFIG_FILE"

# 检查必要的配置项
if [ -z "$TOKEN" ] || [ -z "$USERID" ]; then
    echo "配置文件缺少必要的配置项：TOKEN 或 USERID"
    exit 1
fi

# 设置默认值
[ -z "$CUSTOM" ] && CUSTOM="WARP_UNLOCK"
[ -z "$WARP_API_URL" ] && WARP_API_URL="www.warpapi.us.kg"
[ -z "$MODE" ] && MODE="2"
[ -z "$EXPECT" ] && EXPECT="US"
[ -z "$NIC" ] && NIC="-ks6m8 --interface wgcf"
[ -z "$RESTART" ] && RESTART="warp_restart"
[ -z "$LOG_LIMIT" ] && LOG_LIMIT="1000"
[ -z "$PYTHON" ] && PYTHON="python3"
[ -z "$UNLOCK_STATUS" ] && UNLOCK_STATUS='Yes 🎉'
[ -z "$NOT_UNLOCK_STATUS" ] && NOT_UNLOCK_STATUS='No 😰'
[ -z "$STREAMING_SERVICES" ] && STREAMING_SERVICES="Netflix Disney+"

# 获取 lmc999 的检测脚本
LMC999_SCRIPT="$(curl -sSLm4 https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)"

# 保存检测脚本到当前目录
echo "$LMC999_SCRIPT" > "./check.sh"
chmod +x "./check.sh"

timedatectl set-timezone Asia/Shanghai

if [[ $(pgrep -laf $0 | wc -l) < 4 ]]; then
  log_output="\$(date +'%F %T'). \\\tIP: \$WAN \\\tCountry: \$COUNTRY \\\t\$CONTENT"
  tg_output="💻 \$CUSTOM. ⏰ \$(date +'%F %T'). 🛰 \$WAN  🌏 \$COUNTRY. \$CONTENT"

  log_message() { 
    echo -e "$(eval echo "$log_output")" | tee -a /root/result.log
    [[ $(cat /root/result.log | wc -l) -gt $LOG_LIMIT ]] && sed -i "1,10d" /root/result.log
  }
  
  tg_message() { 
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
      -d chat_id=$USERID \
      -d text="$(eval echo "$tg_output")" \
      -d parse_mode="HTML" >/dev/null 2>&1
  }

  fetch_account_information() {
    local REGISTER_PATH="$1"
    if grep -q 'xml version' $REGISTER_PATH; then
      WARP_DEVICE_ID=$(grep 'correlation_id' $REGISTER_PATH | sed "s#.*>\(.*\)<.*#\1#")
      WARP_TOKEN=$(grep 'warp_token' $REGISTER_PATH | sed "s#.*>\(.*\)<.*#\1#")
      CLIENT_ID=$(grep 'client_id' $REGISTER_PATH | sed "s#.*client_id&quot;:&quot;\([^&]\{4\}\)&.*#\1#")

    # 官方 api 文件
    elif grep -q 'client_id' $REGISTER_PATH; then
      WARP_DEVICE_ID=$(grep -m1 '"id' "$REGISTER_PATH" | cut -d\" -f4)
      WARP_TOKEN=$(grep '"token' "$REGISTER_PATH" | cut -d\" -f4)
      CLIENT_ID=$(grep 'client_id' "$REGISTER_PATH" | cut -d\" -f4)

    # client 文件，默认存放路径为 /var/lib/cloudflare-warp/reg.json
    elif grep -q 'registration_id' $REGISTER_PATH; then
      WARP_DEVICE_ID=$(cut -d\" -f4 "$REGISTER_PATH")
      WARP_TOKEN=$(cut -d\" -f8 "$REGISTER_PATH")

    # wgcf 文件，默认存放路径为 /etc/wireguard/wgcf-account.toml
    elif grep -q 'access_token' $REGISTER_PATH; then
      WARP_DEVICE_ID=$(grep 'device_id' "$REGISTER_PATH" | cut -d\' -f2)
      WARP_TOKEN=$(grep 'access_token' "$REGISTER_PATH" | cut -d\' -f2)

    # warp-go 文件，默认存放路径为 /opt/warp-go/warp.conf
    elif grep -q 'PrivateKey' $REGISTER_PATH; then
      WARP_DEVICE_ID=$(awk -F' *= *' '/^Device/{print }' "$REGISTER_PATH")
      WARP_TOKEN=$(awk -F' *= *' '/^Token/{print }' "$REGISTER_PATH")
    else
      echo " There is no registered account information, please check the content. " && exit 1
    fi
  }

  check_ip() {
    unset IP_INFO WAN COUNTRY ASNORG
    IP_INFO="$(curl $NIC -A Mozilla https://api.ip.sb/geoip)"
    WAN="$(expr "$IP_INFO" : '.*ip\":[ ]*\"\([^"]*\).*')"
    COUNTRY="$(expr "$IP_INFO" : '.*country\":[ ]*\"\([^"]*\).*')"
    ASNORG="$(expr "$IP_INFO" : '.*'isp'\":[ ]*\"\([^"]*\).*')"
  }

  # api 注册账户,优先使用 warp-go 团队 api,后备使用官方 api 脚本
  registe_api() {
    local REGISTE_FILE_PATH="$1"
    local LICENSE="$2"
    local NAME="$3"
    local i=0
    local j=5
    
    until [ -s $REGISTE_FILE_PATH ]; do
      ((i++)) || true
      [ "$i" -gt "$j" ] && rm -f $REGISTE_FILE_PATH && echo -e " Failed to register warp account. Script aborted. " && exit 1
      
      if ! grep -sq 'PrivateKey' $REGISTE_FILE_PATH; then
        unset CF_API_REGISTE API_DEVICE_ID API_ACCESS_TOKEN API_PRIVATEKEY API_TYPE
        rm -f $REGISTE_FILE_PATH
        CF_API_REGISTE="$(curl -m5 -sL "https://${WARP_API_URL}/?run=register")"
        
        if grep -q 'private_key' <<< "$CF_API_REGISTE"; then
          local API_DEVICE_ID=$(expr "$CF_API_REGISTE " | grep -m1 'id' | cut -d\" -f4)
          local API_ACCESS_TOKEN=$(expr "$CF_API_REGISTE " | grep '"token' | cut -d\" -f4)
          local API_PRIVATEKEY=$(expr "$CF_API_REGISTE " | grep 'private_key' | cut -d\" -f4)
          local API_TYPE=$(expr "$CF_API_REGISTE " | grep 'account_type' | cut -d\" -f4)
          
          if [[ "$REGISTE_FILE_PATH" =~ '/opt/warp-go' ]]; then
            cat > $REGISTE_FILE_PATH << ABC
[Account]
Device = $API_DEVICE_ID
PrivateKey = $API_PRIVATEKEY
Token = $API_ACCESS_TOKEN
Type = $API_TYPE

[Device]
Name = WARP
MTU  = 1280

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
Endpoint = 162.159.193.10:1701
KeepAlive = 30
# AllowedIPs = 0.0.0.0/0
# AllowedIPs = ::/0
ABC
          elif [[ "$REGISTE_FILE_PATH" =~ '/etc/wireguard' ]]; then
            expr "$CF_API_REGISTE" > $REGISTE_FILE_PATH
          fi

          # 如果文件有问题，则删除该注册文件
          if grep -sqE 'Account|account_type' $REGISTE_FILE_PATH; then
            grep -sq Account $REGISTE_FILE_PATH && echo -e "\n[Script]\nPostUp =\nPostDown =" >> $REGISTE_FILE_PATH && sed -i 's/\r//' $REGISTE_FILE_PATH
          else
            rm -f $REGISTE_FILE_PATH
          fi

          # 如是 plus 账户，升级账户
          if [[ -n "$LICENSE" && -n "$NAME" ]]; then
            fetch_account_information $REGISTE_FILE_PATH
            curl -m5 -sL "https://${WARP_API_URL}/?run=license&device_id=${WARP_DEVICE_ID}&token=${WARP_TOKEN}&license=${LICENSE}"
            curl -m5 -sL "https://${WARP_API_URL}/?run=name&device_id=${WARP_DEVICE_ID}&token=${WARP_TOKEN}&device_name=$NAME" >/dev/null 2>&1
          fi
        fi
      fi
    done
  }

  warp_restart() {
    INTERFACE=wgcf
    case "$INTERFACE" in
      # warp-go 处理方案
      WARP)
        [ -s /opt/warp-go/License ] && local LICENSE=$(cat /opt/warp-go/License)
        [[ -n "$LICENSE" && -s /opt/warp-go/Device_Name ]] && local NAME=$(cat /opt/warp-go/Device_Name)
        cp -f /opt/warp-go/warp.conf{,.tmp1}
        registe_api /opt/warp-go/warp.conf.tmp2 $LICENSE $NAME
        sed -i '1,6!d' /opt/warp-go/warp.conf.tmp2
        tail -n +7 /opt/warp-go/warp.conf.tmp1 >> /opt/warp-go/warp.conf.tmp2
        mv /opt/warp-go/warp.conf.tmp2 /opt/warp-go/warp.conf
        fetch_account_information /opt/warp-go/warp.conf.tmp1
        curl -m5 -sL "https://${WARP_API_URL}/?run=cancel&device_id=${WARP_DEVICE_ID}&token=${WARP_TOKEN}"
        rm -f /opt/warp-go/warp.conf.tmp*
        systemctl restart warp-go
        sleep 10
        ;;

      # warp 处理方案
      warp)
        [ -s /etc/wireguard/license ] && local LICENSE=$(cat /etc/wireguard/license)
        [ -n "$LICENSE" ] && grep -sq 'Device name' /etc/wireguard/info.log && local NAME=$(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }')
        mv -f /etc/wireguard/warp-account.conf{,.tmp}
        wg-quick down warp >/dev/null 2>&1
        registe_api /etc/wireguard/warp-account.conf $LICENSE $NAME
        local PRIVATEKEY="$(grep 'private_key' /etc/wireguard/warp-account.conf | cut -d\" -f4)"
        local ADDRESS6="$(grep '"v6.*"$' /etc/wireguard/warp-account.conf | cut -d\" -f4)"
        local RESERVED="$(grep 'client_id' /etc/wireguard/warp-account.conf | cut -d\" -f4 | base64 -d | xxd -p | fold -w2 | while read HEX; do printf '%d ' "0x${HEX}"; done | awk '{print "["$1", "$2", "$3"]"}')"
        sed -i "s#\(PrivateKey[ ]\+=[ ]\+\).*#\1$PRIVATEKEY#g; s#\(Address[ ]\+=[ ]\+\).*\(/128\)#\1$ADDRESS6\2#g; s#\(.*Reserved[ ]\+=[ ]\+\).*#\1$RESERVED#g" /etc/wireguard/warp.conf
        fetch_account_information /etc/wireguard/warp-account.conf.tmp
        curl -m5 -sL "https://${WARP_API_URL}/?run=cancel&device_id=${WARP_DEVICE_ID}&token=${WARP_TOKEN}" >/dev/null 2>&1
        rm -f /etc/wireguard/warp-account.conf.tmp
        wg-quick up warp >/dev/null 2>&1
        sleep 10
        [[ "$(ss -nltp | awk -F\" '{print $2}' | sed '/^$/d')" =~ 'dnsmasq' ]] && ( systemctl restart dnsmasq >/dev/null 2>&1; sleep 2 )
        ;;

      # wgcf 处理方案
      wgcf)
        systemctl restart wg-quick@wgcf
        sleep 2
        [[ "$(ss -nltp | awk -F\" '{print $2}' | sed '/^$/d')" =~ 'dnsmasq' ]] && systemctl restart dnsmasq >/dev/null 2>&1
        sleep 2
        ;;
    esac
    check_ip
  }

  client_restart() {
    local CLIENT_MODE=$(warp-cli --accept-tos settings | awk '/Mode:/{for (i=0; i<NF; i++) if ($i=="Mode:") {print $(i+1)}}')
    if [ "$CLIENT_MODE" = 'Warp' ]; then
      [ "$NIC" = '-ks4m8 --interface CloudflareWARP' ] && IP_RULE='-4' || IP_RULE='-6'
      warp-cli --accept-tos delete >/dev/null 2>&1
      ip $IP_RULE rule delete from 172.16.0.2/32 lookup 51820
      ip $IP_RULE rule delete table main suppress_prefixlength 0
      warp-cli --accept-tos register >/dev/null 2>&1 &&
      [ -s /etc/wireguard/license ] && warp-cli --accept-tos set-license $(cat /etc/wireguard/license) >/dev/null 2>&1
      sleep 10
      ip $IP_RULE rule add from 172.16.0.2 lookup 51820
      ip $IP_RULE route add default dev CloudflareWARP table 51820
      ip $IP_RULE rule add table main suppress_prefixlength 0
    elif [ "$CLIENT_MODE" = 'WarpProxy' ]; then
      warp-cli --accept-tos delete >/dev/null 2>&1
      warp-cli --accept-tos register >/dev/null 2>&1 &&
      [ -s /etc/wireguard/license ] && warp-cli --accept-tos set-license $(cat /etc/wireguard/license) >/dev/null 2>&1
      sleep 10
    fi
    check_ip
  }

  wireproxy_restart() { 
    systemctl restart wireproxy
    sleep 5
    check_ip
  }

  check_streaming() {
    # 执行一次检测
    local CHECK_RESULT=$(./check.sh -R 0 | grep -v "Not Currently Supported")
    
    # 初始化结果数组
    declare -A REGION

    # 检查每个配置的流媒体服务
    for service in $STREAMING_SERVICES; do
      case $service in
        "Netflix")
          # 从后往前查找第一个非 "Not Currently Supported" 的结果
          local netflix_result=$(echo "$CHECK_RESULT" | tac | grep -m1 "Netflix:")
          if [ -n "$netflix_result" ] && echo "$netflix_result" | grep -q "Yes"; then
            R["Netflix"]="$UNLOCK_STATUS"
            REGION["Netflix"]=$(echo "$CHECK_RESULT" | tac | grep -m1 "Netflix Region:" | awk '{print $3}')
          else
            R["Netflix"]="$NOT_UNLOCK_STATUS"
          fi
          ;;
        "Disney+")
          local disney_result=$(echo "$CHECK_RESULT" | tac | grep -m1 "Disney+:")
          if [ -n "$disney_result" ] && echo "$disney_result" | grep -q "Yes"; then
            R["Disney+"]="$UNLOCK_STATUS"
          else
            R["Disney+"]="$NOT_UNLOCK_STATUS"
          fi
          ;;
        "AmazonPrimeVideo")
          local prime_result=$(echo "$CHECK_RESULT" | tac | grep -m1 "Amazon Prime Video:")
          if [ -n "$prime_result" ] && echo "$prime_result" | grep -q "Yes"; then
            R["AmazonPrimeVideo"]="$UNLOCK_STATUS"
          else
            R["AmazonPrimeVideo"]="$NOT_UNLOCK_STATUS"
          fi
          ;;
        "YouTubePremium")
          local youtube_result=$(echo "$CHECK_RESULT" | tac | grep -m1 "YouTube Premium:")
          if [ -n "$youtube_result" ] && echo "$youtube_result" | grep -q "Yes"; then
            R["YouTubePremium"]="$UNLOCK_STATUS"
          else
            R["YouTubePremium"]="$NOT_UNLOCK_STATUS"
          fi
          ;;
      esac
    done

    # 记录每个服务的结果
    for service in $STREAMING_SERVICES; do
      if [ -n "${R[$service]}" ]; then
        if [ "$service" = "Netflix" ] && [ -n "${REGION[$service]}" ]; then
          CONTENT="$service: ${R[$service]} (Region: ${REGION[$service]})."
        else
          CONTENT="$service: ${R[$service]}."
        fi
        log_message
        case $service in
          "Netflix")
            [[ -n "$CUSTOM" ]] && [[ "${R[$service]}" != $(sed -n 1p /usr/bin/status.log) ]] && tg_message
            sed -i "1s/.*/${R[$service]}/" /usr/bin/status.log
            ;;
          "Disney+")
            [[ -n "$CUSTOM" ]] && [[ "${R[$service]}" != $(sed -n 2p /usr/bin/status.log) ]] && tg_message
            sed -i "2s/.*/${R[$service]}/" /usr/bin/status.log
            ;;
          "AmazonPrimeVideo")
            [[ -n "$CUSTOM" ]] && [[ "${R[$service]}" != $(sed -n 3p /usr/bin/status.log) ]] && tg_message
            sed -i "3s/.*/${R[$service]}/" /usr/bin/status.log
            ;;
          "YouTubePremium")
            [[ -n "$CUSTOM" ]] && [[ "${R[$service]}" != $(sed -n 4p /usr/bin/status.log) ]] && tg_message
            sed -i "4s/.*/${R[$service]}/" /usr/bin/status.log
            ;;
        esac
      fi
    done
  }

  while true; do
    check_ip
    CONTENT='Script runs.'
    log_message
    UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x6*4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36"
    # 初始化结果数组
    declare -A R
    check_streaming
    until [[ ! ${R[*]} =~ "$NOT_UNLOCK_STATUS" ]]; do
      $RESTART
      declare -A R
      check_streaming
    done
    sleep 30m
  done
fi