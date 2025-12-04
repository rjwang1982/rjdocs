# S3 + rclone 挂载方案 POC SOP（SUSE 15 SP5 版）

**作者**: RJ.Wang  
**邮箱**: wangrenjun@gmail.com  
**创建时间**: 2025-12-03  
**用途**: SUSE Linux Enterprise Server 15 SP5 环境下 S3 + rclone 挂载方案验证标准操作流程

---

## 📋 POC 目标

验证 S3 + rclone 挂载方案在 SUSE 15 SP5 环境下的可行性，评估：
- ✅ 基本功能（读写、删除、重命名）
- ✅ 性能表现（延迟、吞吐量）
- ✅ 稳定性（长时间运行、异常恢复）
- ✅ 系统集成（systemd 服务、开机自动挂载）
- ✅ 成本估算（存储、请求、数据传输）

---

## 🎯 测试环境

### 系统要求
- **操作系统**: SUSE Linux Enterprise Server 15 SP5
- **内核版本**: 5.14.21 或更高
- **网络**: 稳定的互联网连接
- **权限**: root 或 sudo 权限
- **磁盘空间**: 至少 2GB 可用空间（用于缓存）

### AWS 资源
- **区域**: cn-northwest-1（宁夏）或 cn-north-1（北京）
- **S3 存储桶**: 测试专用，POC 结束后可删除
- **IAM 用户**: 具有 S3FullAccess 权限

---

## 📦 准备工作

### 1. 系统更新和基础软件安装

```bash
# 更新系统
sudo zypper refresh
sudo zypper update -y

# 安装必要的工具
sudo zypper install -y \
  curl \
  wget \
  unzip \
  fuse \
  fuse-devel \
  gcc \
  make

# 验证 FUSE 支持
modprobe fuse
lsmod | grep fuse
```

### 2. 安装 AWS CLI

```bash
# 下载 AWS CLI v2
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# 解压并安装
unzip awscliv2.zip
sudo ./aws/install

# 验证安装
aws --version

# 配置 AWS 凭证
aws configure --profile poc-test
# 按提示输入：
# AWS Access Key ID: [您的 Access Key]
# AWS Secret Access Key: [您的 Secret Key]
# Default region name: cn-northwest-1
# Default output format: json
```

### 3. 安装 rclone

#### 方式 A: 使用官方脚本（推荐）

```bash
# 下载并安装 rclone
curl https://rclone.org/install.sh | sudo bash

# 验证安装
rclone version
```

#### 方式 B: 手动安装

```bash
# 下载最新版本
cd /tmp
wget https://downloads.rclone.org/rclone-current-linux-amd64.zip

# 解压
unzip rclone-current-linux-amd64.zip

# 安装到系统路径
cd rclone-*-linux-amd64
sudo cp rclone /usr/local/bin/
sudo chown root:root /usr/local/bin/rclone
sudo chmod 755 /usr/local/bin/rclone

# 安装 man 手册（可选）
sudo mkdir -p /usr/local/share/man/man1
sudo cp rclone.1 /usr/local/share/man/man1/
sudo mandb

# 验证安装
rclone version
which rclone
```

### 4. 配置用户权限

```bash
# 将当前用户添加到 fuse 组
sudo usermod -aG fuse $USER

# 验证 FUSE 配置
cat /etc/fuse.conf

# 如果需要，允许非 root 用户挂载
sudo sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf

# 重新登录以使组权限生效
# 或执行：
newgrp fuse
```

---

## 🔧 配置步骤

### 步骤 1: 创建测试 S3 存储桶

```bash
# 设置 AWS Profile
export AWS_PROFILE=poc-test

# 验证当前账号
aws sts get-caller-identity

# 创建测试存储桶（存储桶名称必须全局唯一）
BUCKET_NAME="rclone-poc-test-$(date +%Y%m%d-%H%M%S)"
aws s3 mb s3://${BUCKET_NAME} --region cn-northwest-1

# 记录存储桶名称
echo "测试存储桶: ${BUCKET_NAME}"
echo ${BUCKET_NAME} > /tmp/rclone-poc-bucket.txt
```

### 步骤 2: 配置 rclone

#### 方式 A: 交互式配置（推荐）

```bash
# 启动配置向导
rclone config

# 按照提示操作：
# n) New remote
# name> s3-poc
# Storage> s3
# provider> AWS
# env_auth> 1 (使用环境变量中的 AWS 凭证)
# region> cn-northwest-1
# endpoint> s3.cn-northwest-1.amazonaws.com.cn
# 其他选项保持默认，按回车
# y) Yes this is OK
# q) Quit config
```

#### 方式 B: 直接创建配置文件

```bash
# 创建 rclone 配置目录
mkdir -p ~/.config/rclone

# 创建配置文件
cat > ~/.config/rclone/rclone.conf << 'EOF'
[s3-poc]
type = s3
provider = AWS
env_auth = true
region = cn-northwest-1
endpoint = s3.cn-northwest-1.amazonaws.com.cn
acl = private
EOF

# 设置权限
chmod 600 ~/.config/rclone/rclone.conf

# 验证配置
rclone config show s3-poc
```

