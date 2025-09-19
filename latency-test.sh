#!/bin/bash

# ==============================================================================
#                  宇哥真实延迟测试脚本
# ==============================================================================

# --- 配置 ---
NUM_TESTS=5
LOG_FILE="latency_log.txt"
CONNECT_TIMEOUT="10"
PREDEFINED_TARGETS=(
    "www.google.com"
    "www.youtube.com"
    "www.googlevideo.com"
    "www.cloudflare.com"
    "www.github.com"
    "www.baidu.com"
)

# --- 颜色定义
COLOR_GREEN=$'\033[0;32m'
COLOR_RED=$'\033[0;31m'
COLOR_YELLOW=$'\033[0;33m'
COLOR_BLUE=$'\033[0;34m'
COLOR_PURPLE=$'\033[0;35m'
COLOR_CYAN=$'\033[0;36m'
COLOR_BOLD=$'\033[1m'
COLOR_RESET=$'\033[0m'

# --- 函数：执行核心测试逻辑 ---
run_test() {
    local TARGET_URL="$1"
    
    case "$TARGET_URL" in
      http://* | https://*) ;;
      *) TARGET_URL="https://"$TARGET_URL ;;
    esac

    clear
    printf "============================================================\n"
    printf "  %s正在测试: %s%s%s\n" "${COLOR_BLUE}" "${COLOR_BOLD}" "${TARGET_URL}" "${COLOR_RESET}"
    printf "============================================================\n"
    
    local total_duration_ms=0
    local min_time_ms="999999"
    local max_time_ms="0"
    local successful_runs=0

    for i in $(seq 1 $NUM_TESTS); do
        local CACHE_BUST_URL
        CACHE_BUST_URL="${TARGET_URL}?_t=$(date +%s%N)"
        
        local CURL_FORMAT="%{time_connect},%{time_pretransfer},%{time_total}"
        
        local response
        response=$(curl -s \
                     -H "Cache-Control: no-cache" \
                     -H "Pragma: no-cache" \
                     --connect-timeout "${CONNECT_TIMEOUT}" \
                     -o /dev/null \
                     -w "${CURL_FORMAT}" \
                     "${CACHE_BUST_URL}")
        
        if [ $? -ne 0 ] || [ -z "$response" ]; then
            printf "  第 %d/%d 次: %s❌ 测试失败 (无法连接或超时)%s\n" "$i" "$NUM_TESTS" "${COLOR_RED}" "${COLOR_RESET}"
            continue
        fi
        
        successful_runs=$((successful_runs + 1))
        
        local connect_time_s tls_time_s run_time_s
        connect_time_s=$(echo "$response" | cut -d, -f1)
        tls_time_s=$(echo "$response" | cut -d, -f2)
        run_time_s=$(echo "$response" | cut -d, -f3)

        local connect_time_ms tls_time_ms run_time_ms
        connect_time_ms=$(awk -v time="$connect_time_s" 'BEGIN { printf "%.0f", time * 1000 }')
        tls_time_ms=$(awk -v time="$tls_time_s" 'BEGIN { printf "%.0f", time * 1000 }')
        run_time_ms=$(awk -v time="$run_time_s" 'BEGIN { printf "%.0f", time * 1000 }')

        printf "  第 %d/%d 次: 总延迟 = %s%s ms%s (连接: %s ms, TLS: %s ms)\n" "$i" "$NUM_TESTS" "${COLOR_BOLD}" "$run_time_ms" "${COLOR_RESET}" "$connect_time_ms" "$tls_time_ms"
        
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"),${TARGET_URL},${i},${connect_time_s},${tls_time_s},${run_time_s}" >> "$LOG_FILE"
        
        total_duration_ms=$((total_duration_ms + run_time_ms))
        if [ "$run_time_ms" -lt "$min_time_ms" ]; then min_time_ms=$run_time_ms; fi
        if [ "$run_time_ms" -gt "$max_time_ms" ]; then max_time_ms=$run_time_ms; fi
    done

    printf -- "------------------------------------------------------------\n"
    if [ "$successful_runs" -gt 0 ]; then
        local avg_time_ms
        avg_time_ms=$(awk -v total="$total_duration_ms" -v runs="$successful_runs" 'BEGIN { printf "%.2f", total / runs }')
        printf "  📊 %s统计结果 (基于 %d 次成功测试):%s\n" "${COLOR_BOLD}" "$successful_runs" "${COLOR_RESET}"
        printf "  - 最快 (Min): \t%s%s ms%s\n" "${COLOR_GREEN}" "${min_time_ms}" "${COLOR_RESET}"
        printf "  - 最慢 (Max): \t%s%s ms%s\n" "${COLOR_RED}" "${max_time_ms}" "${COLOR_RESET}"
        printf "  - 平均 (Avg): \t%s%s ms%s\n" "${COLOR_YELLOW}" "${avg_time_ms}" "${COLOR_RESET}"
    else
        printf "  📊 %s所有测试均失败,无法生成统计数据。%s\n" "${COLOR_RED}" "${COLOR_RESET}"
    fi
    printf "============================================================\n"
}

# --- 函数：显示主菜单 ---
show_menu() {
    clear
    printf "%s%s🚀 欢迎使用宇哥真实延迟测试脚本 🚀%s\n" "${COLOR_PURPLE}" "${COLOR_BOLD}" "${COLOR_RESET}"
    printf -- "----------------------------------\n"
    printf "%s请选择一个要测试的目标:%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    
    for i in "${!PREDEFINED_TARGETS[@]}"; do
        printf "  %s%2d)%s %s\n" "${COLOR_YELLOW}" $((i+1)) "${COLOR_RESET}" "${PREDEFINED_TARGETS[$i]}"
    done
    
    printf -- "----------------------------------\n"
    printf "  %sm)%s 手动输入域名 (Manual Input)\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf "  %sq)%s 退出 (Quit)\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf -- "----------------------------------\n"
}

# --- 主循环 ---
if [ ! -f "$LOG_FILE" ]; then
    echo "Timestamp,Target,Run,Connect_Time_s,TLS_Time_s,Total_Time_s" > "$LOG_FILE"
fi

while true; do
    show_menu
    read -rp "请输入您的选择 [1-$((${#PREDEFINED_TARGETS[@]})), m, q]: " choice

    case "$choice" in
        [qQ])
            printf "\n%s感谢使用,再见！%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
            exit 0
            ;;
        [mM])
            read -rp "请输入您想测试的域名: " MANUAL_URL
            if [ -n "$MANUAL_URL" ]; then
                run_test "$MANUAL_URL"
            else
                printf "%s输入不能为空,请重试。%s\n" "${COLOR_RED}" "${COLOR_RESET}"; sleep 2
            fi
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#PREDEFINED_TARGETS[@]}" ]; then
                SELECTED_TARGET="${PREDEFINED_TARGETS[$((choice-1))]}"
                run_test "$SELECTED_TARGET"
            else
                printf "%s无效的选择 '%s',请重试。%s\n" "${COLOR_RED}" "${choice}" "${COLOR_RESET}"; sleep 2
            fi
            ;;
    esac

    if [[ ! "$choice" =~ [qQ] ]]; then
        read -n 1 -s -r -p $'\n按任意键返回主菜单...'
    fi
done