#!/bin/bash

#############################################
# Aurora 蓝绿部署切换前检查脚本
# 用途：验证切换条件是否满足
#############################################

set -e

#############################################
# 配置参数 - 请在此处修改
#############################################

# AWS 配置
BG_DEPLOYMENT_ID="bgd-xxxxxxxxxxxxx"           # 蓝绿部署 ID
DB_CLUSTER_ID="my-aurora-cluster"              # 集群标识符
AWS_REGION="us-east-1"                         # AWS 区域

# 蓝色环境（当前生产环境）数据库连接
BLUE_DB_HOST="blue-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
BLUE_DB_USER="admin"
BLUE_DB_PASSWORD="your-blue-password"

# 绿色环境（新环境）数据库连接
GREEN_DB_HOST="green-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
GREEN_DB_USER="admin"
GREEN_DB_PASSWORD="your-green-password"

# 检查阈值配置
MAX_CONNECTIONS=100                            # 最大连接数
MAX_REPLICATION_LAG_SECONDS=1                  # 最大复制延迟（秒）
MAX_LONG_TRANSACTION_SECONDS=10                # 长事务阈值（秒）
MAX_LOCK_WAIT_SECONDS=5                        # 锁等待阈值（秒）

#############################################
# 以下代码无需修改
#############################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 兼容旧的环境变量方式（如果设置了环境变量，优先使用环境变量）
BG_DEPLOYMENT_ID="${BG_DEPLOYMENT_ID:-$BG_DEPLOYMENT_ID}"
DB_CLUSTER_ID="${DB_CLUSTER_ID:-$DB_CLUSTER_ID}"
AWS_REGION="${AWS_REGION:-$AWS_REGION}"

# 阈值配置
MAX_CONNECTIONS=100
MAX_REPLICATION_LAG_SECONDS=1
MAX_LONG_TRANSACTION_SECONDS=10
MAX_LOCK_WAIT_SECONDS=5

# 检查结果
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

#############################################
# 辅助函数
#############################################

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

print_failure() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNING++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_prerequisites() {
    print_header "检查前置条件"
    
    # 检查必需的命令
    local required_commands=("aws" "mysql" "jq" "bc")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            print_success "命令 $cmd 已安装"
        else
            print_failure "命令 $cmd 未安装"
            exit 1
        fi
    done
    
    # 检查配置是否已修改
    if [[ "$BG_DEPLOYMENT_ID" == "bgd-xxxxxxxxxxxxx" ]]; then
        print_warning "请在脚本头部修改 BG_DEPLOYMENT_ID 配置"
    fi
    
    if [[ "$DB_CLUSTER_ID" == "my-aurora-cluster" ]]; then
        print_warning "请在脚本头部修改 DB_CLUSTER_ID 配置"
    fi
    
    if [[ "$BLUE_DB_HOST" == "blue-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" ]]; then
        print_warning "数据库连接信息未修改，将跳过数据库内部检查"
    fi
}

#############################################
# AWS 层面检查
#############################################