### 步骤 3: 验证 S3 连接

```bash
# 读取存储桶名称
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)

# 测试列出存储桶内容
rclone ls s3-poc:${BUCKET_NAME}

# 上传测试文件
echo "Hello rclone POC - $(date)" > /tmp/test.txt
rclone copy /tmp/test.txt s3-poc:${BUCKET_NAME}/

# 验证上传
rclone ls s3-poc:${BUCKET_NAME}

# 下载测试
rclone copy s3-poc:${BUCKET_NAME}/test.txt /tmp/test-download.txt
cat /tmp/test-download.txt
```

---

## 🚀 挂载测试

### 测试 1: 基本挂载

```bash
# 创建挂载点
sudo mkdir -p /mnt/s3-poc
sudo chown $USER:$USER /mnt/s3-poc

# 读取存储桶名称
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)

# 基本挂载（前台运行，用于测试）
rclone mount s3-poc:${BUCKET_NAME} /mnt/s3-poc \
  --vfs-cache-mode writes \
  --verbose

# 在另一个终端窗口测试
ls -la /mnt/s3-poc
cat /mnt/s3-poc/test.txt
```

**测试项目**:
- [ ] 能否看到挂载点内容
- [ ] 能否读取文件: `cat /mnt/s3-poc/test.txt`
- [ ] 能否创建文件: `echo "test" > /mnt/s3-poc/new.txt`
- [ ] 能否删除文件: `rm /mnt/s3-poc/new.txt`

**停止挂载**: 在运行 rclone mount 的终端按 `Ctrl+C`，或在另一终端执行：
```bash
fusermount -u /mnt/s3-poc
```

### 测试 2: 优化挂载（推荐配置）

```bash
# 读取存储桶名称
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)

# 使用优化参数挂载（后台运行）
rclone mount s3-poc:${BUCKET_NAME} /mnt/s3-poc \
  --vfs-cache-mode full \
  --vfs-cache-max-size 1G \
  --vfs-cache-max-age 1h \
  --buffer-size 32M \
  --dir-cache-time 5m \
  --poll-interval 15s \
  --allow-other \
  --log-file ~/rclone-mount-poc.log \
  --log-level INFO \
  --daemon

# 验证挂载
mount | grep rclone
df -h /mnt/s3-poc
ls -la /mnt/s3-poc
```

**参数说明**:
- `--vfs-cache-mode full`: 完整缓存模式，性能最好
- `--vfs-cache-max-size 1G`: 最大缓存 1GB
- `--vfs-cache-max-age 1h`: 缓存保留 1 小时
- `--buffer-size 32M`: 读写缓冲区 32MB
- `--dir-cache-time 5m`: 目录列表缓存 5 分钟
- `--poll-interval 15s`: 每 15 秒检查变化
- `--allow-other`: 允许其他用户访问
- `--daemon`: 后台运行

### 测试 3: 创建 systemd 服务（生产环境推荐）

```bash
# 创建 systemd 服务文件
sudo tee /etc/systemd/system/rclone-s3-poc.service > /dev/null << 'EOF'
[Unit]
Description=RClone S3 Mount POC
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
Environment=AWS_PROFILE=poc-test
ExecStartPre=/bin/mkdir -p /mnt/s3-poc
ExecStart=/usr/local/bin/rclone mount s3-poc:BUCKET_NAME /mnt/s3-poc \
  --vfs-cache-mode full \
  --vfs-cache-max-size 1G \
  --vfs-cache-max-age 1h \
  --buffer-size 32M \
  --dir-cache-time 5m \
  --poll-interval 15s \
  --allow-other \
  --log-file /var/log/rclone-mount-poc.log \
  --log-level INFO
ExecStop=/bin/fusermount -u /mnt/s3-poc
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

# 替换存储桶名称
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)
sudo sed -i "s/BUCKET_NAME/${BUCKET_NAME}/" /etc/systemd/system/rclone-s3-poc.service

# 复制 AWS 凭证到 root 用户（如果使用 root 运行服务）
sudo mkdir -p /root/.aws
sudo cp ~/.aws/credentials /root/.aws/
sudo cp ~/.aws/config /root/.aws/

# 复制 rclone 配置到 root 用户
sudo mkdir -p /root/.config/rclone
sudo cp ~/.config/rclone/rclone.conf /root/.config/rclone/

# 重新加载 systemd
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start rclone-s3-poc

# 查看状态
sudo systemctl status rclone-s3-poc

# 设置开机自启
sudo systemctl enable rclone-s3-poc

# 查看日志
sudo journalctl -u rclone-s3-poc -f
```

---

## 🧪 功能测试

### 测试 4: 文件操作测试

```bash
# 进入挂载目录
cd /mnt/s3-poc

# 1. 创建测试文件
echo "POC Test $(date)" > test-write.txt
cat test-write.txt

# 2. 创建目录
mkdir test-dir
ls -la

# 3. 复制文件
cp test-write.txt test-dir/
ls -la test-dir/

# 4. 重命名文件
mv test-write.txt renamed.txt
ls -la

# 5. 修改文件权限
chmod 644 renamed.txt
ls -l renamed.txt

# 6. 创建符号链接（测试是否支持）
ln -s renamed.txt link-test.txt
ls -la

# 7. 删除文件
rm renamed.txt link-test.txt
ls -la

# 8. 删除目录
rm -rf test-dir
ls -la
```

