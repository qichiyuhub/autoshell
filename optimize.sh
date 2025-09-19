#!/bin/bash

# ==============================================================================
# Linux 网络性能优化脚本
# - 根据内存动态选择策略 (保守/高性能)
# - 智能应用内核参数与文件描述符限制
# - 根据内存+现有参数读取确保不会出现负优化
# ==============================================================================

# --- 必须以 root 用户运行 ---
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：此脚本必须以 root 用户权限运行。" >&2
  exit 1
fi

# --- 动态策略选择 ---
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
STRATEGY="high_performance"
if [ "$TOTAL_MEM_MB" -lt 1500 ]; then
  STRATEGY="conservative"
fi

# --- 配置文件路径 ---
SYSCTL_CONF_FILE="/etc/sysctl.d/99-custom-network-tuning.conf"
LIMITS_CONF_FILE="/etc/security/limits.d/99-custom-limits.conf"

# --- 智能设置 sysctl (仅当目标值更大时写入) ---
set_sysctl_smart() {
  local key="$1"
  local target_value="$2"
  local proc_path="/proc/sys/${key//./\/}"
  
  # 从文件中移除旧定义
  sed -i "/^$(echo "$key" | sed -e 's/[]\/$*.^[]/\\&/g')/d" "$SYSCTL_CONF_FILE"

  if [ ! -f "$proc_path" ]; then
    echo "$key = $target_value" >> "$SYSCTL_CONF_FILE"
    return
  fi
  
  local current_value
  current_value=$(sysctl -n "$key" 2>/dev/null)
  
  if [ -z "$current_value" ] || [ "$((current_value))" -lt "$((target_value))" ]; then
    echo "$key = $target_value" >> "$SYSCTL_CONF_FILE"
  fi
}

# --- 1. 配置 sysctl 内核参数 (基础配置) ---
cat > "$SYSCTL_CONF_FILE" << EOF
# --- 自定义网络优化配置 ---

# 1. 连接队列
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 16384

# 2. TCP/UDP 缓冲区
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 65536 4194304
net.ipv4.udp_rmem_min = 4096
net.ipv4.udp_wmem_min = 4096

# 3. BBR 拥塞控制 (如果支持)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 4. TCP 行为优化
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10

# 5. IP 转发与安全
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF

# --- 2. 智能应用策略特定值 ---
set_sysctl_smart "fs.file-max" 1048576

if [ "$STRATEGY" = "high_performance" ]; then
  set_sysctl_smart "fs.file-max" 2097152
  set_sysctl_smart "net.core.somaxconn" 65535
  set_sysctl_smart "net.ipv4.tcp_max_syn_backlog" 65535
  set_sysctl_smart "net.core.rmem_max" 33554432
  set_sysctl_smart "net.core.wmem_max" 33554432
  sed -i "/tcp_rmem/c\net.ipv4.tcp_rmem = 4096 87380 33554432" "$SYSCTL_CONF_FILE"
  sed -i "/tcp_wmem/c\net.ipv4.tcp_wmem = 4096 65536 33554432" "$SYSCTL_CONF_FILE"
fi

# --- 3. 检查 BBR 支持并适应 ---
if ! sysctl -n net.ipv4.tcp_available_congestion_control | grep -qw "bbr"; then
  BBR_SUPPORTED=false
  CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control)
  sed -i -e '/bbr/d' -e '/fq/d' "$SYSCTL_CONF_FILE"
else
  BBR_SUPPORTED=true
fi

# --- 4. 配置文件描述符限制 ---
ULIMIT_VALUE=65536
if [ "$STRATEGY" = "high_performance" ]; then
  ULIMIT_VALUE=1048576
fi

cat > "$LIMITS_CONF_FILE" << EOF
# 自定义文件描述符限制
* soft nofile ${ULIMIT_VALUE}
* hard nofile ${ULIMIT_VALUE}
root soft nofile ${ULIMIT_VALUE}
root hard nofile ${ULIMIT_VALUE}
EOF

# --- 5. 应用配置并生成最终报告 ---
sysctl -p "$SYSCTL_CONF_FILE" >/dev/null 2>&1

if [ "$BBR_SUPPORTED" = true ]; then
  BBR_STATUS_MSG="已启用"
else
  BBR_STATUS_MSG="内核不支持 (当前为: ${CURRENT_CC})"
fi

clear
cat << EOF
=====================================================
          Linux 网络优化已应用
=====================================================

  - 策略: ${STRATEGY} (${TOTAL_MEM_MB} MB)
  - 文件描述符 (ulimit): ${ULIMIT_VALUE}
  - BBR 拥塞控制: ${BBR_STATUS_MSG}

[!] 重要后续操作:
    1. 重新登录 SSH (或重启) 使文件描述符限制生效。
    2. 检查防火墙规则，因 IP 转发已被激活。

=====================================================
EOF