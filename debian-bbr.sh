#!/bin/bash
#
# 功能: 启用 BBR。如果已最佳启用则跳过，否则进行配置并验证。
#

set -e

CONF_FILE="/etc/sysctl.d/99-bbr.conf"

# 1. 前置检查: 必须同时满足 bbr 和 fq 才视为已启用
echo "正在检测当前网络配置..."
current_qdisc=$(sysctl -n net.core.default_qdisc)
current_algo=$(sysctl -n net.ipv4.tcp_congestion_control)

if [ "$current_qdisc" = "fq" ] && [ "$current_algo" = "bbr" ]; then
    echo "✅ 检测通过：BBR 和 fq 已完美启用，无需任何操作。"
    exit 0
fi

# 2. 写入配置与应用 (仅在未完全启用时执行)
echo "当前配置 (qdisc: '$current_qdisc', algo: '$current_algo') 未达最佳，开始配置..."
cat > ${CONF_FILE} << EOF
# 由优化脚本自动生成 - 启用 BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

sysctl -p "${CONF_FILE}" > /dev/null

# 3. 执行后验证
echo "验证配置..."
final_qdisc=$(sysctl -n net.core.default_qdisc)
final_algo=$(sysctl -n net.ipv4.tcp_congestion_control)

if [ "$final_qdisc" = "fq" ] && [ "$final_algo" = "bbr" ]; then
    echo "✅ 配置成功：BBR 和 fq 均已成功启用并正在运行。"
    echo
    echo "--------------------------------------------------"
    echo "如需禁用并恢复默认，请执行以下命令:"
    echo "sudo rm ${CONF_FILE} && sudo reboot"
    echo "--------------------------------------------------"
else
    echo "❌ 配置失败：未能成功启用 BBR 和 fq。"
    echo "   当前实际配置为 (qdisc: '$final_qdisc', algo: '$final_algo')"
    exit 1
fi