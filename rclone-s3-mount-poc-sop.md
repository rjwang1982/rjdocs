# S3 + rclone 挂载方案 POC SOP

**作者**: RJ.Wang  
**邮箱**: wangrenjun@gmail.com  
**创建时间**: 2025-12-03  
**用途**: macOS 环境下 S3 + rclone 挂载方案验证标准操作流程

---

## 📋 POC 目标

验证 S3 + rclone 挂载方案的可行性，评估：
- ✅ 基本功能（读写、删除、重命名）
- ✅ 性能表现（延迟、吞吐量）
- ✅ 稳定性（长时间运行、异常恢复）
- ✅ 成本估算（存储、请求、数据传输）

---

## 🎯 测试环境

### 系统要求
- **操作系统**: macOS（本 SOP 基于 macOS）
- **网络**: 稳定的互联网连接
- **权限**: AWS IAM 用户具有 S3 完全访问权限

### AWS 资源
- **区域**: cn-northwest-1（宁夏）或 cn-north-1（北京）
- **S3 存储桶**: 测试专用，POC 结束后可删除
- **IAM 用户**: 具有 S3FullAccess 权限

---

## 📦 准备工作

### 1. 安装 rclone

#### 使用 Homebrew（推荐）
```bash
# 安装 rclone
brew install rclone

# 验证安装
rclone version
```

#### 手动安装
```bash
# 下载最新版本
curl -O https://downloads.rclone.org/rclone-current-osx-amd64.zip

# 解压
unzip rclone-current-osx-amd64.zip

# 移动到系统路径
sudo mv rclone-*/rclone /usr/local/bin/

# 验证
rclone version
```

### 2. 安装 macFUSE（必需）

rclone mount 需要 macFUSE 支持。

```bash
# 使用 Homebrew 安装
brew install --cask macfuse

# 安装后需要重启 Mac
# 或在"系统偏好设置 > 安全性与隐私"中允许 macFUSE
```

**重要提示**:
- macOS 10.15+ 需要在系统设置中允许内核扩展
- 路径: 系统偏好设置 → 安全性与隐私 → 通用 → 允许

---

## 🔧 配置步骤

### 步骤 1: 创建测试 S3 存储桶

```bash
# 设置 AWS Profile（使用中国区账号）
export AWS_PROFILE=c5611

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

#### 方式 A: 交互式配置（推荐新手）

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

#### 方式 B: 直接编辑配置文件（推荐熟手）

```bash
# 编辑 rclone 配置文件
cat >> ~/.config/rclone/rclone.conf << 'EOF'
[s3-poc]
type = s3
provider = AWS
env_auth = true
region = cn-northwest-1
endpoint = s3.cn-northwest-1.amazonaws.com.cn
acl = private
EOF

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
echo "Hello rclone POC" > /tmp/test.txt
rclone copy /tmp/test.txt s3-poc:${BUCKET_NAME}/

# 验证上传
rclone ls s3-poc:${BUCKET_NAME}
```

---

## 🚀 挂载测试

### 测试 1: 基本挂载

#### 创建挂载点
```bash
# 创建本地挂载目录
mkdir -p ~/rclone-mount-poc

# 基本挂载（前台运行，用于测试）
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)
rclone mount s3-poc:${BUCKET_NAME} ~/rclone-mount-poc \
  --vfs-cache-mode writes \
  --verbose

# 在另一个终端窗口测试
ls -la ~/rclone-mount-poc
```

**测试项目**:
- [ ] 能否看到之前上传的 test.txt
- [ ] 能否读取文件内容: `cat ~/rclone-mount-poc/test.txt`
- [ ] 能否创建新文件: `echo "test" > ~/rclone-mount-poc/new.txt`
- [ ] 能否删除文件: `rm ~/rclone-mount-poc/new.txt`

**停止挂载**: 在运行 rclone mount 的终端按 `Ctrl+C`

### 测试 2: 优化挂载（推荐配置）

```bash
# 卸载之前的挂载
umount ~/rclone-mount-poc 2>/dev/null || true