check_bg_deployment_status() {
    print_header "检查蓝绿部署状态"
    
    local status=$(aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "$BG_DEPLOYMENT_ID" \
        --region "$AWS_REGION" \
        --query 'BlueGreenDeployments[0].Status' \
        --output text 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        print_failure "无法获取蓝绿部署状态"
        return 1
    fi
    
    print_info "蓝绿部署状态: $status"
    
    if [[ "$status" == "AVAILABLE" ]]; then
        print_success "蓝绿部署状态正常，可以切换"
    else
        print_failure "蓝绿部署状态不是 AVAILABLE，当前状态: $status"
        return 1
    fi
    
    # 检查复制延迟
    local replication_lag=$(aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "$BG_DEPLOYMENT_ID" \
        --region "$AWS_REGION" \
        --query 'BlueGreenDeployments[0].StatusDetails' \
        --output text 2>/dev/null)
    
    print_info "复制状态详情: $replication_lag"
}

check_cluster_status() {
    print_header "检查集群状态"
    
    local cluster_status=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$DB_CLUSTER_ID" \
        --region "$AWS_REGION" \
        --query 'DBClusters[0].Status' \
        --output text 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        print_failure "无法获取集群状态"
        return 1
    fi
    
    print_info "集群状态: $cluster_status"
    
    if [[ "$cluster_status" == "available" ]]; then
        print_success "集群状态正常"
    else
        print_failure "集群状态异常: $cluster_status"
        return 1
    fi
}

check_cloudwatch_metrics() {
    print_header "检查 CloudWatch 指标"
    
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    local start_time=$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)
    
    # 检查数据库连接数
    print_info "检查数据库连接数（最近 5 分钟平均值）..."
    local connections=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name DatabaseConnections \
        --dimensions Name=DBClusterIdentifier,Value="$DB_CLUSTER_ID" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --region "$AWS_REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    if [[ "$connections" == "None" ]] || [[ -z "$connections" ]]; then
        print_warning "无法获取连接数指标"
    else
        connections=$(printf "%.0f" "$connections")
        print_info "当前平均连接数: $connections"
        
        if (( connections < MAX_CONNECTIONS )); then
            print_success "连接数在安全范围内 (< $MAX_CONNECTIONS)"
        else
            print_failure "连接数过高: $connections (阈值: $MAX_CONNECTIONS)"
        fi
    fi
    
    # 检查 CPU 使用率
    print_info "检查 CPU 使用率..."
    local cpu_usage=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name CPUUtilization \
        --dimensions Name=DBClusterIdentifier,Value="$DB_CLUSTER_ID" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --region "$AWS_REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    if [[ "$cpu_usage" != "None" ]] && [[ -n "$cpu_usage" ]]; then
        cpu_usage=$(printf "%.2f" "$cpu_usage")
        print_info "当前 CPU 使用率: ${cpu_usage}%"
        
        if (( $(echo "$cpu_usage < 70" | bc -l) )); then
            print_success "CPU 使用率正常 (< 70%)"
        else
            print_warning "CPU 使用率较高: ${cpu_usage}%"
        fi
    fi
    
    # 检查写入 IOPS
    print_info "检查写入 IOPS..."
    local write_iops=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name WriteIOPS \
        --dimensions Name=DBClusterIdentifier,Value="$DB_CLUSTER_ID" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --region "$AWS_REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    if [[ "$write_iops" != "None" ]] && [[ -n "$write_iops" ]]; then
        write_iops=$(printf "%.2f" "$write_iops")
        print_info "当前写入 IOPS: $write_iops"
    fi
}

#############################################
# 数据库内部检查
#############################################

execute_mysql_query() {
    local env="$1"  # "blue" 或 "green"
    local query="$2"
    
    local db_host db_user db_password
    
    if [[ "$env" == "blue" ]]; then
        db_host="$BLUE_DB_HOST"
        db_user="$BLUE_DB_USER"
        db_password="$BLUE_DB_PASSWORD"
    else
        db_host="$GREEN_DB_HOST"
        db_user="$GREEN_DB_USER"
        db_password="$GREEN_DB_PASSWORD"
    fi
    
    mysql -h "$db_host" -u "$db_user" -p"$db_password" \
        --skip-column-names --batch -e "$query" 2>/dev/null
}