**记录结果**:
- [ ] 创建文件: ✅ / ❌
- [ ] 读取文件: ✅ / ❌
- [ ] 创建目录: ✅ / ❌
- [ ] 复制文件: ✅ / ❌
- [ ] 重命名文件: ✅ / ❌
- [ ] 修改权限: ✅ / ❌
- [ ] 符号链接: ✅ / ❌
- [ ] 删除文件: ✅ / ❌
- [ ] 删除目录: ✅ / ❌

### 测试 5: 性能测试

#### 写入性能测试

```bash
cd /mnt/s3-poc

# 测试小文件写入（1MB x 10）
echo "=== 小文件写入测试 ==="
time for i in {1..10}; do
  dd if=/dev/zero of=small-$i.dat bs=1M count=1 2>/dev/null
done

# 测试大文件写入（100MB x 1）
echo "=== 大文件写入测试 ==="
time dd if=/dev/zero of=large.dat bs=1M count=100

# 测试顺序写入
echo "=== 顺序写入测试（500MB）==="
time dd if=/dev/zero of=seq-write.dat bs=1M count=500

# 清理测试文件
rm -f small-*.dat large.dat seq-write.dat
```

#### 读取性能测试

```bash
cd /mnt/s3-poc

# 创建测试文件（100MB）
dd if=/dev/zero of=read-test.dat bs=1M count=100

# 清除系统缓存
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

# 测试读取性能
echo "=== 首次读取测试 ==="
time dd if=read-test.dat of=/dev/null bs=1M

# 再次读取（测试缓存效果）
echo "=== 缓存读取测试 ==="
time dd if=read-test.dat of=/dev/null bs=1M

# 测试随机读取
echo "=== 随机读取测试 ==="
time dd if=read-test.dat of=/dev/null bs=4K skip=$((RANDOM % 25600)) count=1000

# 清理
rm read-test.dat
```

#### 并发性能测试

```bash
cd /mnt/s3-poc

# 创建并发测试脚本
cat > /tmp/concurrent-test.sh << 'EOF'
#!/bin/bash
PROCESS_ID=$1
for i in {1..5}; do
  echo "Process $PROCESS_ID - File $i - $(date)" > /mnt/s3-poc/process-${PROCESS_ID}-file-${i}.txt
  sleep 1
done
EOF

chmod +x /tmp/concurrent-test.sh

# 并发执行（5个进程）
echo "=== 并发写入测试 ==="
time (
  /tmp/concurrent-test.sh 1 &
  /tmp/concurrent-test.sh 2 &
  /tmp/concurrent-test.sh 3 &
  /tmp/concurrent-test.sh 4 &
  /tmp/concurrent-test.sh 5 &
  wait
)

# 验证结果
ls -la /mnt/s3-poc/process-*.txt
wc -l /mnt/s3-poc/process-*.txt

# 清理
rm -f /mnt/s3-poc/process-*.txt
```

**记录性能数据**:
```
小文件写入（1MB x 10）: _____ 秒
大文件写入（100MB）: _____ 秒
顺序写入（500MB）: _____ 秒
首次读取（100MB）: _____ 秒
缓存读取（100MB）: _____ 秒
随机读取（4K x 1000）: _____ 秒
并发写入（5进程 x 5文件）: _____ 秒
```

### 测试 6: 多用户访问测试

```bash
# 创建测试用户
sudo useradd -m testuser1
sudo useradd -m testuser2

# 测试用户1访问
sudo -u testuser1 ls -la /mnt/s3-poc
sudo -u testuser1 touch /mnt/s3-poc/user1-test.txt

# 测试用户2访问
sudo -u testuser2 ls -la /mnt/s3-poc
sudo -u testuser2 touch /mnt/s3-poc/user2-test.txt

# 验证权限
ls -la /mnt/s3-poc/user*.txt

# 清理测试用户
sudo userdel -r testuser1
sudo userdel -r testuser2
rm -f /mnt/s3-poc/user*.txt
```

**记录结果**:
- [ ] 多用户可访问: ✅ / ❌
- [ ] 权限隔离: ✅ / ❌

---

## 📊 稳定性测试

### 测试 7: 长时间运行测试

