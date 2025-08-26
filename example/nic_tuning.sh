#!/bin/bash

# 多网卡NIC调优脚本
# 支持指定单个网卡或自动检测所有以太网卡

# 使用方法:
# ./nic_tuning.sh                    # 调优所有以太网卡
# ./nic_tuning.sh enp3s0             # 调优指定网卡
# ./nic_tuning.sh enp3s0 eth0 ens18  # 调优多个指定网卡

# 调优单个网卡的函数
tune_interface() {
    local INTERFACE=$1
    
    echo "=========================================="
    echo "开始对网卡 $INTERFACE 进行调优..."
    echo "=========================================="
    
    # 检查网卡是否存在且为UP状态
    if ! ip link show $INTERFACE &> /dev/null; then
        echo "✗ 网卡 $INTERFACE 不存在，跳过"
        return 1
    fi
    
    # 检查网卡状态
    STATE=$(ip link show $INTERFACE | grep -o "state [A-Z]*" | cut -d' ' -f2)
    echo "网卡状态: $STATE"
    
    # 1. 智能中断合并调优
    echo "设置中断合并参数..."
    
    # 获取当前中断合并设置
    COALESCE_INFO=$(ethtool -c $INTERFACE 2>/dev/null)
    if [ $? -eq 0 ]; then
        # 检查是否支持帧数合并
        RX_FRAMES_SUPPORT=$(echo "$COALESCE_INFO" | grep "rx-frames:" | grep -v "n/a")
        TX_FRAMES_SUPPORT=$(echo "$COALESCE_INFO" | grep "tx-frames:" | grep -v "n/a")
        
        if [ ! -z "$RX_FRAMES_SUPPORT" ]; then
            ethtool -C $INTERFACE rx-frames 32 2>/dev/null && echo "✓ rx-frames 设置为 32" || echo "✗ rx-frames 设置失败"
        else
            echo "- rx-frames 不支持"
        fi
        
        if [ ! -z "$TX_FRAMES_SUPPORT" ]; then
            ethtool -C $INTERFACE tx-frames 32 2>/dev/null && echo "✓ tx-frames 设置为 32" || echo "✗ tx-frames 设置失败"
        else
            echo "- tx-frames 不支持"
        fi
        
        # 检查时间延迟合并支持
        RX_USECS_SUPPORT=$(echo "$COALESCE_INFO" | grep "rx-usecs:" | grep -v "n/a")
        TX_USECS_SUPPORT=$(echo "$COALESCE_INFO" | grep "tx-usecs:" | grep -v "n/a")
        
        if [ ! -z "$RX_USECS_SUPPORT" ]; then
            CURRENT_RX_USECS=$(echo "$RX_USECS_SUPPORT" | awk '{print $2}')
            # 统一使用50微秒作为平衡点（吞吐量vs延迟）
            if [ "$CURRENT_RX_USECS" -ne 50 ]; then
                ethtool -C $INTERFACE rx-usecs 50 2>/dev/null && echo "✓ rx-usecs 设置为 50 (从 $CURRENT_RX_USECS 调整)" || echo "✗ rx-usecs 设置失败"
            else
                echo "✓ rx-usecs 当前值 $CURRENT_RX_USECS 已为目标值"
            fi
        else
            echo "- rx-usecs 不支持"
        fi
        
        if [ ! -z "$TX_USECS_SUPPORT" ]; then
            CURRENT_TX_USECS=$(echo "$TX_USECS_SUPPORT" | awk '{print $2}')
            if [ "$CURRENT_TX_USECS" -ne 50 ]; then
                ethtool -C $INTERFACE tx-usecs 50 2>/dev/null && echo "✓ tx-usecs 设置为 50 (从 $CURRENT_TX_USECS 调整)" || echo "✗ tx-usecs 设置失败"
            else
                echo "✓ tx-usecs 当前值 $CURRENT_TX_USECS 已为目标值"
            fi
        else
            echo "- tx-usecs 不支持"
        fi
        
        # 检查聚合参数支持（新型网卡特性）
        TX_AGGR_SUPPORT=$(echo "$COALESCE_INFO" | grep "tx-aggr" | grep -v "n/a")
        if [ ! -z "$TX_AGGR_SUPPORT" ]; then
            echo "检测到TX聚合功能支持..."
            # 根据网卡类型调整聚合参数
            ethtool -C $INTERFACE tx-aggr-max-frames 64 2>/dev/null && echo "✓ tx-aggr-max-frames 设置为 64" || echo "✗ tx-aggr-max-frames 设置失败"
            ethtool -C $INTERFACE tx-aggr-time-usecs 1000 2>/dev/null && echo "✓ tx-aggr-time-usecs 设置为 1000" || echo "✗ tx-aggr-time-usecs 设置失败"
        fi
    else
        echo "✗ 无法获取中断合并信息"
    fi
    
    # 2. 环形缓冲区调优
    echo "调整环形缓冲区大小..."
    # 先获取最大支持值
    RING_INFO=$(ethtool -g $INTERFACE 2>/dev/null)
    if [ $? -eq 0 ]; then
        MAX_RX=$(echo "$RING_INFO" | grep -A4 "Pre-set maximums" | grep "RX:" | awk '{print $2}')
        MAX_TX=$(echo "$RING_INFO" | grep -A4 "Pre-set maximums" | grep "TX:" | awk '{print $2}')
        
        if [ ! -z "$MAX_RX" ] && [ "$MAX_RX" -gt 1024 ]; then
            TARGET_RX=$(( MAX_RX > 4096 ? 4096 : MAX_RX ))
            ethtool -G $INTERFACE rx $TARGET_RX 2>/dev/null && echo "✓ RX 缓冲区设置为 $TARGET_RX" || echo "✗ RX 缓冲区设置失败"
        fi
        
        if [ ! -z "$MAX_TX" ] && [ "$MAX_TX" -gt 1024 ]; then
            TARGET_TX=$(( MAX_TX > 4096 ? 4096 : MAX_TX ))
            ethtool -G $INTERFACE tx $TARGET_TX 2>/dev/null && echo "✓ TX 缓冲区设置为 $TARGET_TX" || echo "✗ TX 缓冲区设置失败"
        fi
    else
        echo "✗ 无法获取环形缓冲区信息"
    fi
    
    # 3. 检查并启用硬件加速功能
    echo "检查并启用硬件加速功能..."
    FEATURES=$(ethtool -k $INTERFACE 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # 检查TSO支持
        if echo "$FEATURES" | grep -q "tcp-segmentation-offload:.*off"; then
            ethtool -K $INTERFACE tso on 2>/dev/null && echo "✓ TSO 已启用" || echo "✗ TSO 启用失败"
        elif echo "$FEATURES" | grep -q "tcp-segmentation-offload:.*on"; then
            echo "✓ TSO 已经启用"
        else
            echo "- TSO 不支持"
        fi
        
        # 检查GSO支持
        if echo "$FEATURES" | grep -q "generic-segmentation-offload:.*off"; then
            ethtool -K $INTERFACE gso on 2>/dev/null && echo "✓ GSO 已启用" || echo "✗ GSO 启用失败"
        elif echo "$FEATURES" | grep -q "generic-segmentation-offload:.*on"; then
            echo "✓ GSO 已经启用"
        else
            echo "- GSO 不支持"
        fi
        
        # 检查GRO支持
        if echo "$FEATURES" | grep -q "generic-receive-offload:.*off"; then
            ethtool -K $INTERFACE gro on 2>/dev/null && echo "✓ GRO 已启用" || echo "✗ GRO 启用失败"
        elif echo "$FEATURES" | grep -q "generic-receive-offload:.*on"; then
            echo "✓ GRO 已经启用"
        else
            echo "- GRO 不支持"
        fi
        
        # 检查LRO支持
        if echo "$FEATURES" | grep -q "large-receive-offload:.*off"; then
            ethtool -K $INTERFACE lro on 2>/dev/null && echo "✓ LRO 已启用" || echo "✗ LRO 启用失败"
        elif echo "$FEATURES" | grep -q "large-receive-offload:.*on"; then
            echo "✓ LRO 已经启用"
        else
            echo "- LRO 不支持"
        fi
        
        # 检查RX校验和支持
        if echo "$FEATURES" | grep -q "rx-checksumming:.*off"; then
            ethtool -K $INTERFACE rx-checksumming on 2>/dev/null && echo "✓ RX 校验和已启用" || echo "✗ RX 校验和启用失败"
        elif echo "$FEATURES" | grep -q "rx-checksumming:.*on"; then
            echo "✓ RX 校验和已经启用"
        else
            echo "- RX 校验和不支持"
        fi
        
        # 检查TX校验和支持
        if echo "$FEATURES" | grep -q "tx-checksumming:.*off"; then
            ethtool -K $INTERFACE tx-checksumming on 2>/dev/null && echo "✓ TX 校验和已启用" || echo "✗ TX 校验和启用失败"
        elif echo "$FEATURES" | grep -q "tx-checksumming:.*on"; then
            echo "✓ TX 校验和已经启用"
        else
            echo "- TX 校验和不支持"
        fi
    else
        echo "✗ 无法获取硬件功能信息"
    fi
    
    # 4. 多队列调优（如果支持）
    echo "检查多队列支持..."
    QUEUE_INFO=$(ethtool -l $INTERFACE 2>/dev/null)
    if [ $? -eq 0 ]; then
        MAX_COMBINED=$(echo "$QUEUE_INFO" | grep -A10 "Pre-set maximums" | grep "Combined:" | awk '{print $2}')
        CURRENT_COMBINED=$(echo "$QUEUE_INFO" | grep -A10 "Current hardware settings" | grep "Combined:" | awk '{print $2}')
        
        if [ ! -z "$MAX_COMBINED" ] && [ "$MAX_COMBINED" -gt 1 ]; then
            CPU_CORES=$(nproc)
            TARGET_QUEUES=$(( MAX_COMBINED > CPU_CORES ? CPU_CORES : MAX_COMBINED ))
            
            if [ "$CURRENT_COMBINED" != "$TARGET_QUEUES" ]; then
                ethtool -L $INTERFACE combined $TARGET_QUEUES 2>/dev/null && echo "✓ 队列数设置为 $TARGET_QUEUES" || echo "✗ 队列设置失败"
            else
                echo "✓ 队列数已为最优值 $TARGET_QUEUES"
            fi
        else
            echo "✗ 不支持多队列或已为单队列"
        fi
    else
        echo "✗ 无法获取队列信息"
    fi
    
    # 5. 设置中断亲和性（避开CPU0，从CPU1开始）
    echo "优化中断亲和性..."
    IRQ_LIST=$(grep $INTERFACE /proc/interrupts | cut -d: -f1 | tr -d ' ')
    if [ ! -z "$IRQ_LIST" ]; then
        CPU_COUNT=$(nproc)
        
        # 避开CPU0，从CPU1开始分配
        if [ "$CPU_COUNT" -gt 1 ]; then
            CPU_INDEX=1
            IRQ_COUNT=0
            
            for IRQ in $IRQ_LIST; do
                if [ -w /proc/irq/$IRQ/smp_affinity ]; then
                    CPU_MASK=$((1 << CPU_INDEX))
                    printf "%x" $CPU_MASK > /proc/irq/$IRQ/smp_affinity 2>/dev/null && echo "✓ IRQ $IRQ 绑定到 CPU $CPU_INDEX" || echo "✗ IRQ $IRQ 亲和性设置失败"
                    
                    # 循环分配，但跳过CPU0
                    CPU_INDEX=$(( CPU_INDEX + 1 ))
                    if [ "$CPU_INDEX" -ge "$CPU_COUNT" ]; then
                        CPU_INDEX=1  # 重新从CPU1开始
                    fi
                    IRQ_COUNT=$((IRQ_COUNT + 1))
                fi
            done
            
            echo "✓ 已将 $IRQ_COUNT 个中断分配到 CPU1-CPU$((CPU_COUNT-1))，避开了繁忙的 CPU0"
        else
            echo "✗ 单核系统，无法进行中断亲和性优化"
        fi
    else
        echo "✗ 未找到 $INTERFACE 的中断信息"
    fi
    
    # 6. 显示当前设置
    echo "当前网卡配置:"
    echo "中断合并: $(ethtool -c $INTERFACE 2>/dev/null | grep -E 'rx-frames|tx-frames' | head -2)"
    echo "硬件功能: $(ethtool -k $INTERFACE 2>/dev/null | grep -E ': on$' | wc -l) 个功能已启用"
    
    echo "$INTERFACE 调优完成"
    echo
}

# 设置开机自动应用调优
setup_autostart() {
    local INTERFACES="$1"
    
    echo "设置开机自动应用调优..."
    
    # 创建调优脚本
    TUNING_SCRIPT="/usr/local/bin/nic-autotuning.sh"
    cat > $TUNING_SCRIPT << 'EOF'
#!/bin/bash
# NIC 自动调优脚本 - 开机启动版本

apply_tuning() {
    local INTERFACE=$1
    
    # 等待网卡就绪
    for i in {1..30}; do
        if ip link show $INTERFACE &> /dev/null; then
            break
        fi
        sleep 1
    done
    
    # 检查网卡是否存在
    if ! ip link show $INTERFACE &> /dev/null; then
        logger "NIC-Tuning: Interface $INTERFACE not found"
        return 1
    fi
    
    logger "NIC-Tuning: Starting tuning for $INTERFACE"
    
    # 中断合并 - 智能检测支持的参数
    COALESCE_INFO=$(ethtool -c $INTERFACE 2>/dev/null)
    if [ $? -eq 0 ]; then
        # 帧数合并
        if echo "$COALESCE_INFO" | grep "rx-frames:" | grep -qv "n/a"; then
            ethtool -C $INTERFACE rx-frames 32 2>/dev/null
        fi
        if echo "$COALESCE_INFO" | grep "tx-frames:" | grep -qv "n/a"; then
            ethtool -C $INTERFACE tx-frames 32 2>/dev/null
        fi
        
        # 时间延迟合并 - 统一使用50微秒
        if echo "$COALESCE_INFO" | grep "rx-usecs:" | grep -qv "n/a"; then
            ethtool -C $INTERFACE rx-usecs 50 2>/dev/null
        fi
        if echo "$COALESCE_INFO" | grep "tx-usecs:" | grep -qv "n/a"; then
            ethtool -C $INTERFACE tx-usecs 50 2>/dev/null
        fi
        
        # 聚合参数
        if echo "$COALESCE_INFO" | grep "tx-aggr" | grep -qv "n/a"; then
            ethtool -C $INTERFACE tx-aggr-max-frames 64 2>/dev/null
            ethtool -C $INTERFACE tx-aggr-time-usecs 1000 2>/dev/null
        fi
    fi
    
    # 环形缓冲区
    RING_INFO=$(ethtool -g $INTERFACE 2>/dev/null)
    if [ $? -eq 0 ]; then
        MAX_RX=$(echo "$RING_INFO" | grep -A4 "Pre-set maximums" | grep "RX:" | awk '{print $2}')
        MAX_TX=$(echo "$RING_INFO" | grep -A4 "Pre-set maximums" | grep "TX:" | awk '{print $2}')
        
        if [ ! -z "$MAX_RX" ] && [ "$MAX_RX" -gt 1024 ]; then
            TARGET_RX=$(( MAX_RX > 4096 ? 4096 : MAX_RX ))
            ethtool -G $INTERFACE rx $TARGET_RX 2>/dev/null
        fi
        
        if [ ! -z "$MAX_TX" ] && [ "$MAX_TX" -gt 1024 ]; then
            TARGET_TX=$(( MAX_TX > 4096 ? 4096 : MAX_TX ))
            ethtool -G $INTERFACE tx $TARGET_TX 2>/dev/null
        fi
    fi
    
    # 硬件加速功能
    FEATURES=$(ethtool -k $INTERFACE 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$FEATURES" | grep -q "tcp-segmentation-offload:.*off" && ethtool -K $INTERFACE tso on 2>/dev/null
        echo "$FEATURES" | grep -q "generic-segmentation-offload:.*off" && ethtool -K $INTERFACE gso on 2>/dev/null
        echo "$FEATURES" | grep -q "generic-receive-offload:.*off" && ethtool -K $INTERFACE gro on 2>/dev/null
        echo "$FEATURES" | grep -q "large-receive-offload:.*off" && ethtool -K $INTERFACE lro on 2>/dev/null
        echo "$FEATURES" | grep -q "rx-checksumming:.*off" && ethtool -K $INTERFACE rx-checksumming on 2>/dev/null
        echo "$FEATURES" | grep -q "tx-checksumming:.*off" && ethtool -K $INTERFACE tx-checksumming on 2>/dev/null
    fi
    
    # 多队列
    QUEUE_INFO=$(ethtool -l $INTERFACE 2>/dev/null)
    if [ $? -eq 0 ]; then
        MAX_COMBINED=$(echo "$QUEUE_INFO" | grep -A10 "Pre-set maximums" | grep "Combined:" | awk '{print $2}')
        if [ ! -z "$MAX_COMBINED" ] && [ "$MAX_COMBINED" -gt 1 ]; then
            CPU_CORES=$(nproc)
            TARGET_QUEUES=$(( MAX_COMBINED > CPU_CORES ? CPU_CORES : MAX_COMBINED ))
            ethtool -L $INTERFACE combined $TARGET_QUEUES 2>/dev/null
        fi
    fi
    
    # 中断亲和性 - 避开CPU0
    IRQ_LIST=$(grep $INTERFACE /proc/interrupts 2>/dev/null | cut -d: -f1 | tr -d ' ')
    if [ ! -z "$IRQ_LIST" ]; then
        CPU_COUNT=$(nproc)
        
        if [ "$CPU_COUNT" -gt 1 ]; then
            CPU_INDEX=1  # 从CPU1开始
            
            for IRQ in $IRQ_LIST; do
                if [ -w /proc/irq/$IRQ/smp_affinity ]; then
                    CPU_MASK=$((1 << CPU_INDEX))
                    printf "%x" $CPU_MASK > /proc/irq/$IRQ/smp_affinity 2>/dev/null
                    CPU_INDEX=$(( CPU_INDEX + 1 ))
                    if [ "$CPU_INDEX" -ge "$CPU_COUNT" ]; then
                        CPU_INDEX=1
                    fi
                fi
            done
        fi
    fi
    
    logger "NIC-Tuning: Completed tuning for $INTERFACE"
}

# 主程序
EOF
    
    # 添加网卡列表到脚本
    echo "" >> $TUNING_SCRIPT
    echo "# 需要调优的网卡列表" >> $TUNING_SCRIPT
    echo "INTERFACES=\"$INTERFACES\"" >> $TUNING_SCRIPT
    
    # 添加执行部分
    cat >> $TUNING_SCRIPT << 'EOF'

for INTERFACE in $INTERFACES; do
    apply_tuning $INTERFACE &
done

wait
logger "NIC-Tuning: All interfaces tuning completed"
EOF
    
    chmod +x $TUNING_SCRIPT
    
    # 创建systemd服务文件
    SERVICE_FILE="/etc/systemd/system/nic-tuning.service"
    cat > $SERVICE_FILE << EOF
[Unit]
Description=Network Interface Card Tuning
After=network.target
Before=network-online.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$TUNING_SCRIPT
RemainAfterExit=yes
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF
    
    # 启用服务
    systemctl daemon-reload
    systemctl enable nic-tuning.service
    
    echo "✓ 已创建 systemd 服务: $SERVICE_FILE"
    echo "✓ 已创建调优脚本: $TUNING_SCRIPT"
    echo "✓ 服务已启用，重启后自动应用调优设置"
    
    # 同时创建网络接口启动脚本（作为备用方案）
    NETWORK_SCRIPT="/etc/network/if-up.d/nic-tuning"
    cat > $NETWORK_SCRIPT << EOF
#!/bin/bash
# NIC调优 - 网络接口启动时触发

if [ "\$METHOD" = "loopback" ] || [ "\$METHOD" = "none" ]; then
    exit 0
fi

case "\$IFACE" in
EOF
    
    for INTERFACE in $INTERFACES; do
        echo "    $INTERFACE)" >> $NETWORK_SCRIPT
        echo "        $TUNING_SCRIPT &" >> $NETWORK_SCRIPT
        echo "        ;;" >> $NETWORK_SCRIPT
    done
    
    cat >> $NETWORK_SCRIPT << 'EOF'
    *)
        ;;
esac

exit 0
EOF
    
    chmod +x $NETWORK_SCRIPT 2>/dev/null
    
    if [ -d "/etc/network/if-up.d" ]; then
        echo "✓ 已创建网络接口启动脚本: $NETWORK_SCRIPT"
    fi
    
    echo
    echo "开机自动调优设置完成！"
    echo "可以使用以下命令管理:"
    echo "  systemctl status nic-tuning     # 查看服务状态"
    echo "  systemctl disable nic-tuning    # 禁用自动调优"
    echo "  $TUNING_SCRIPT                  # 手动运行调优"
}
get_ethernet_interfaces() {
    ip link show | grep -E '^[0-9]+:' | grep -E 'eth|en[sp]|ens' | cut -d: -f2 | tr -d ' ' | grep -v '@'
}

# 主程序
main() {
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        echo "请使用 root 权限运行此脚本"
        echo "sudo $0 $@"
        exit 1
    fi
    
    # 检查ethtool是否安装
    if ! command -v ethtool &> /dev/null; then
        echo "错误: ethtool 未安装"
        echo "请安装: apt install ethtool 或 yum install ethtool"
        exit 1
    fi
    
    echo "NIC 调优脚本 - 支持多网卡"
    echo "=================================="
    
    # 如果没有指定参数，自动检测所有以太网卡
    if [ $# -eq 0 ]; then
        echo "未指定网卡，自动检测所有以太网接口..."
        INTERFACES=$(get_ethernet_interfaces)
        
        if [ -z "$INTERFACES" ]; then
            echo "未找到任何以太网接口"
            exit 1
        fi
        
        echo "检测到以下网卡: $INTERFACES"
        echo
    else
        INTERFACES="$@"
        echo "将调优指定网卡: $INTERFACES"
        echo
    fi
    
    # 对每个网卡进行调优
    SUCCESS_COUNT=0
    TOTAL_COUNT=0
    
    for INTERFACE in $INTERFACES; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        if tune_interface $INTERFACE; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
        sleep 1
    done
    
    echo "=========================================="
    echo "调优完成! 成功: $SUCCESS_COUNT/$TOTAL_COUNT"
    echo "=========================================="
    
    # 建议重启网络服务或重启系统使某些设置生效
    echo "注意: 某些设置可能需要重启网络服务或系统才能完全生效"
    
    # 询问是否设置开机自动应用
    echo
    read -p "是否设置开机自动应用这些调优设置? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_autostart "$INTERFACES"
    fi
}

# 运行主程序
main "$@"