check_long_transactions() {
    print_header "检查长时间运行的事务"
    
    if [[ "$BLUE_DB_HOST" == "blue-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" ]]; then
        print_warning "跳过：未配置数据库连接"
        return 0
    fi
    
    print_info "检查蓝色环境（生产环境）..."
    
    local query="
    SELECT 
        id,
        user,
        host,
        db,
        command,
        time,
        state,
        LEFT(info, 50) as query_preview
    FROM information_schema.processlist
    WHERE time > $MAX_LONG_TRANSACTION_SECONDS
      AND command != 'Sleep'
      AND user != 'system user'
    ORDER BY time DESC;
    "
    
    local result=$(execute_mysql_query "blue" "$query")
    
    if [[ -z "$result" ]]; then
        print_success "蓝色环境：没有长时间运行的事务 (> ${MAX_LONG_TRANSACTION_SECONDS}s)"
    else
        print_failure "蓝色环境：发现长时间运行的事务:"
        echo "$result" | while IFS=$'\t' read -r id user host db command time state query_preview; do
            echo "  - ID: $id, 用户: $user, 时间: ${time}s, 状态: $state"
            echo "    查询: $query_preview"
        done
        print_info "建议终止这些事务: KILL <process_id>;"
    fi
}

check_lock_waits() {
    print_header "检查锁等待"
    
    if [[ "$BLUE_DB_HOST" == "blue-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" ]]; then
        print_warning "跳过：未配置数据库连接"
        return 0
    fi
    
    print_info "检查蓝色环境（生产环境）..."
    
    local query="
    SELECT 
        r.trx_id waiting_trx_id,
        r.trx_mysql_thread_id waiting_thread,
        r.trx_query waiting_query,
        b.trx_id blocking_trx_id,
        b.trx_mysql_thread_id blocking_thread,
        b.trx_query blocking_query,
        TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) as wait_time
    FROM information_schema.innodb_lock_waits w
    INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
    INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id
    WHERE TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) > $MAX_LOCK_WAIT_SECONDS;
    "
    
    local result=$(execute_mysql_query "blue" "$query")
    
    if [[ -z "$result" ]]; then
        print_success "蓝色环境：没有锁等待 (> ${MAX_LOCK_WAIT_SECONDS}s)"
    else
        print_failure "蓝色环境：发现锁等待:"
        echo "$result" | while IFS=$'\t' read -r waiting_trx waiting_thread waiting_query blocking_trx blocking_thread blocking_query wait_time; do
            echo "  - 等待线程: $waiting_thread, 阻塞线程: $blocking_thread, 等待时间: ${wait_time}s"
        done
        print_info "建议终止阻塞线程"
    fi
}

check_replication_lag() {
    print_header "检查复制延迟（绿色环境）"
    
    if [[ "$GREEN_DB_HOST" == "green-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" ]]; then
        print_warning "跳过：未配置绿色环境数据库连接"
        return 0
    fi
    
    print_info "检查绿色环境的复制状态..."
    
    local query="SHOW SLAVE STATUS\G"
    local result=$(execute_mysql_query "green" "$query")
    
    if [[ -z "$result" ]]; then
        print_info "绿色环境不是副本或未配置复制"
    else
        local seconds_behind=$(echo "$result" | grep "Seconds_Behind_Master:" | awk '{print $2}')
        
        if [[ "$seconds_behind" == "NULL" ]]; then
            print_warning "复制状态异常"
        elif [[ -n "$seconds_behind" ]]; then
            print_info "复制延迟: ${seconds_behind}s"
            
            if (( seconds_behind <= MAX_REPLICATION_LAG_SECONDS )); then
                print_success "复制延迟在安全范围内 (≤ ${MAX_REPLICATION_LAG_SECONDS}s)"
            else
                print_failure "复制延迟过高: ${seconds_behind}s (阈值: ${MAX_REPLICATION_LAG_SECONDS}s)"
            fi
        fi
    fi
}

check_active_connections() {
    print_header "检查活跃连接详情"
    
    if [[ "$BLUE_DB_HOST" == "blue-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" ]]; then
        print_warning "跳过：未配置数据库连接"
        return 0
    fi
    
    print_info "检查蓝色环境（生产环境）..."
    
    local query="
    SELECT 
        command,
        COUNT(*) as count
    FROM information_schema.processlist
    WHERE user != 'system user'
    GROUP BY command
    ORDER BY count DESC;
    "
    
    local result=$(execute_mysql_query "blue" "$query")
    
    if [[ -n "$result" ]]; then
        print_info "连接类型分布:"
        echo "$result" | while IFS=$'\t' read -r command count; do
            echo "  - $command: $count"
        done
    fi
    
    # 统计总连接数
    local total_connections=$(execute_mysql_query "blue" "SELECT COUNT(*) FROM information_schema.processlist WHERE user != 'system user';")
    print_info "当前活跃连接总数: $total_connections"
    
    if (( total_connections < MAX_CONNECTIONS )); then
        print_success "活跃连接数在安全范围内"
    else
        print_failure "活跃连接数过高: $total_connections"
    fi
}