```bash
# 创建长时间测试脚本
cat > ~/long-run-test.sh << 'EOF'
#!/bin/bash

MOUNT_POINT=/mnt/s3-poc
LOG_FILE=~/long-run-test.log
DURATION=3600  # 测试 1 小时

echo "开始长时间运行测试: $(date)" | tee -a $LOG_FILE
echo "测试时长: ${DURATION} 秒" | tee -a $LOG_FILE

START_TIME=$(date +%s)
COUNTER=0

while [ $(($(date +%s) - START_TIME)) -lt $DURATION ]; do
  COUNTER=$((COUNTER + 1))
  
  # 写入测试
  echo "Test $COUNTER at $(date)" > $MOUNT_POINT/long-run-$COUNTER.txt
  
  # 读取测试
  cat $MOUNT_POINT/long-run-$COUNTER.txt > /dev/null
  
  # 删除测试
  rm $MOUNT_POINT/long-run-$COUNTER.txt
  
  # 每 10 次记录一次
  if [ $((COUNTER % 10)) -eq 0 ]; then
    echo "完成 $COUNTER 次操作 at $(date)" | tee -a $LOG_FILE
  fi
  
  sleep 10
done

echo "测试完成: $(date)" | tee -a $LOG_FILE
echo "总操作次数: $COUNTER" | tee -a $LOG_FILE
EOF

chmod +x ~/long-run-test.sh

# 后台运行测试
nohup ~/long-run-test.sh &

# 查看测试进度
tail -f ~/long-run-test.log
```

### 测试 8: 系统重启测试

```bash
# 1. 确保 systemd 服务已启用
sudo systemctl enable rclone-s3-poc

# 2. 创建测试文件
echo "Before reboot $(date)" > /mnt/s3-poc/reboot-test.txt

# 3. 重启系统
sudo reboot

# 4. 系统重启后，验证自动挂载
mount | grep rclone
ls -la /mnt/s3-poc
cat /mnt/s3-poc/reboot-test.txt

# 5. 创建新文件验证功能
echo "After reboot $(date)" > /mnt/s3-poc/reboot-test2.txt
```

**记录结果**:
- [ ] 开机自动挂载: ✅ / ❌
- [ ] 数据完整性: ✅ / ❌
- [ ] 服务自动启动: ✅ / ❌

### 测试 9: 网络中断恢复测试

```bash
# 1. 正常创建文件
echo "Before disconnect $(date)" > /mnt/s3-poc/recovery-test.txt

# 2. 模拟网络中断
sudo ip link set eth0 down
# 或使用防火墙阻断
# sudo iptables -A OUTPUT -d s3.cn-northwest-1.amazonaws.com.cn -j DROP

# 3. 等待 30 秒
sleep 30

# 4. 尝试操作（应该失败或挂起）
echo "During disconnect $(date)" > /mnt/s3-poc/recovery-test2.txt

# 5. 恢复网络
sudo ip link set eth0 up
# 或清除防火墙规则
# sudo iptables -D OUTPUT -d s3.cn-northwest-1.amazonaws.com.cn -j DROP

# 6. 等待 rclone 自动重连（观察日志）
sudo journalctl -u rclone-s3-poc -f

# 7. 验证恢复后的操作
echo "After reconnect $(date)" > /mnt/s3-poc/recovery-test3.txt
ls -la /mnt/s3-poc/recovery-test*.txt

# 8. 验证数据完整性
cat /mnt/s3-poc/recovery-test.txt
cat /mnt/s3-poc/recovery-test3.txt
```

**记录结果**:
- [ ] 网络中断时操作行为: _____
- [ ] 自动重连时间: _____ 秒
- [ ] 重连后数据完整性: ✅ / ❌
- [ ] systemd 自动重启: ✅ / ❌

### 测试 10: 高负载测试

```bash
# 创建高负载测试脚本
cat > ~/stress-test.sh << 'EOF'
#!/bin/bash

MOUNT_POINT=/mnt/s3-poc
DURATION=600  # 10 分钟
PROCESSES=10

echo "开始高负载测试: $(date)"
echo "并发进程数: $PROCESSES"
echo "测试时长: $DURATION 秒"

for i in $(seq 1 $PROCESSES); do
  (
    START_TIME=$(date +%s)
    COUNTER=0
    while [ $(($(date +%s) - START_TIME)) -lt $DURATION ]; do
      COUNTER=$((COUNTER + 1))
      dd if=/dev/urandom of=$MOUNT_POINT/stress-p${i}-${COUNTER}.dat bs=1M count=1 2>/dev/null
      rm $MOUNT_POINT/stress-p${i}-${COUNTER}.dat
    done
    echo "进程 $i 完成 $COUNTER 次操作"
  ) &
done

wait
echo "高负载测试完成: $(date)"
EOF

chmod +x ~/stress-test.sh

# 运行测试
~/stress-test.sh

# 监控系统资源
# 在另一个终端运行：
top -b -n 1 | head -20
iostat -x 1 10
```

**记录结果**:
- [ ] 系统稳定性: ✅ / ❌
- [ ] CPU 使用率: _____ %
- [ ] 内存使用率: _____ %
- [ ] 错误率: _____ %

---

## 💰 成本评估

### 测试 11: 成本计算

