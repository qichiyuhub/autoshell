#!/bin/sh
# OpenWrt 开启BBR脚本

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- 脚本变量定义 ---
CONF_FILE="/etc/sysctl.conf"
REQUIRED_PACKAGES="kmod-tcp-bbr kmod-sched-fq-pie"
QDISC_NAME="fq_pie"

# 脚本执行出错则立即退出
set -e

# --- 步骤1: 检查状态 ---
printf "%b\n" "${YELLOW}--- 正在检查当前系统状态...${NC}"
BBR_ACTIVE=$(sysctl -n net.ipv4.tcp_congestion_control | grep -c "bbr" || true)
FQ_PIE_ACTIVE=$(sysctl -n net.core.default_qdisc | grep -c "${QDISC_NAME}" || true)

if [ "$BBR_ACTIVE" -gt 0 ] && [ "$FQ_PIE_ACTIVE" -gt 0 ]; then
    printf "%b\n" "${GREEN}✅ BBR 和 ${QDISC_NAME} 均已激活，无需任何操作。${NC}"
    exit 0
fi

# --- 步骤2: 安装并加载模块 ---
printf "%b\n" "${YELLOW}--- 准备安装并加载所需模块...${NC}"
PKG_MANAGER=""
if command -v opkg >/dev/null 2>&1; then PKG_MANAGER="opkg"; elif command -v apk >/dev/null 2>&1; then PKG_MANAGER="apk"; else printf "%b\n" "${RED}❌ 未找到 opkg 或 apk 包管理器。${NC}" >&2; exit 1; fi

printf "%b\n" "${YELLOW}检测到包管理器: '${PKG_MANAGER}'，正在更新软件列表...${NC}"
if [ "$PKG_MANAGER" = "opkg" ]; then opkg update; else apk update; fi

printf "%b\n" "${YELLOW}正在安装必需软件包: ${REQUIRED_PACKAGES} ...${NC}"
# shellcheck disable=SC2086
if [ "$PKG_MANAGER" = "opkg" ]; then opkg install ${REQUIRED_PACKAGES}; else apk add ${REQUIRED_PACKAGES}; fi
printf "%b\n" "${GREEN}✅ 软件包安装完毕。${NC}"

printf "%b\n" "${YELLOW}--- 正在加载内核模块...${NC}"
if ! modprobe sch_fq_pie; then printf "%b\n" "${RED}❌ 加载 sch_fq_pie 模块失败。${NC}" >&2; exit 1; fi
if ! modprobe tcp_bbr; then printf "%b\n" "${RED}❌ 加载 tcp_bbr 模块失败。${NC}" >&2; exit 1; fi
printf "%b\n" "${GREEN}✅ 所有必需模块加载成功。${NC}"

# --- 步骤3: 写入永久配置 ---
printf "%b\n" "${YELLOW}--- 正在写入永久配置到 ${CONF_FILE}...${NC}"
sed -i '/^net.core.default_qdisc/d' "${CONF_FILE}"
printf "%s\n" "net.core.default_qdisc=${QDISC_NAME}" >> "${CONF_FILE}"
sed -i '/^net.ipv4.tcp_congestion_control/d' "${CONF_FILE}"
printf "%s\n" "net.ipv4.tcp_congestion_control=bbr" >> "${CONF_FILE}"
printf "%b\n" "${GREEN}✅ 永久配置写入成功。${NC}"

# --- 步骤4: 应用配置并验证 ---
printf "%b\n" "${YELLOW}--- 正在将配置直接应用到当前内核...${NC}"
sysctl -w "net.core.default_qdisc=${QDISC_NAME}" >/dev/null
sysctl -w "net.ipv4.tcp_congestion_control=bbr" >/dev/null

printf "%b\n" "${YELLOW}--- 正在进行最终验证...${NC}"
final_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
final_qdisc=$(sysctl -n net.core.default_qdisc)

if [ "$final_algo" = "bbr" ] && [ "$final_qdisc" = "${QDISC_NAME}" ]; then
    printf "%b\n" "${GREEN}✅ 成功！BBR 和 ${QDISC_NAME} 均已激活并正在运行。${NC}"
    printf "\n"
    printf "%b\n" "${YELLOW}==================== 如何禁用 ====================${NC}"
    printf "%b\n" "${YELLOW}1. 编辑 ${CONF_FILE} 文件，删除或注释掉相关行。${NC}"
    printf "%b\n" "${YELLOW}2. 重启设备。${NC}"
    printf "%b\n" "${YELLOW}==================================================${NC}"
else
    printf "%b\n" "${RED}❌ 最终验证失败。${NC}"
    printf "%b\n" "${RED}   当前实际状态为: qdisc='${final_qdisc}', algo='${final_algo}'${NC}" >&2
    exit 1
fi