#!/bin/bash
set -e
set -o pipefail

#================================================================================
#
#           Linux 网络性能优化脚本（只适用于debian）
#
#================================================================================

# --- 确保以 Root 权限运行 ---
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本必须以 root 权限运行。" 
   exit 1
fi

# --- 全局变量与配置 ---
SYSCTL_CONF_FILE="/etc/sysctl.d/99-custom-network-tuning.conf"
LIMITS_CONF_FILE="/etc/security/limits.d/99-custom-limits.conf"
TEMP_SYSCTL_FILE=$(mktemp)

# 定义用于管理配置块的标记
SYSCTL_MARKER_START="# --- BEGIN Kernel Tuning by Script ---"
SYSCTL_MARKER_END="# --- END Kernel Tuning by Script ---"
LIMITS_MARKER_START="# --- BEGIN Ulimit Settings by Script ---"
LIMITS_MARKER_END="# --- END Ulimit Settings by Script ---"

# --- 辅助函数 ---
apply_sysctl_value() {
    local key="$1"
    local target_value="$2"
    local proc_path="/proc/sys/${key//./\/}"
    if [ -f "$proc_path" ]; then
        echo "$key = $target_value" >> "$TEMP_SYSCTL_FILE"
    fi
}

# --- 主逻辑 ---

# 根据内存大小确定优化策略
mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
mem_total_mb=$((mem_total_kb / 1024))
strategy="dedicated_proxy_le_2gb"
if [ "$mem_total_mb" -gt 2000 ]; then
    strategy="high_performance_gt_2gb"
fi

# 定义参数模板
declare -A sysctl_values
declare ulimit_n

if [ "$strategy" == "dedicated_proxy_le_2gb" ]; then
    ### 策略1: <= 2GB 内存的专用代理服务器 ###
    # 此策略专为内存有限但带宽高的代理/网关服务器设计
    ulimit_n=1048576
    sysctl_values=(
        # --- 连接队列 ---
        ["net.core.somaxconn"]="65535"
        ["net.ipv4.tcp_max_syn_backlog"]="65535"
        ["net.core.netdev_max_backlog"]="65535"
        # --- TCP 缓冲区 (32MB) ---
        ["net.core.rmem_max"]="33554432"
        ["net.core.wmem_max"]="33554432"
        ["net.ipv4.tcp_rmem"]="4096 87380 33554432"
        ["net.ipv4.tcp_wmem"]="4096 87380 33554432"
        # --- TCP 连接管理 ---
        ["net.ipv4.tcp_fin_timeout"]="30"
        ["net.ipv4.tcp_keepalive_time"]="300"
        ["net.ipv4.tcp_keepalive_intvl"]="60"
        ["net.ipv4.tcp_keepalive_probes"]="5"
        ["net.ipv4.tcp_tw_reuse"]="1"
    )
else # high_performance_gt_2gb
    ### 策略2: > 2GB 内存的高性能通用服务器 ###
    # 适用于内存充裕，追求极致性能的服务器
    ulimit_n=1048576
    sysctl_values=(
        # --- 连接队列 ---
        ["net.core.somaxconn"]="65535"
        ["net.ipv4.tcp_max_syn_backlog"]="65535"
        ["net.core.netdev_max_backlog"]="65535"
        # --- TCP 缓冲区 (64MB) ---
        ["net.core.rmem_max"]="67108864"
        ["net.core.wmem_max"]="67108864"
        ["net.ipv4.tcp_rmem"]="4096 87380 67108864"
        ["net.ipv4.tcp_wmem"]="4096 87380 67108864"
        # --- TCP 连接管理 ---
        ["net.ipv4.tcp_fin_timeout"]="30"
        ["net.ipv4.tcp_keepalive_time"]="300"
        ["net.ipv4.tcp_keepalive_intvl"]="30"
        ["net.ipv4.tcp_keepalive_probes"]="5"
        ["net.ipv4.tcp_tw_reuse"]="1"
    )
fi

# ==============================================================================
#      通用参数 (对所有策略生效)
# ==============================================================================

# 智能处理 fs.file-max, 确保足够大
current_file_max=$(sysctl -n fs.file-max)
target_file_max=$(( ulimit_n * 10 ))
if (( current_file_max < target_file_max )); then
    sysctl_values["fs.file-max"]="$target_file_max"
fi

# 提升连接建立速度
sysctl_values["net.ipv4.tcp_fastopen"]="3"

# 安全与系统响应
sysctl_values["net.ipv4.conf.all.accept_redirects"]="0"
sysctl_values["net.ipv4.conf.all.send_redirects"]="0"
sysctl_values["net.ipv6.conf.all.accept_redirects"]="0"
sysctl_values["vm.swappiness"]="10"

# 主动尝试加载并启用 BBR
bbr_status_message="BBR: 内核不支持或模块加载失败。"
modprobe tcp_bbr >/dev/null 2>&1
if [[ $(sysctl -n net.ipv4.tcp_available_congestion_control) == *"bbr"* ]]; then
    sysctl_values["net.core.default_qdisc"]="fq"
    sysctl_values["net.ipv4.tcp_congestion_control"]="bbr"
    mkdir -p /etc/modules-load.d/
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    bbr_status_message="BBR: 已成功加载模块并配置启用。"
fi

# --- 开始应用配置 ---

for key in "${!sysctl_values[@]}"; do
    apply_sysctl_value "$key" "${sysctl_values[$key]}"
done

echo "正在写入内核配置文件: $SYSCTL_CONF_FILE"
{
    echo ""
    echo "$SYSCTL_MARKER_START"
    echo "# Strategy: $strategy, Applied: $(date '+%F %T')"
    cat "$TEMP_SYSCTL_FILE"
    echo "$SYSCTL_MARKER_END"
} > "$SYSCTL_CONF_FILE"
rm "$TEMP_SYSCTL_FILE"

# 使用正确的命令使所有 .d 目录下的配置生效
sysctl_apply_output=$(sysctl --system 2>&1)


echo "正在写入 Ulimit 配置文件: $LIMITS_CONF_FILE"
{
    echo ""
    echo "$LIMITS_MARKER_START"
    echo "# Strategy: $strategy"
    echo "* soft nofile $ulimit_n"
    echo "* hard nofile $ulimit_n"
    echo "root soft nofile $ulimit_n"
    echo "root hard nofile $ulimit_n"
    echo "$LIMITS_MARKER_END"
} > "$LIMITS_CONF_FILE"

# --- 生成并打印最终报告 ---
echo "======================================================================"
echo "          优化完成 - '${strategy}' 策略已应用"
echo "======================================================================"
echo
echo "- 系统内核参数已写入独立的配置文件: $SYSCTL_CONF_FILE"
echo "- Ulimit 配置已写入独立的配置文件: $LIMITS_CONF_FILE"
echo "- $bbr_status_message"
echo

current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
echo "- 当前拥塞控制算法: $current_cc"
echo "- Ulimit 设置提示: 需要重新登录 SSH 会话才能对新会话完全生效。"

if [[ -n "$sysctl_apply_output" && ! "$sysctl_apply_output" =~ ^$ ]]; then
    echo
    echo "--- 'sysctl --system' 生效时输出 (请检查是否存在错误): ---"
    echo "$sysctl_apply_output"
    echo "--------------------------------------------------"
fi
echo
echo "======================================================================"
echo "优化已完成，请重启服务器以确保所有更改完全生效。"
echo "======================================================================"