```bash
# 获取存储桶统计信息
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)

# 查看存储用量
aws s3 ls s3://${BUCKET_NAME} --recursive --human-readable --summarize

# 创建成本估算脚本
cat > ~/cost-estimate.sh << 'EOF'
#!/bin/bash

# 输入参数
STORAGE_GB=${1:-10}        # 存储容量 GB
REQUESTS_PER_DAY=${2:-1000} # 每天请求次数
TRANSFER_GB=${3:-5}        # 每月传输 GB

# 中国区宁夏价格（2025）
STORAGE_PRICE=0.144        # ¥/GB/月
PUT_PRICE=0.01             # ¥/千次
GET_PRICE=0.001            # ¥/千次
TRANSFER_PRICE=0.6         # ¥/GB

# 计算
STORAGE_COST=$(echo "$STORAGE_GB * $STORAGE_PRICE" | bc)
PUT_COST=$(echo "$REQUESTS_PER_DAY * 30 / 1000 * $PUT_PRICE * 0.5" | bc)
GET_COST=$(echo "$REQUESTS_PER_DAY * 30 / 1000 * $GET_PRICE * 0.5" | bc)
TRANSFER_COST=$(echo "$TRANSFER_GB * $TRANSFER_PRICE" | bc)
TOTAL_COST=$(echo "$STORAGE_COST + $PUT_COST + $GET_COST + $TRANSFER_COST" | bc)

echo "=== S3 + rclone 月成本估算 ==="
echo "存储容量: ${STORAGE_GB} GB"
echo "每日请求: ${REQUESTS_PER_DAY} 次"
echo "月传输量: ${TRANSFER_GB} GB"
echo ""
echo "存储成本: ¥${STORAGE_COST}"
echo "PUT 请求: ¥${PUT_COST}"
echo "GET 请求: ¥${GET_COST}"
echo "数据传输: ¥${TRANSFER_COST}"
echo "----------------------------"
echo "总计: ¥${TOTAL_COST} / 月"
EOF

chmod +x ~/cost-estimate.sh

# 运行成本估算
~/cost-estimate.sh 10 1000 5
```

---

## 🔍 监控和日志

### 查看 rclone 日志

```bash
# 实时查看日志（systemd 服务）
sudo journalctl -u rclone-s3-poc -f

# 查看最近 100 行日志
sudo journalctl -u rclone-s3-poc -n 100

# 查看错误日志
sudo journalctl -u rclone-s3-poc -p err

# 查看日志文件
tail -f /var/log/rclone-mount-poc.log

# 查看错误日志
grep -i error /var/log/rclone-mount-poc.log
```

### 监控挂载状态

```bash
# 创建监控脚本
cat > ~/monitor-rclone.sh << 'EOF'
#!/bin/bash

MOUNT_POINT=/mnt/s3-poc
LOG_FILE=~/monitor-rclone.log

while true; do
  if mount | grep -q "$MOUNT_POINT"; then
    echo "[$(date)] ✅ rclone 挂载正常" | tee -a $LOG_FILE
  else
    echo "[$(date)] ❌ rclone 挂载断开，尝试重启服务..." | tee -a $LOG_FILE
    sudo systemctl restart rclone-s3-poc
  fi
  sleep 60
done
EOF

chmod +x ~/monitor-rclone.sh

# 后台运行监控
nohup ~/monitor-rclone.sh &

# 查看监控日志
tail -f ~/monitor-rclone.log
```

### 系统资源监控

```bash
# 查看 rclone 进程资源使用
ps aux | grep rclone

# 查看内存使用
free -h

# 查看磁盘 I/O
iostat -x 1 5

# 查看网络流量
iftop -i eth0

# 查看挂载点使用情况
df -h /mnt/s3-poc

# 查看缓存目录大小
du -sh ~/.cache/rclone/
```

### 配置日志轮转

```bash
# 创建 logrotate 配置
sudo tee /etc/logrotate.d/rclone-s3-poc > /dev/null << 'EOF'
/var/log/rclone-mount-poc.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    postrotate
        systemctl reload rclone-s3-poc > /dev/null 2>&1 || true
    endscript
}
EOF

# 测试 logrotate 配置
sudo logrotate -d /etc/logrotate.d/rclone-s3-poc
```

---

## 🧹 清理工作

### 卸载挂载

```bash
# 方式 1: 停止 systemd 服务
sudo systemctl stop rclone-s3-poc

# 方式 2: 手动卸载
fusermount -u /mnt/s3-poc

# 方式 3: 强制卸载
sudo umount -f /mnt/s3-poc

# 验证卸载
mount | grep rclone
```

### 停止后台进程

```bash
# 停止 systemd 服务
sudo systemctl stop rclone-s3-poc
sudo systemctl disable rclone-s3-poc

# 停止监控脚本
pkill -f "monitor-rclone.sh"

# 停止长时间测试
pkill -f "long-run-test.sh"

# 停止所有 rclone 进程
pkill rclone
```

### 删除测试资源

