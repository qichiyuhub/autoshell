#!/bin/bash
set -e
#================================================================================
#
#           Linux 网络默认配置恢复脚本
#
#================================================================================

# --- 确保以 Root 权限运行 ---
if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本必须以 root 权限运行。"
   exit 1
fi

# --- 定义标记，必须与优化脚本中的完全一致 ---
SYSCTL_MARKER_START="# --- BEGIN Kernel Tuning by Script ---"
SYSCTL_MARKER_END="# --- END Kernel Tuning by Script ---"
LIMITS_MARKER_START="# --- BEGIN Ulimit Settings by Script ---"
LIMITS_MARKER_END="# --- END Ulimit Settings by Script ---"

echo "======================================================================"
echo "          开始恢复 Debian 网络默认配置..."
echo "======================================================================"
echo

# --- 步骤 1: 恢复 /etc/sysctl.conf 文件 ---
echo "[1/4] 正在恢复 /etc/sysctl.conf 文件..."
if grep -q "$SYSCTL_MARKER_START" /etc/sysctl.conf; then
    sed -i "/^${SYSCTL_MARKER_START}$/,/^${SYSCTL_MARKER_END}$/d" /etc/sysctl.conf
    echo "      成功：优化脚本添加的内核参数块已移除。"
else
    echo "      信息：未在 /etc/sysctl.conf 中找到优化标记，无需操作。"
fi
echo

# --- 步骤 2: 恢复 /etc/security/limits.conf 文件 ---
echo "[2/4] 正在恢复 /etc/security/limits.conf 文件..."
if grep -q "$LIMITS_MARKER_START" /etc/security/limits.conf; then
    sed -i "/^${LIMITS_MARKER_START}$/,/^${LIMITS_MARKER_END}$/d" /etc/security/limits.conf
    echo "      成功：优化脚本添加的 Ulimit 配置块已移除。"
else
    echo "      信息：未在 /etc/security/limits.conf 中找到优化标记，无需操作。"
fi
echo

# --- 步骤 3: 移除 BBR 自动加载配置 ---
echo "[3/4] 正在移除 BBR 自动加载配置..."
BBR_MODULE_FILE="/etc/modules-load.d/bbr.conf"
if [ -f "$BBR_MODULE_FILE" ]; then
    rm -f "$BBR_MODULE_FILE"
    echo "      成功：BBR 自动加载文件 '$BBR_MODULE_FILE' 已删除。"
else
    echo "      信息：未找到 BBR 自动加载文件，无需操作。"
fi
echo

# --- 步骤 4: 恢复运行中的系统内核参数为 Debian 默认值 ---
echo "[4/4] 正在恢复当前运行的系统内核参数..."
# 重新加载所有 sysctl 配置文件，这将应用默认值
sysctl --system > /dev/null 2>&1

# Debian 默认的拥塞控制算法是 cubic
sysctl -w net.ipv4.tcp_congestion_control=cubic > /dev/null 2>&1
# 默认的排队规则是 pfifo_fast
sysctl -w net.core.default_qdisc=pfifo_fast > /dev/null 2>&1

echo "      成功：已尝试将运行中的内核参数恢复为 Debian 默认值。"
echo "      - 当前拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "      - 当前排队规则: $(sysctl -n net.core.default_qdisc)"
echo

echo "======================================================================"
echo "                      恢复操作已完成"
echo "======================================================================"
echo
echo "所有相关的配置文件均已清理完毕，并且已尝试恢复了运行中的系统状态。"
echo
echo "重要提示:"
echo "  - Ulimit (文件描述符) 的限制需要您 '退出当前SSH会话并重新登录' 才能完全恢复为默认值。"
echo "  - 为了确保所有系统服务和内核状态 100% 恢复到最干净的初始状态，强烈建议您重启服务器。"
echo

read -r -p "您想现在重启服务器吗? (y/N): " choice
case "$choice" in
  y|Y )
    echo "好的，服务器将在5秒后重启..."
    sleep 5
    reboot
    ;;
  * )
    echo "操作完成。请记得手动重启服务器以完成彻底恢复。"
    ;;
esac