# 使用优化参数挂载
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)
rclone mount s3-poc:${BUCKET_NAME} ~/rclone-mount-poc \
  --vfs-cache-mode full \
  --vfs-cache-max-size 1G \
  --vfs-cache-max-age 1h \
  --buffer-size 32M \
  --dir-cache-time 5m \
  --poll-interval 15s \
  --verbose \
  --log-file ~/rclone-mount-poc.log &

# 记录进程 ID
echo $! > /tmp/rclone-mount-poc.pid
```

**参数说明**:
- `--vfs-cache-mode full`: 完整缓存模式，性能最好
- `--vfs-cache-max-size 1G`: 最大缓存 1GB
- `--vfs-cache-max-age 1h`: 缓存保留 1 小时
- `--buffer-size 32M`: 读写缓冲区 32MB
- `--dir-cache-time 5m`: 目录列表缓存 5 分钟
- `--poll-interval 15s`: 每 15 秒检查变化
- `--log-file`: 日志文件路径
- `&`: 后台运行

### 测试 3: 后台运行挂载

```bash
# 创建启动脚本
cat > ~/start-rclone-mount.sh << 'EOF'
#!/bin/bash

BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)
MOUNT_POINT=~/rclone-mount-poc
LOG_FILE=~/rclone-mount-poc.log
PID_FILE=/tmp/rclone-mount-poc.pid

# 检查是否已挂载
if mount | grep -q "$MOUNT_POINT"; then
    echo "已经挂载在 $MOUNT_POINT"
    exit 0
fi

# 确保挂载点存在
mkdir -p "$MOUNT_POINT"

# 启动挂载
rclone mount s3-poc:${BUCKET_NAME} "$MOUNT_POINT" \
  --vfs-cache-mode full \
  --vfs-cache-max-size 1G \
  --vfs-cache-max-age 1h \
  --buffer-size 32M \
  --dir-cache-time 5m \
  --poll-interval 15s \
  --log-file "$LOG_FILE" \
  --daemon

echo "rclone 挂载已启动"
echo "挂载点: $MOUNT_POINT"
echo "日志文件: $LOG_FILE"
EOF

# 添加执行权限
chmod +x ~/start-rclone-mount.sh

# 执行挂载
~/start-rclone-mount.sh
```

**验证挂载**:
```bash
# 检查挂载状态
mount | grep rclone

# 查看挂载点
ls -la ~/rclone-mount-poc

# 查看日志
tail -f ~/rclone-mount-poc.log
```

---

## 🧪 功能测试

### 测试 4: 文件操作测试

```bash
# 进入挂载目录
cd ~/rclone-mount-poc

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

# 5. 删除文件
rm renamed.txt
ls -la

# 6. 删除目录
rm -rf test-dir
ls -la
```

**记录结果**:
- [ ] 创建文件: ✅ / ❌
- [ ] 读取文件: ✅ / ❌
- [ ] 创建目录: ✅ / ❌
- [ ] 复制文件: ✅ / ❌
- [ ] 重命名文件: ✅ / ❌
- [ ] 删除文件: ✅ / ❌
- [ ] 删除目录: ✅ / ❌

### 测试 5: 性能测试

#### 写入性能测试
```bash
cd ~/rclone-mount-poc

# 测试小文件写入（1MB x 10）
echo "=== 小文件写入测试 ==="
time for i in {1..10}; do
  dd if=/dev/zero of=small-$i.dat bs=1m count=1 2>/dev/null
done

# 测试大文件写入（100MB x 1）
echo "=== 大文件写入测试 ==="
time dd if=/dev/zero of=large.dat bs=1m count=100

# 清理测试文件
rm -f small-*.dat large.dat
```

#### 读取性能测试
```bash
cd ~/rclone-mount-poc