```bash
# 删除 S3 存储桶内容
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)
aws s3 rm s3://${BUCKET_NAME} --recursive

# 删除存储桶
aws s3 rb s3://${BUCKET_NAME}

# 删除本地文件
rm -rf /mnt/s3-poc
rm -f ~/rclone-mount-poc.log
rm -f ~/long-run-test.log
rm -f ~/monitor-rclone.log
rm -f /tmp/rclone-poc-bucket.txt

# 删除脚本
rm -f ~/long-run-test.sh
rm -f ~/monitor-rclone.sh
rm -f ~/cost-estimate.sh
rm -f /tmp/concurrent-test.sh
rm -f ~/stress-test.sh

# 删除 systemd 服务
sudo rm -f /etc/systemd/system/rclone-s3-poc.service
sudo systemctl daemon-reload

# 删除日志轮转配置
sudo rm -f /etc/logrotate.d/rclone-s3-poc

# 清理 rclone 缓存
rm -rf ~/.cache/rclone/

# 删除 rclone 配置（可选）
rclone config delete s3-poc
```

### 卸载软件（可选）

```bash
# 卸载 rclone
sudo rm -f /usr/local/bin/rclone
sudo rm -f /usr/local/share/man/man1/rclone.1

# 卸载 AWS CLI
sudo rm -rf /usr/local/aws-cli
sudo rm -f /usr/local/bin/aws
sudo rm -f /usr/local/bin/aws_completer

# 删除配置文件
rm -rf ~/.aws
rm -rf ~/.config/rclone
```

---

## 📝 POC 报告模板

### 测试结果总结

#### 1. 功能测试
| 功能 | 状态 | 备注 |
|------|------|------|
| 文件读取 | ✅ / ❌ | |
| 文件写入 | ✅ / ❌ | |
| 文件删除 | ✅ / ❌ | |
| 目录操作 | ✅ / ❌ | |
| 文件重命名 | ✅ / ❌ | |
| 权限管理 | ✅ / ❌ | |
| 符号链接 | ✅ / ❌ | |
| 多用户访问 | ✅ / ❌ | |

#### 2. 性能测试
| 测试项 | 结果 | 备注 |
|--------|------|------|
| 小文件写入（1MB x 10） | ___ 秒 | |
| 大文件写入（100MB） | ___ 秒 | |
| 顺序写入（500MB） | ___ 秒 | |
| 首次读取（100MB） | ___ 秒 | |
| 缓存读取（100MB） | ___ 秒 | |
| 随机读取（4K x 1000） | ___ 秒 | |
| 并发写入（5进程） | ___ 秒 | |

#### 3. 稳定性测试
| 测试项 | 结果 | 备注 |
|--------|------|------|
| 长时间运行（1小时） | ✅ / ❌ | |
| 系统重启自动挂载 | ✅ / ❌ | |
| 网络中断恢复 | ✅ / ❌ | |
| 高负载测试 | ✅ / ❌ | |
| systemd 服务稳定性 | ✅ / ❌ | |

#### 4. 系统集成
| 项目 | 状态 | 备注 |
|------|------|------|
| systemd 服务 | ✅ / ❌ | |
| 开机自动挂载 | ✅ / ❌ | |
| 日志轮转 | ✅ / ❌ | |
| 多用户支持 | ✅ / ❌ | |

#### 5. 成本估算
```
预计存储容量: ___ GB
预计每日请求: ___ 次
预计月传输量: ___ GB
----------------------------
预计月成本: ¥___ 元
```

#### 6. 优缺点总结

**优点**:
- ✅ 按使用量计费，成本可控
- ✅ 无需预配置容量
- ✅ 与 Linux 系统集成良好
- ✅ 支持 systemd 服务管理
- ✅ 支持开机自动挂载
- ✅ 

**缺点**:
- ❌ 不支持文件锁
- ❌ 性能不如本地磁盘
- ❌ 依赖网络连接
- ❌ 首次访问有延迟
- ❌ 

#### 7. 适用场景评估

**✅ 推荐使用的场景**:
- 应用日志存储
- 备份和归档
- 静态文件存储
- 媒体文件存储
- 数据分发

**❌ 不推荐使用的场景**:
- 数据库文件存储
- 需要文件锁的应用
- 高频率小文件操作
- 对延迟敏感的应用
- 多进程并发写入同一文件

#### 8. 最终建议

**是否推荐采用**: ✅ 推荐 / ⚠️ 有条件推荐 / ❌ 不推荐

**推荐理由**:
- 

**注意事项**:
- 

**替代方案**:
- 如果需要文件锁，建议使用 EFS（按使用量计费）
- 如果可以修改应用代码，建议直接使用 S3 SDK
- 如果是 Windows 环境，建议使用 FSx for Windows

---

## 🔗 参考资源

