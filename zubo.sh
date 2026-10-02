#!/bin/bash
# zubo.sh - 组播源检测与测速脚本（城市并发 + 测速并发 + FOFA 可选）

# ============================================================
# 可调参数（环境变量可覆盖）
# ============================================================
NC_JOBS=${NC_JOBS:-50}              # 单城市内：连通性检测并发
SPEED_JOBS=${SPEED_JOBS:-10}        # 单城市内：测速并发（别太大，避免抢带宽失真）
CITY_JOBS=${CITY_JOBS:-3}           # 城市级并发（选项0时生效）
CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT:-5}
CURL_MAX_TIME=${CURL_MAX_TIME:-40}

# ============================================================
# FOFA API 可选模块（默认关闭，设置以下环境变量后启用）
#   用法示例：
#     FOFA_EMAIL=you@x.com FOFA_KEY=xxxx FOFA_QBASE64=InVkcHh5... bash zubo.sh 7
# ============================================================
FOFA_ENABLE=${FOFA_ENABLE:-0}       # 1=启用，0=关闭
FOFA_EMAIL=${FOFA_EMAIL:-}
FOFA_KEY=${FOFA_KEY:-}
FOFA_QBASE64=${FOFA_QBASE64:-}
FOFA_SIZE=${FOFA_SIZE:-100}

# ============================================================
# 0. 目录准备
# ============================================================
mkdir -p ip txt tmp