# 创建测试文件
dd if=/dev/zero of=read-test.dat bs=1m count=50

# 清除系统缓存（需要 root 权限）
sudo purge

# 测试读取性能
echo "=== 读取性能测试 ==="
time dd if=read-test.dat of=/dev/null bs=1m

# 再次读取（测试缓存效果）
echo "=== 缓存读取测试 ==="
time dd if=read-test.dat of=/dev/null bs=1m

# 清理
rm read-test.dat
```

**记录性能数据**:
```
小文件写入（1MB x 10）: _____ 秒
大文件写入（100MB）: _____ 秒
首次读取（50MB）: _____ 秒
缓存读取（50MB）: _____ 秒
```

### 测试 6: 并发操作测试

```bash
cd ~/rclone-mount-poc

# 创建测试脚本
cat > concurrent-test.sh << 'EOF'
#!/bin/bash
for i in {1..5}; do
  echo "Process $1 - File $i" > process-$1-file-$i.txt
  sleep 1
done
EOF

chmod +x concurrent-test.sh

# 并发执行
echo "=== 并发写入测试 ==="
time (
  ./concurrent-test.sh 1 &
  ./concurrent-test.sh 2 &
  ./concurrent-test.sh 3 &
  wait
)

# 验证结果
ls -la process-*.txt
wc -l process-*.txt

# 清理
rm -f concurrent-test.sh process-*.txt
```

---

## 📊 稳定性测试

### 测试 7: 长时间运行测试

```bash
# 创建长时间测试脚本
cat > ~/long-run-test.sh << 'EOF'
#!/bin/bash

MOUNT_POINT=~/rclone-mount-poc
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

### 测试 8: 异常恢复测试

```bash
# 1. 正常创建文件
cd ~/rclone-mount-poc
echo "Before disconnect" > recovery-test.txt

# 2. 模拟网络中断（关闭 WiFi 或拔网线）
# 等待 30 秒

# 3. 尝试操作（应该失败或挂起）
echo "During disconnect" > recovery-test2.txt

# 4. 恢复网络连接

# 5. 等待 rclone 自动重连（观察日志）
tail -f ~/rclone-mount-poc.log

# 6. 验证恢复后的操作
echo "After reconnect" > recovery-test3.txt
ls -la

# 7. 验证数据完整性
cat recovery-test.txt
cat recovery-test3.txt
```

**记录结果**:
- [ ] 网络中断时操作行为: _____
- [ ] 自动重连时间: _____ 秒
- [ ] 重连后数据完整性: ✅ / ❌

---

## 💰 成本评估

### 测试 9: 成本计算

```bash
# 获取存储桶统计信息
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)

# 查看存储用量
aws s3 ls s3://${BUCKET_NAME} --recursive --human-readable --summarize

# 查看请求次数（需要启用 S3 请求指标）
# 在 AWS Console 中查看 CloudWatch 指标

# 估算月成本
cat > cost-estimate.sh << 'EOF'
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

chmod +x cost-estimate.sh

# 运行成本估算
./cost-estimate.sh 10 1000 5
```

---

## 🔍 监控和日志

### 查看 rclone 日志
```bash
# 实时查看日志
tail -f ~/rclone-mount-poc.log

# 查看错误日志
grep -i error ~/rclone-mount-poc.log

# 查看统计信息
rclone rc core/stats
```

### 监控挂载状态
```bash
# 创建监控脚本
cat > ~/monitor-rclone.sh << 'EOF'
#!/bin/bash

MOUNT_POINT=~/rclone-mount-poc

while true; do
  if mount | grep -q "$MOUNT_POINT"; then
    echo "[$(date)] ✅ rclone 挂载正常"
  else
    echo "[$(date)] ❌ rclone 挂载断开，尝试重新挂载..."
    ~/start-rclone-mount.sh
  fi
  sleep 60
done
EOF

chmod +x ~/monitor-rclone.sh

# 后台运行监控
nohup ~/monitor-rclone.sh > ~/monitor-rclone.log 2>&1 &
```

