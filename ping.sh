#!/bin/bash

# 定义颜色输出函数
function echo_color() {
    local var_color=${1}
    local content_str=${2}
    local content_echo_str=""

    # 定义颜色变量
    local error_color="\033[1;31m"        # 红色字体
    local failed_color="\033[1;31m"        # 红色字体
    local warn_color="\033[1;33m"          # 黄色字体
    local succ_color="\033[1;32m"         # 绿色字体
    local info_color="\033[1;34m"         # 蓝色字体
    local violet_color="\033[1;35m"       # 紫色字体
    local RES="\033[0m"                   # 颜色结束

    case ${var_color} in
        error) content_echo_str="${error_color}${content_str}${RES}" ;;
        failed) content_echo_str="${failed_color}${content_str}${RES}" ;;
        warning) content_echo_str="${warn_color}${content_str}${RES}" ;;
        success) content_echo_str="${succ_color}${content_str}${RES}" ;;
        info) content_echo_str="${info_color}${content_str}${RES}" ;;
        violet) content_echo_str="${violet_color}${content_str}${RES}" ;;
        *) content_echo_str="${content_str}${RES}" ;;
    esac

    echo -e "${content_echo_str}"
}

# 参数验证函数
function validate_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && \
           ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# 检查命令是否存在
function check_commands() {
    for cmd in "$@"; do
        if ! command -v $cmd &> /dev/null; then
            echo_color error "错误: 需要安装 $cmd 命令"
            return 1
        fi
    done
    return 0
}

# 检查参数有效性
function validate_parameters() {
    local network=$1
    local start=$2
    local end=$3
    
    # 检查IP地址
    if ! validate_ip "$network"; then
        echo_color error "错误: 必须提供有效的IP地址作为第一个参数"
        echo_color info "用法: $0 <网络地址> [起始IP] [结束IP]"
        echo_color info "示例: $0 192.168.1.0 2 254"
        return 1
    fi
    
    # 参数范围检查
    if [ $start -lt 1 ] || [ $start -gt 254 ]; then
        echo_color error "错误: 起始IP必须在1-254范围内"
        return 1
    fi

    if [ $end -lt 1 ] || [ $end -gt 254 ]; then
        echo_color error "错误: 结束IP必须在1-254范围内"
        return 1
    fi

    if [ $start -gt $end ]; then
        echo_color error "错误: 起始IP不能大于结束IP"
        return 1
    fi
    
    return 0
}

# 初始化日志目录
function init_log_dir() {
    local log_dir=$1
    
    # 检查并创建日志目录
    if [ ! -d "$log_dir" ]; then
        echo_color info "创建日志目录: $log_dir"
        mkdir -p "$log_dir"
        if [ $? -ne 0 ]; then
            echo_color error "错误: 无法创建日志目录 $log_dir"
            return 1
        fi
    elif [ ! -w "$log_dir" ]; then
        echo_color error "错误: 日志目录 $log_dir 不可写"
        return 1
    fi
    
    return 0
}

# 扫描单个IP
function scan_ip() {
    local ip=$1
    local result=""
    
    if ping -c 1 -W $ping_timeout "$ip" &> /dev/null; then
        nc -z -w $nc_timeout "$ip" 22 &> /dev/null
        local ssh_open=$?
        
        nc -z -w $nc_timeout "$ip" 3389 &> /dev/null
        local rdp_open=$?
        
        result="$ip | 状态: 在线 | SSH: $([ $ssh_open -eq 0 ] && echo 开放 || echo 关闭) | RDP: $([ $rdp_open -eq 0 ] && echo 开放 || echo 关闭)"
        echo_color success "$result"
    else
        result="$ip | 状态: 离线 | SSH: - | RDP: -"
        echo_color failed "$result"
    fi
    echo "$result" >> "$result_file"
}

# 执行扫描过程
function run_scan() {
    local network=$1
    local start=$2
    local end=$3
    local max_workers=$4
    
    echo_color info "开始扫描网络: $network.0/24 (IP范围: $start-$end)"
    echo_color info "最大并行任务数: $max_workers"
    echo_color info "结果将保存到: $result_file"
    
    # 导出函数以便并行使用
    export -f echo_color scan_ip
    export ping_timeout nc_timeout result_file
    
    # 主扫描过程
    for i in $(seq $start $end); do
        ip="$network.$i"
        scan_ip "$ip" &
        
        # 控制并行数量
        while [ $(jobs -r | wc -l) -ge $max_workers ]; do
            sleep 0.1
        done
    done
    
    # 等待所有后台任务完成
    wait
}

# 生成统计报告
function generate_report() {
    local network=$1
    local start=$2
    local end=$3
    local result_file=$4
    
    local online_count=$(grep -c "状态: 在线" "$result_file" 2>/dev/null)
    local offline_count=$(grep -c "状态: 离线" "$result_file" 2>/dev/null)
    local ssh_open_count=$(grep -c "SSH: 开放" "$result_file" 2>/dev/null)
    local rdp_open_count=$(grep -c "RDP: 开放" "$result_file" 2>/dev/null)

    echo_color info ""
    echo_color success "扫描完成！"
    echo_color info "------------------------------------"
    echo_color violet "扫描范围: $network.$start - $network.$end"
    echo_color violet "总IP数: $((end - start + 1))"
    echo_color success "在线设备: ${online_count:-0}"
    echo_color failed "离线设备: ${offline_count:-0}"
    echo_color info "服务开放统计："
    echo_color violet "  SSH (22端口): ${ssh_open_count:-0}"
    echo_color violet "  RDP (3389端口): ${rdp_open_count:-0}"
    echo_color info "------------------------------------"
    echo_color info "详细结果已保存到: $result_file"
}

# 主函数
function main() {
    # 检查参数
    if [ $# -lt 1 ]; then
        echo_color error "错误: 必须提供有效的IP地址作为第一个参数"
        echo_color info "用法: $0 <网络地址> [起始IP] [结束IP]"
        echo_color info "示例: $0 192.168.1.0 2 254"
        exit 1
    fi
    
    # 设置网络参数
    local network=$(echo $1 | cut -d. -f1-3)
    local start=${2:-2}
    local end=${3:-253}
    
    # 验证参数
    validate_parameters "$1" "$start" "$end"
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # 超时设置
    ping_timeout=1
    nc_timeout=2
    max_workers=20
    
    # 日志目录设置
    log_dir="pinglog"
    
    # 初始化日志目录
    init_log_dir "$log_dir"
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # 结果文件
    result_file="$log_dir/scan_result_$(date +%Y%m%d_%H%M%S).txt"
    > "$result_file"
    
    # 检查必要命令
    check_commands ping nc
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # 执行扫描
    run_scan "$network" "$start" "$end" "$max_workers"
    
    # 生成报告
    generate_report "$network" "$start" "$end" "$result_file"
}

# 执行主函数
main "$@"
