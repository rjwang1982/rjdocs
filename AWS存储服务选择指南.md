# AWS 存储服务选择指南

**作者**: RJ.Wang  
**邮箱**: wangrenjun@gmail.com  
**创建时间**: 2025-12-01  
**用途**: Windows 环境下 AWS 存储服务选择和按需计费方案

---

## 📊 服务对比总览

| 服务 | 协议 | Windows 支持 | 计费模式 | 文件锁 | 适用场景 |
|------|------|-------------|---------|--------|---------|
| **FSx for Windows** | SMB | ✅ 原生支持 | 按预配置容量 | ✅ 支持 | 多人编辑 Office 文档 |
| **EFS** | NFS | ❌ 不原生支持 | 按使用量 | ✅ 支持 | Linux 应用共享文件 |
| **S3** | HTTP/S3 API | ⚠️ 需工具 | 按使用量 | ❌ 不支持 | 静态文件、备份、归档 |

---

## 🔍 关键概念

### 计费模式区别

#### 按预配置容量计费（FSx）
```
创建配置: 1TB 存储 + 64 MB/s 吞吐量
实际使用: 只存了 10GB 文件
计费标准: 按 1TB + 64 MB/s 计费 ❌
```

#### 按使用量计费（S3/EFS）
```
创建配置: 无需预配置
实际使用: 存了 10GB 文件
计费标准: 只按 10GB 计费 ✅
```

### 文件锁（File Locking）

**定义**: 防止多个程序同时修改同一个文件导致数据损坏的机制

#### 没有文件锁的问题
```
时间轴：
10:00:00 - 用户A 打开 report.xlsx，看到金额 = 100
10:00:01 - 用户B 打开 report.xlsx，看到金额 = 100
10:00:05 - 用户A 改成 150，保存
10:00:06 - 用户B 改成 200，保存
结果：用户A 的修改丢失了！❌
```

#### 有文件锁的保护
```
时间轴：
10:00:00 - 用户A 打开 report.xlsx（文件被锁定）
10:00:01 - 用户B 尝试打开，提示"文件正在被使用"
10:00:05 - 用户A 保存并关闭（解锁）
10:00:06 - 用户B 现在可以打开了
结果：数据安全！✅
```

---

## 💡 Windows 环境按需计费方案

### 方案 1: S3 + 应用层集成（推荐 - 最经济）

**适用场景**: 可以修改应用代码

```python
# 应用直接使用 S3 SDK
import boto3
s3 = boto3.client('s3')

# 读写文件
s3.upload_file('local.txt', 'bucket', 'key')
s3.download_file('bucket', 'key', 'local.txt')
```

**优点**:
- ✅ 完全按使用量计费
- ✅ 无限扩展
- ✅ 最便宜

**缺点**:
- ❌ 不是文件系统，需要修改应用代码
- ❌ 不支持文件锁

---

### 方案 2: S3 + 挂载工具

**适用场景**: 不能修改应用代码，需要像磁盘一样使用

#### 工具选项
- **rclone mount**（开源免费，推荐）
- **CloudBerry Drive**（商业软件）
- **S3 Browser**（只能浏览，不能挂载）

#### rclone 使用示例
```bash
# Windows 上安装 rclone 后
rclone mount s3:bucket-name Z: --vfs-cache-mode full
```

**优点**:
- ✅ 按使用量计费
- ✅ 像普通磁盘一样使用
- ✅ 支持 Windows 盘符

**缺点**:
- ⚠️ 性能比原生文件系统差
- ⚠️ 不支持文件锁
- ⚠️ 网络延迟较高

---

### 方案 3: FSx for Windows 最小配置

**适用场景**: 必须使用原生 Windows 文件系统，需要文件锁

#### 最小配置
```
存储容量: 32 GB（最小值）
吞吐量: 8 MB/s（最小值）
```

