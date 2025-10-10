#!/bin/bash
set -e
#================================================================================
#
#           Linux 网络默认配置恢复脚本
#
#================================================================================

if [[ $EUID -ne 0 ]]; then
   echo "错误: 此脚本必须以 root 权限运行。"
   exit 1
fi

# --- 配置文件路径 (必须与优化脚本中使用的完全一致) ---
SYSCTL_CONF_FILE="/etc/sysctl.d/99-custom-network-tuning.conf"
LIMITS_CONF_FILE="/etc/security/limits.d/99-custom-limits.conf"
BBR_MODULE_FILE="/etc/modules-load.d/bbr.conf"

echo "======================================================================"
echo "          开始恢复 Debian 网络默认配置..."
echo "======================================================================"
echo

# --- 步骤 1: 移除网络性能优化配置文件 ---
echo "[1/3] 正在移除网络性能优化配置文件..."
if [ -f "$SYSCTL_CONF_FILE" ]; then
    rm -f "$SYSCTL_CONF_FILE"
    echo "      成功：文件 '$SYSCTL_CONF_FILE' 已删除。"
else
    echo "      信息：文件 '$SYSCTL_CONF_FILE' 未找到，无需操作。"
fi
echo

# --- 步骤 2: 移除 Ulimit 配置文件 ---
echo "[2/3] 正在移除 Ulimit 配置文件..."
if [ -f "$LIMITS_CONF_FILE" ]; then
    rm -f "$LIMITS_CONF_FILE"
    echo "      成功：文件 '$LIMITS_CONF_FILE' 已删除。"
else
    echo "      信息：文件 '$LIMITS_CONF_FILE' 未找到，无需操作。"
fi
echo

# --- 步骤 3: 移除 BBR 自动加载配置 ---
echo "[3/3] 正在移除 BBR 自动加载配置..."
if [ -f "$BBR_MODULE_FILE" ]; then
    rm -f "$BBR_MODULE_FILE"
    echo "      成功：BBR 自动加载文件 '$BBR_MODULE_FILE' 已删除。"
else
    echo "      信息：未找到 BBR 自动加载文件，无需操作。"
fi
echo

# --- 步骤 4: 重新加载系统默认内核参数 ---
echo "[4/4] 正在重新加载系统默认内核参数..."
# --system 会重新读取所有剩余的配置文件，从而恢复到默认状态
sysctl --system >/dev/null 2>&1
echo "      成功：系统默认配置已重新加载。"
echo "      - 当前拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo

echo "======================================================================"
echo "                      恢复操作已完成"
echo "======================================================================"
echo
echo "所有由优化脚本创建的配置文件均已清理完毕。"
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