---

## 🧹 清理工作

### 卸载挂载
```bash
# 方式 1: 使用 umount
umount ~/rclone-mount-poc

# 方式 2: 使用 fusermount（如果 umount 失败）
fusermount -u ~/rclone-mount-poc

# 方式 3: 强制卸载
sudo umount -f ~/rclone-mount-poc
```

### 停止后台进程
```bash
# 停止 rclone mount
pkill -f "rclone mount"

# 停止监控脚本
pkill -f "monitor-rclone.sh"

# 停止长时间测试
pkill -f "long-run-test.sh"
```

### 删除测试资源
```bash
# 删除 S3 存储桶内容
BUCKET_NAME=$(cat /tmp/rclone-poc-bucket.txt)
aws s3 rm s3://${BUCKET_NAME} --recursive

# 删除存储桶
aws s3 rb s3://${BUCKET_NAME}

# 删除本地文件
rm -rf ~/rclone-mount-poc
rm -f ~/rclone-mount-poc.log
rm -f ~/long-run-test.log
rm -f ~/monitor-rclone.log
rm -f /tmp/rclone-poc-bucket.txt
rm -f /tmp/rclone-mount-poc.pid

# 删除脚本
rm -f ~/start-rclone-mount.sh
rm -f ~/long-run-test.sh
rm -f ~/monitor-rclone.sh
rm -f ~/cost-estimate.sh

# 删除 rclone 配置（可选）
rclone config delete s3-poc
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

#### 2. 性能测试
| 测试项 | 结果 | 备注 |
|--------|------|------|
| 小文件写入（1MB x 10） | ___ 秒 | |
| 大文件写入（100MB） | ___ 秒 | |
| 首次读取（50MB） | ___ 秒 | |
| 缓存读取（50MB） | ___ 秒 | |
| 并发操作 | ✅ / ❌ | |

#### 3. 稳定性测试
| 测试项 | 结果 | 备注 |
|--------|------|------|
| 长时间运行（1小时） | ✅ / ❌ | |
| 网络中断恢复 | ✅ / ❌ | |
| 自动重连时间 | ___ 秒 | |

#### 4. 成本估算
```
存储容量: ___ GB
月成本: ¥___ 元
```

#### 5. 优缺点总结

**优点**:
- 
- 
- 

**缺点**:
- 
- 
- 

#### 6. 建议

**适用场景**:
- 

**不适用场景**:
- 

**优化建议**:
- 

---

## 🔗 参考资源

### 官方文档
- [rclone 官方文档](https://rclone.org/docs/)
- [rclone mount 文档](https://rclone.org/commands/rclone_mount/)
- [AWS S3 定价](https://aws.amazon.com/cn/s3/pricing/)

### 相关文档
- [AWS 存储服务选择指南](./AWS存储服务选择指南.md)

### 常见问题
- [rclone FAQ](https://rclone.org/faq/)
- [macFUSE 文档](https://osxfuse.github.io/)

---

## ⚠️ 注意事项

1. **macFUSE 权限**: 首次安装需要在系统设置中允许内核扩展
2. **网络依赖**: rclone mount 完全依赖网络，断网会导致挂载不可用
3. **缓存管理**: 注意 `--vfs-cache-max-size` 设置，避免占用过多磁盘空间
4. **文件锁**: rclone 不支持文件锁，不适合多人编辑 Office 文档
5. **性能**: 首次访问文件会有网络延迟，缓存后性能提升明显
6. **成本**: 频繁的小文件操作会产生大量 API 请求，注意成本控制

---

## 📞 支持

如有问题，请联系:
- **邮箱**: wangrenjun@gmail.com
- **参考文档**: [AWS 存储服务选择指南](./AWS存储服务选择指南.md)

---

**最后更新**: 2025-12-03  
**测试环境**: macOS  
**AWS 区域**: 中国区（宁夏/北京）