#### 中国区宁夏价格参考
```
单价: 约 ¥0.8/GB/月
最小配置成本: 32GB × ¥0.8 ≈ ¥25/月
```

**优点**:
- ✅ 原生 Windows SMB 支持
- ✅ 高性能
- ✅ 支持文件锁
- ✅ 支持 Windows ACL

**缺点**:
- ❌ 按预配置容量计费
- ❌ 最低配置也有固定成本

---

### 方案 4: EFS + Linux 网关（混合环境）

**适用场景**: Linux + Windows 混合环境

#### 架构
```
Windows 客户端
    ↓ (SMB)
Linux EC2 (Samba 服务器)
    ↓ (NFS)
EFS (按使用量计费)
```

#### 配置步骤
```bash
# 1. Linux 上挂载 EFS
sudo mount -t nfs4 -o nfsvers=4.1 \
  fs-xxxxx.efs.region.amazonaws.com:/ /mnt/efs

# 2. 安装 Samba
sudo yum install samba -y

# 3. 配置 Samba 共享
# 编辑 /etc/samba/smb.conf

# 4. Windows 通过 SMB 协议访问
\\linux-gateway-ip\share
```

**优点**:
- ✅ EFS 按使用量计费
- ✅ 支持文件锁
- ✅ 适合混合环境

**缺点**:
- ⚠️ 需要维护 Linux 网关 EC2
- ⚠️ 架构复杂度增加
- ⚠️ 网关成为单点故障

---

## 🎯 决策树

### 第一步: 是否需要文件锁？

#### 需要文件锁的场景
- ✅ Office 文档（Word、Excel、PPT）多人编辑
- ✅ 数据库文件（SQLite、Access）
- ✅ 配置文件多个进程读写
- ✅ 日志文件多个程序写入

#### 不需要文件锁的场景
- ❌ 静态网站文件（HTML、CSS、图片）
- ❌ 备份文件（只读不写）
- ❌ 日志归档（写入后不再修改）
- ❌ 媒体文件（上传后不修改）

### 决策流程图

```
需要文件锁？
├─ 是 → FSx for Windows（最小配置 ¥25/月）
│
└─ 否 → 能修改应用代码？
    ├─ 是 → S3 SDK（最便宜，按使用量）
    │
    └─ 否 → 需要高性能？
        ├─ 是 → FSx for Windows（最小配置）
        └─ 否 → S3 + rclone mount（按使用量）
```

---

## 📋 快速选择表

| 使用场景 | 推荐方案 | 月成本估算 |
|---------|---------|-----------|
| 共享 Office 文档编辑 | FSx for Windows | ¥25+ |
| 静态文件存储/备份 | S3 | 按使用量 |
| 应用日志/归档 | S3 | 按使用量 |
| 图片/视频存储 | S3 | 按使用量 |
| 单用户文件访问 | S3 + rclone | 按使用量 |
| 数据库文件共享 | FSx for Windows | ¥25+ |
| Linux + Windows 混合 | EFS + Linux 网关 | EC2 + 按使用量 |

---

## 🔧 EFS 在 Windows 上的使用

### Windows 原生 NFS 客户端（不推荐）

#### 启用 NFS 客户端
```powershell
# Windows Server / Windows 10/11 专业版
Enable-WindowsOptionalFeature -FeatureName ServicesForNFS-ClientOnly -Online -All
```

#### 挂载 EFS
```powershell
mount -o anon \\fs-xxxxx.efs.region.amazonaws.com\share Z:
```

**问题**:
- ❌ 性能较差
- ❌ 权限管理复杂
- ❌ 不支持 Windows ACL
- ❌ 稳定性一般

**结论**: 不推荐在生产环境使用

---

## 💰 成本对比示例

### 场景: 存储 100GB 文件