# ============================================================
# 1. 参数 / 交互
# ============================================================
if [ $# -eq 0 ]; then
    echo "开始测试······"
    echo "在5秒内输入编号可选择城市（0=测试全部）"
    echo "完整列表见脚本 case 分支，例如："
    echo "  1.浙江电信  2.浙江联通  3.江苏电信  7.湖北电信 33.天津联通"
    echo "  0 = 并发测试全部 71 个城市"
    if ! read -t 5 -p "超时未输入,将按默认设置测试全部: " city_choice || [ -z "$city_choice" ]; then
        echo "未检测到输入,默认测试全部"
        city_choice=0
    fi
else
    city_choice=$1
fi

# ============================================================
# 2. 城市与流地址映射
# ============================================================
case $city_choice in
    1)  city="浙江电信";     stream="udp/233.50.201.100:5140" ;;
    2)  city="浙江联通";     stream="rtp/233.50.201.118:5140" ;;
    3)  city="江苏电信";     stream="udp/239.49.8.19:9614" ;;
    4)  city="河北电信";     stream="rtp/239.254.200.174:6000" ;;
    5)  city="河北联通";     stream="rtp/239.253.92.154:6011" ;;
    6)  city="河北移动";     stream="rtp/239.255.2.2:8000" ;;
    7)  city="湖北电信";     stream="rtp/239.69.1.102:10250" ;;
    8)  city="湖北联通";     stream="rtp/228.0.0.60:6108" ;;
    9)  city="河南电信";     stream="rtp/239.16.20.21:10210" ;;
    10) city="河南联通";     stream="rtp/225.1.4.98:1127" ;;
    11) city="河南移动";     stream="rtp/225.1.4.73:1102" ;;
    12) city="广东电信";     stream="udp/239.77.1.152:5146" ;;
    13) city="广东联通";     stream="udp/239.0.1.3:8008" ;;
    14) city="广东移动";     stream="rtp/239.20.0.104:2006" ;;
    15) city="北京电信";     stream="rtp/225.1.8.21:8002" ;;
    16) city="北京联通";     stream="rtp/239.3.1.241:8000" ;;
    17) city="北京移动";     stream="rtp/228.1.1.28:8008" ;;
    18) city="湖南电信";     stream="udp/239.76.246.151:1234" ;;
    19) city="湖南联通";     stream="rtp/228.1.1.1:6001" ;;
    20) city="湖南移动";     stream="rtp/239.1.0.105:1025" ;;
    21) city="辽宁电信";     stream="rtp/239.33.5.2:22580" ;;
    22) city="辽宁联通";     stream="rtp/232.0.0.126:1234" ;;
    23) city="辽宁移动";     stream="rtp/232.11.0.90:20159" ;;
    24) city="四川电信";     stream="rtp/239.94.0.11:5140" ;;
    25) city="四川联通";     stream="rtp/239.0.0.10:5140" ;;
    26) city="四川移动";     stream="rtp/239.11.0.65:5140" ;;
    27) city="山东电信";     stream="udp/239.21.1.87:5002" ;;
    28) city="山东联通";     stream="rtp/239.253.254.78:8000" ;;
    29) city="山东移动";     stream="rtp/239.253.2.189:9128" ;;
    30) city="陕西电信";     stream="rtp/239.111.205.35:5140" ;;
    31) city="陕西移动";     stream="rtp/239.10.3.34:9000" ;;
    32) city="天津电信";     stream="rtp/239.5.1.1:5000" ;;
    33) city="天津联通";     stream="udp/225.1.1.111:5002" ;;
    34) city="天津移动";     stream="rtp/225.2.1.120:5000" ;;
    35) city="广西电信";     stream="udp/239.81.0.107:4056" ;;
    36) city="贵州电信";     stream="rtp/238.255.2.1:5999" ;;
    37) city="贵州联通";     stream="rtp/239.254.22.105:7000" ;;
    38) city="贵州移动";     stream="rtp/239.10.2.122:5599" ;;
    39) city="山西电信";     stream="rtp/239.1.1.7:8007" ;;
    40) city="山西联通";     stream="rtp/226.0.2.152:9128" ;;
    41) city="山西移动";     stream="rtp/226.0.1.157:3086" ;;
    42) city="上海电信";     stream="rtp/233.18.204.20:5140" ;;
    43) city="上海联通";     stream="rtp/238.200.200.133:5540" ;;
    44) city="上海移动";     stream="rtp/225.0.0.220:6140" ;;
    45) city="福建电信";     stream="rtp/239.61.2.132:8708" ;;
    46) city="福建联通";     stream="rtp/239.255.40.149:8208" ;;
    47) city="江西电信";     stream="udp/239.252.220.63:5140" ;;
    48) city="安徽电信";     stream="rtp/238.1.79.27:4328" ;;
    49) city="宁夏电信";     stream="rtp/239.121.4.94:8538" ;;
    50) city="宁夏联通";     stream="rtp/224.168.68.56:6000" ;;
    51) city="重庆电信";     stream="rtp/235.254.196.249:1268" ;;
    52) city="重庆联通";     stream="udp/225.0.4.187:7980" ;;
    53) city="重庆移动";     stream="rtp/239.253.112.17:9000" ;;
    54) city="海南电信";     stream="rtp/239.253.64.120:5140" ;;
    55) city="海南联通";     stream="rtp/239.254.96.82:7640" ;;
    56) city="海南移动";     stream="rtp/239.10.0.12:9876" ;;
    57) city="黑龙江联通";   stream="rtp/229.58.190.150:5000" ;;
    58) city="黑龙江移动";   stream="rtp/239.0.2.29:5140" ;;
    59) city="甘肃电信";     stream="udp/239.255.30.249:8231" ;;
    60) city="甘肃联通";     stream="rtp/239.255.36.70:8231" ;;
    61) city="新疆电信";     stream="udp/238.125.3.174:5140" ;;
    62) city="内蒙古电信";   stream="rtp/239.29.0.2:5000" ;;
    63) city="内蒙古联通";   stream="udp/239.125.1.127:4130" ;;
    64) city="吉林电信";     stream="rtp/239.37.0.231:5540" ;;
    65) city="吉林联通";     stream="rtp/239.253.142.12:3000" ;;
    66) city="云南电信";     stream="rtp/239.200.200.145:8840" ;;
    67) city="云南联通";     stream="rtp/225.0.1.88:5000" ;;
    68) city="云南移动";     stream="rtp/228.0.0.101:5051" ;;
    69) city="青海电信";     stream="rtp/239.120.1.119:8260" ;;
    70) city="青海联通";     stream="rtp/239.120.2.145:5141" ;;
    71) city="西藏电信";     stream="rtp/239.105.0.102:5140" ;;
    0)
        # ---- 城市级并发 ----
        echo "并发测试全部 71 个城市（城市并发=$CITY_JOBS）..."
        # 主日志目录
        mkdir -p tmp/city_logs
        # 每个城市一个子任务，用 xargs -P 控制并发
        seq 1 71 | xargs -I{} -P "$CITY_JOBS" bash -c '
            opt="$1"
            log="tmp/city_logs/city_${opt}.log"
            # 子进程内自己控制单城市内的并发数
            NC_JOBS='"$NC_JOBS"' SPEED_JOBS='"$SPEED_JOBS"' \
                bash "$0" "$opt" > "$log" 2>&1
            echo "[城市 $opt] 完成 -> $log"
        ' _ {}
        echo "全部城市测试完成，日志在 tmp/city_logs/"
        exit 0
        ;;
    *)
        echo "无效选项: $city_choice" >&2
        exit 1
        ;;