### 官方文档
- [rclone 官方文档](https://rclone.org/docs/)
- [rclone mount 文档](https://rclone.org/commands/rclone_mount/)
- [rclone S3 配置](https://rclone.org/s3/)
- [AWS S3 定价](https://aws.amazon.com/cn/s3/pricing/)
- [SUSE Linux Enterprise Server 文档](https://documentation.suse.com/sles/15-SP5/)

### 相关文档
- [AWS 存储服务选择指南](./AWS存储服务选择指南.md)
- [rclone Windows 版 POC SOP](./rclone-s3-mount-poc-sop-windows.md)

### 常见问题
- [rclone FAQ](https://rclone.org/faq/)
- [FUSE 文档](https://github.com/libfuse/libfuse)

### 社区支持
- [rclone 论坛](https://forum.rclone.org/)
- [rclone GitHub](https://github.com/rclone/rclone)
- [SUSE 社区](https://www.suse.com/support/)

---

## ⚠️ 重要注意事项

### 1. 文件锁限制
- **rclone 不支持文件锁**
- 多进程同时写入同一文件会导致数据损坏
- 不适合需要并发写入的场景
- 不适合数据库文件存储

### 2. 性能考虑
- 首次访问文件会有网络延迟（通常 100-500ms）
- 启用 `--vfs-cache-mode full` 后性能显著提升
- 大文件传输速度取决于网络带宽
- 建议配置足够的缓存空间（1-2GB）

### 3. 网络依赖
- 完全依赖网络连接
- 网络中断会导致挂载不可用
- 建议配置 systemd 自动重启
- 建议配置监控和告警

### 4. 成本控制
- 频繁的小文件操作会产生大量 API 请求
- 建议启用缓存减少请求次数
- 定期检查 AWS 账单
- 使用 S3 生命周期策略管理数据

### 5. 安全建议
- 使用 IAM 用户而非 root 账号
- 遵循最小权限原则
- 定期轮换访问密钥
- 启用 S3 存储桶加密
- 限制 S3 存储桶访问策略
- 使用 VPC 端点减少公网流量

### 6. SUSE 特定注意事项
- 确保 FUSE 内核模块已加载
- 检查 SELinux/AppArmor 策略
- 配置防火墙允许 S3 访问
- 使用 systemd 管理服务
- 定期更新系统补丁

### 7. 生产环境建议
- 使用 systemd 服务而非手动挂载
- 配置日志轮转避免日志文件过大
- 配置监控和告警
- 定期备份 rclone 配置
- 文档化运维流程

---

## 🆘 故障排查

### 问题 1: 挂载失败 - FUSE 相关

**症状**: 执行 `rclone mount` 后报错 "fuse: device not found"

**解决方案**:
```bash
# 1. 检查 FUSE 模块
lsmod | grep fuse

# 2. 加载 FUSE 模块
sudo modprobe fuse

# 3. 设置开机自动加载
echo "fuse" | sudo tee -a /etc/modules-load.d/fuse.conf

# 4. 检查 FUSE 配置
cat /etc/fuse.conf

# 5. 允许非 root 用户挂载
sudo sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
```

### 问题 2: 权限被拒绝

**症状**: 提示 "Permission denied" 或 "Access denied"

**解决方案**:
```bash
# 1. 检查用户组
groups $USER

# 2. 添加到 fuse 组
sudo usermod -aG fuse $USER
newgrp fuse

# 3. 检查挂载点权限
ls -ld /mnt/s3-poc
sudo chown $USER:$USER /mnt/s3-poc

# 4. 检查 AWS 凭证
aws sts get-caller-identity --profile poc-test

# 5. 检查 S3 权限
aws s3 ls s3://bucket-name --profile poc-test
```

### 问题 3: 访问速度慢

**症状**: 打开文件或列出目录很慢

**解决方案**:
```bash
# 1. 增加缓存设置
rclone mount s3-poc:bucket /mnt/s3-poc \
  --vfs-cache-mode full \
  --vfs-cache-max-size 2G \
  --buffer-size 64M \
  --dir-cache-time 10m \
  --daemon

# 2. 检查网络延迟
ping s3.cn-northwest-1.amazonaws.com.cn

# 3. 使用 VPC 端点（如果在 EC2 上）
# 配置 S3 VPC 端点减少延迟

# 4. 检查缓存目录空间
df -h ~/.cache/rclone/
```

### 问题 4: systemd 服务启动失败

**症状**: `systemctl start rclone-s3-poc` 失败

**解决方案**:
```bash
# 1. 查看详细错误
sudo systemctl status rclone-s3-poc -l
sudo journalctl -u rclone-s3-poc -n 50

# 2. 检查配置文件
sudo systemctl cat rclone-s3-poc

# 3. 检查 rclone 配置
sudo -u root rclone config show s3-poc

# 4. 检查 AWS 凭证
sudo -u root aws sts get-caller-identity --profile poc-test

# 5. 手动测试挂载
sudo rclone mount s3-poc:bucket /mnt/s3-poc --vfs-cache-mode full --verbose

# 6. 重新加载 systemd
sudo systemctl daemon-reload
sudo systemctl restart rclone-s3-poc
```

### 问题 5: 网络中断后无法恢复

**症状**: 网络恢复后挂载点仍然无法访问

**解决方案**:
```bash
# 1. 检查服务状态
sudo systemctl status rclone-s3-poc

# 2. 重启服务
sudo systemctl restart rclone-s3-poc

# 3. 如果使用手动挂载，重新挂载
fusermount -u /mnt/s3-poc
rclone mount s3-poc:bucket /mnt/s3-poc --vfs-cache-mode full --daemon

# 4. 检查网络连接
ping s3.cn-northwest-1.amazonaws.com.cn
curl -I https://s3.cn-northwest-1.amazonaws.com.cn
```

### 问题 6: 文件保存失败

**症状**: 编辑文件后无法保存或保存后内容丢失

**解决方案**:
```bash
# 1. 确保使用完整缓存模式
# 修改 systemd 服务或挂载命令，使用：
--vfs-cache-mode full

# 2. 增加写回延迟
--vfs-write-back 5s

# 3. 检查缓存空间
df -h ~/.cache/rclone/

# 4. 清理缓存
rm -rf ~/.cache/rclone/*

# 5. 重新挂载
sudo systemctl restart rclone-s3-poc
```

### 问题 7: 高 CPU 使用率

**症状**: rclone 进程占用大量 CPU

**解决方案**:
```bash
# 1. 检查进程状态
top -p $(pgrep rclone)

# 2. 减少轮询频率
--poll-interval 30s

# 3. 减少并发传输
--transfers 4

# 4. 限制带宽（如果需要）
--bwlimit 10M

# 5. 检查是否有大量小文件操作
ls -la /mnt/s3-poc | wc -l
```

---

## 📞 技术支持

### 联系方式
- **邮箱**: wangrenjun@gmail.com
- **参考文档**: [AWS 存储服务选择指南](./AWS存储服务选择指南.md)

### 获取帮助
1. 查看 rclone 日志: `sudo journalctl -u rclone-s3-poc -f`
2. 查看系统日志: `sudo journalctl -xe`
3. 访问 rclone 官方论坛: https://forum.rclone.org/
4. 联系 AWS 技术支持
5. 查看 SUSE 支持文档

---

## 📋 快速检查清单

### POC 执行前检查
- [ ] SUSE Linux Enterprise Server 15 SP5
- [ ] root 或 sudo 权限
- [ ] 稳定的网络连接
- [ ] AWS 账号和 IAM 用户
- [ ] 至少 2GB 可用磁盘空间
- [ ] 已安装 AWS CLI
- [ ] 已安装 rclone
- [ ] FUSE 模块已加载
- [ ] 防火墙允许 S3 访问

### POC 执行中检查
- [ ] S3 存储桶创建成功
- [ ] rclone 配置正确
- [ ] 基本挂载测试通过
- [ ] 文件操作测试通过
- [ ] 性能测试完成
- [ ] 稳定性测试完成
- [ ] systemd 服务配置完成
- [ ] 开机自动挂载测试通过

### POC 执行后检查
- [ ] 完成所有测试项目
- [ ] 记录测试结果
- [ ] 填写 POC 报告
- [ ] 评估成本
- [ ] 清理测试资源
- [ ] 删除测试存储桶
- [ ] 文档化配置和流程

---

## 🔧 高级配置

### 1. 使用 VPC 端点（EC2 环境）

```bash
# 在 AWS Console 创建 S3 VPC 端点后，配置路由表
# rclone 会自动使用 VPC 端点，无需额外配置

# 验证是否使用 VPC 端点
aws s3 ls --debug 2>&1 | grep -i endpoint
```

### 2. 配置 S3 存储类

```bash
# 在 rclone 配置中指定存储类
rclone config

# 或在挂载时指定
rclone mount s3-poc:bucket /mnt/s3-poc \
  --s3-storage-class STANDARD_IA \
  --vfs-cache-mode full \
  --daemon
```

### 3. 启用服务器端加密

```bash
# 在 rclone 配置中启用 SSE-S3
rclone config

# 或在挂载时指定
rclone mount s3-poc:bucket /mnt/s3-poc \
  --s3-server-side-encryption AES256 \
  --vfs-cache-mode full \
  --daemon
```

### 4. 配置多个挂载点

```bash
# 创建多个 systemd 服务
sudo cp /etc/systemd/system/rclone-s3-poc.service \
     /etc/systemd/system/rclone-s3-prod.service

# 修改配置
sudo vi /etc/systemd/system/rclone-s3-prod.service
# 修改挂载点和存储桶名称

# 启动服务
sudo systemctl daemon-reload
sudo systemctl start rclone-s3-prod
sudo systemctl enable rclone-s3-prod
```

### 5. 配置只读挂载

```bash
# 添加 --read-only 参数
rclone mount s3-poc:bucket /mnt/s3-poc-ro \
  --read-only \
  --vfs-cache-mode full \
  --daemon
```

---

## 📊 性能优化建议

### 1. 缓存优化
```bash
# 增加缓存大小
--vfs-cache-max-size 5G

# 延长缓存时间
--vfs-cache-max-age 24h

# 增加目录缓存时间
--dir-cache-time 1h
```

### 2. 网络优化
```bash
# 增加并发传输数
--transfers 8

# 增加缓冲区大小
--buffer-size 64M

# 使用 VPC 端点（EC2 环境）
```

### 3. 系统优化
```bash
# 增加文件描述符限制
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# 优化网络参数
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
```

---

**文档版本**: 1.0  
**最后更新**: 2025-12-03  
**测试环境**: SUSE Linux Enterprise Server 15 SP5  
**AWS 区域**: 中国区（宁夏/北京）  
**目标用户**: Linux 系统管理员、DevOps 工程师

---

**祝测试顺利！** 🎉