| 服务 | 配置 | 月成本（中国区宁夏） |
|------|------|-------------------|
| **S3 标准存储** | 100GB 实际使用 | ¥14.4 |
| **EFS** | 100GB 实际使用 | ¥20 |
| **FSx for Windows** | 最小 32GB 配置 | ¥25 |
| **FSx for Windows** | 100GB 配置 | ¥80 |

### 场景: 存储 10GB 文件

| 服务 | 配置 | 月成本（中国区宁夏） |
|------|------|-------------------|
| **S3 标准存储** | 10GB 实际使用 | ¥1.44 |
| **EFS** | 10GB 实际使用 | ¥2 |
| **FSx for Windows** | 最小 32GB 配置 | ¥25（固定） |

**结论**: 小容量场景下，S3 成本优势明显

---

## 🚀 实施建议

### 1. 评估需求
```
问题清单：
□ 是否需要多人同时编辑文件？
□ 是否需要文件锁？
□ 是否可以修改应用代码？
□ 预计存储容量是多少？
□ 对性能要求如何？
□ 预算限制是多少？
```

### 2. 选择方案
- **预算优先** → S3 + rclone mount
- **性能优先** → FSx for Windows
- **灵活性优先** → S3 SDK

### 3. 测试验证
```bash
# 测试 S3 访问
aws --profile c5611 s3 ls

# 测试 rclone 挂载
rclone mount s3:bucket Z: --vfs-cache-mode full

# 测试文件读写性能
# 使用实际应用场景测试
```

### 4. 监控成本
```bash
# 查看 S3 存储用量
aws --profile c5611 s3 ls --summarize --recursive s3://bucket-name

# 查看 FSx 配置
aws --profile c5611 fsx describe-file-systems
```

---

## ⚠️ 常见问题

### Q1: S3 挂载工具稳定吗？
**A**: rclone 相对稳定，但不如原生文件系统。建议：
- 启用本地缓存（`--vfs-cache-mode full`）
- 不要用于高并发写入场景
- 定期检查挂载状态

### Q2: FSx 最小配置够用吗？
**A**: 取决于使用场景：
- **够用**: 少量用户，小文件，低频访问
- **不够**: 大量用户，大文件，高频访问
- **建议**: 从最小配置开始，根据监控数据调整

### Q3: 能否从 FSx 迁移到 S3？
**A**: 可以，但需要：
- 修改应用代码使用 S3 SDK
- 或使用 rclone 同步数据
- 评估文件锁需求

### Q4: EFS 在 Windows 上真的不能用吗？
**A**: 技术上可以，但：
- 性能和稳定性差
- 不支持 Windows ACL
- 不推荐生产环境使用
- 如果必须用，建议通过 Linux 网关

---

## 📚 相关资源

### AWS 官方文档
- [FSx for Windows 定价](https://aws.amazon.com/fsx/windows/pricing/)
- [EFS 定价](https://aws.amazon.com/efs/pricing/)
- [S3 定价](https://aws.amazon.com/s3/pricing/)

### 工具下载
- [rclone 官网](https://rclone.org/)
- [AWS CLI 安装](https://aws.amazon.com/cli/)

### 成本计算器
- [AWS 定价计算器](https://calculator.aws)

---

## 📝 总结

### 核心原则
1. **按需计费优先** - 除非必须，否则选择 S3/EFS
2. **简单即稳定** - 优先选择架构简单的方案
3. **成本可控** - 从最小配置开始，逐步扩展

### 最佳实践
- ✅ 小文件、静态内容 → S3
- ✅ 需要文件锁 → FSx for Windows
- ✅ Linux 环境 → EFS
- ✅ 预算有限 → S3 + rclone

### 避免的坑
- ❌ 不要在 Windows 上直接用 EFS NFS 客户端
- ❌ 不要为了按需计费牺牲必要的文件锁功能
- ❌ 不要一开始就配置过大的 FSx 容量

---

**最后更新**: 2025-12-01  
**适用区域**: AWS 中国区（宁夏/北京）和 Global 区域