esac

# ============================================================
# 3. 单城市变量准备
# ============================================================
ts=$(date +%m%d%H%M)
workdir="tmp/${city}_${ts}"
mkdir -p "$workdir"
ipfile="ip/${city}_ip.txt"
good_ip="ip/good_${city}_ip.txt"
speedlog="speedtest_${city}_${ts}.log"

echo "======== 开始检索 ${city} ========"

# ============================================================
# 4. 汇总待检测 IP（本地 + 可选 FOFA）
# ============================================================
tmp_ipfile=$(mktemp)
: > "$tmp_ipfile"

if [ -f "$ipfile" ]; then
    echo "从 '${ipfile}' 读取 IP 并添加到检测列表"
    cat "$ipfile" >> "$tmp_ipfile"
else
    echo "警告: '${ipfile}' 不存在，跳过本地 IP 列表"
fi

# ---- 可选：FOFA API ----
if [ "$FOFA_ENABLE" = "1" ]; then
    if [ -n "$FOFA_EMAIL" ] && [ -n "$FOFA_KEY" ] && [ -n "$FOFA_QBASE64" ]; then
        echo "从 FOFA API 拉取（size=$FOFA_SIZE）..."
        fofa_api="https://fofa.info/api/v1/search/all"
        resp=$(curl -s --connect-timeout 10 --max-time 30 \
            "${fofa_api}?email=${FOFA_EMAIL}&key=${FOFA_KEY}&qbase64=${FOFA_QBASE64}&size=${FOFA_SIZE}&fields=host")
        # 简单校验返回是否含错误
        if echo "$resp" | grep -q '"error":true'; then
            echo "FOFA API 返回错误："
            echo "$resp" | head -c 500
            echo
        else
            # 从 JSON 中提取 host 字段（形如 1.2.3.4:8080）
            echo "$resp" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' \
                | sort -u >> "$tmp_ipfile"
            echo "FOFA 拉取完成。"
        fi
    else
        echo "FOFA_ENABLE=1 但缺少 FOFA_EMAIL / FOFA_KEY / FOFA_QBASE64，跳过。"
    fi
fi

sort -u "$tmp_ipfile" | sed '/^\s*$/d' > "$ipfile"
rm -f "$tmp_ipfile"

if [ ! -s "$ipfile" ]; then
    echo "没有可检测的 IP，退出。"
    rmdir "$workdir" 2>/dev/null
    exit 1
fi

# ============================================================
# 5. 连通性检测（单城市内并发 nc）
# ============================================================
: > "$good_ip"
echo "开始连通性检测（并发 $NC_JOBS）..."

export workdir