check_pending_ddl() {
    print_header "检查待执行的 DDL 操作"
    
    if [[ "$BLUE_DB_HOST" == "blue-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" ]]; then
        print_warning "跳过：未配置数据库连接"
        return 0
    fi
    
    print_info "检查蓝色环境（生产环境）..."
    
    local query="
    SELECT 
        id,
        user,
        time,
        state,
        info
    FROM information_schema.processlist
    WHERE info LIKE '%ALTER TABLE%'
       OR info LIKE '%CREATE INDEX%'
       OR info LIKE '%DROP INDEX%'
       OR info LIKE '%OPTIMIZE TABLE%';
    "
    
    local result=$(execute_mysql_query "blue" "$query")
    
    if [[ -z "$result" ]]; then
        print_success "没有正在执行的 DDL 操作"
    else
        print_failure "发现正在执行的 DDL 操作:"
        echo "$result" | while IFS=$'\t' read -r id user time state info; do
            echo "  - ID: $id, 用户: $user, 时间: ${time}s"
            echo "    SQL: $info"
        done
        print_warning "DDL 操作可能导致切换延迟或失败"
    fi
}

#############################################
# 生成报告
#############################################

generate_summary() {
    print_header "检查结果汇总"
    
    echo -e "\n总计检查项:"
    echo -e "  ${GREEN}通过: $CHECKS_PASSED${NC}"
    echo -e "  ${RED}失败: $CHECKS_FAILED${NC}"
    echo -e "  ${YELLOW}警告: $CHECKS_WARNING${NC}"
    
    echo -e "\n切换建议:"
    if (( CHECKS_FAILED == 0 )); then
        echo -e "${GREEN}✓ 所有关键检查通过，可以安全执行切换${NC}"
        echo -e "\n执行切换命令:"
        echo -e "${BLUE}aws rds switchover-blue-green-deployment \\${NC}"
        echo -e "${BLUE}    --blue-green-deployment-identifier $BG_DEPLOYMENT_ID \\${NC}"
        echo -e "${BLUE}    --switchover-timeout 300 \\${NC}"
        echo -e "${BLUE}    --region $AWS_REGION${NC}"
        return 0
    elif (( CHECKS_FAILED <= 2 )) && (( CHECKS_WARNING > 0 )); then
        echo -e "${YELLOW}⚠ 存在警告项，建议评估后再执行切换${NC}"
        return 1
    else
        echo -e "${RED}✗ 存在严重问题，不建议立即切换${NC}"
        echo -e "\n建议操作:"
        echo -e "  1. 解决上述失败的检查项"
        echo -e "  2. 等待系统负载降低"
        echo -e "  3. 终止长时间运行的事务"
        echo -e "  4. 选择更低峰的时段"
        return 2
    fi
}

#############################################
# 主函数
#############################################

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║   Aurora 蓝绿部署切换前检查脚本                       ║"
    echo "║   检查时间: $(date '+%Y-%m-%d %H:%M:%S')                      ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # 执行检查
    check_prerequisites
    check_bg_deployment_status
    check_cluster_status
    check_cloudwatch_metrics
    check_long_transactions
    check_lock_waits
    check_replication_lag
    check_active_connections
    check_pending_ddl
    
    # 生成报告
    generate_summary
    exit_code=$?
    
    echo -e "\n${BLUE}检查完成！${NC}"
    exit $exit_code
}

# 执行主函数
main