check_one() {
    ip="$1"
    [ -z "$ip" ] && return
    host=${ip%:*}
    port=${ip##*:}
    if nc -z -w 1 "$host" "$port" 2>/dev/null; then
        echo "$ip" >> "$workdir/nc_ok.$$"
    fi
}
export -f check_one

xargs -a "$ipfile" -I{} -P "$NC_JOBS" bash -c 'check_one "$@"' _ {}

cat "$workdir"/nc_ok.* 2>/dev/null | sort -u > "$good_ip"
rm -f "$workdir"/nc_ok.*

lines=$(wc -l < "$good_ip" | tr -d ' ')
echo "连接成功 $lines 个,开始测速（并发 $SPEED_JOBS）······"

if [ "$lines" -eq 0 ]; then
    echo "没有可连通 IP，退出。"
    rm -f "$good_ip"
    rmdir "$workdir" 2>/dev/null
    exit 1
fi

# ============================================================
# 6. 测速（单城市内并发 curl）
# ============================================================
: > "$speedlog"

export STREAM="$stream"
export CURL_CONNECT_TIMEOUT CURL_MAX_TIME

speed_one() {
    ip="$1"
    [ -z "$ip" ] && return
    url="http://$ip/$STREAM"
    speed_bps=$(curl -o /dev/null -s -w "%{speed_download}" \
                     --connect-timeout "$CURL_CONNECT_TIMEOUT" \
                     --max-time "$CURL_MAX_TIME" "$url" 2>/dev/null)
    [ -z "$speed_bps" ] && speed_bps=0
    human=$(awk -v s="$speed_bps" 'BEGIN{
        if (s >= 1048576)      printf "%.2f M", s/1048576;
        else if (s >= 1024)    printf "%.2f k", s/1024;
        else                   printf "%.2f B", s;
    }')
    echo -e "${speed_bps}\t${human}\t${ip}" >> "$workdir/spd.$$"
}
export -f speed_one

xargs -a "$good_ip" -I{} -P "$SPEED_JOBS" bash -c 'speed_one "$@"' _ {}

cat "$workdir"/spd.* > "$speedlog" 2>/dev/null
rm -f "$workdir"/spd.*

total=$(wc -l < "$speedlog" | tr -d ' ')
echo "测速完成，共 $total 条结果。"

# ============================================================
# 7. 排序并生成结果
# ============================================================
echo "测速结果排序"
sort -k1,1nr "$speedlog" > "${speedlog}.sorted"

echo "----- 测速排行（前10）-----"
head -n 10 "${speedlog}.sorted" | awk -F'\t' '{printf "%-22s %s\n", $3, $2}'
echo "---------------------------"

top3=$(head -n 3 "${speedlog}.sorted" | awk -F'\t' '{print $3}')
ip1=$(echo "$top3" | sed -n '1p')
ip2=$(echo "$top3" | sed -n '2p')
ip3=$(echo "$top3" | sed -n '3p')

rm -f "$speedlog" "${speedlog}.sorted"

if [ -z "$ip1" ]; then
    echo "没有可用 IP，跳过生成。"
    rmdir "$workdir" 2>/dev/null
    exit 1
fi

# ============================================================
# 8. 生成对应城市的 txt
# ============================================================
program="template/template_${city}.txt"
if [ ! -f "$program" ]; then
    echo "模板文件不存在: $program，跳过生成。"
    rmdir "$workdir" 2>/dev/null
    exit 1
fi

out="txt/${city}.txt"
: > "$out"
[ -n "$ip1" ] && { echo "${city}-组播1,#genre#" >> "$out"; sed "s/ipipip/$ip1/g" "$program" >> "$out"; }
[ -n "$ip2" ] && { echo "${city}-组播2,#genre#" >> "$out"; sed "s/ipipip/$ip2/g" "$program" >> "$out"; }
[ -n "$ip3" ] && { echo "${city}-组播3,#genre#" >> "$out"; sed "s/ipipip/$ip3/g" "$program" >> "$out"; }

grep -v 'ipipip' "$out" > "${out}.tmp" && mv "${out}.tmp" "$out"

rmdir "$workdir" 2>/dev/null
echo "${city} 测试完成，生成可用文件：'${out}'"