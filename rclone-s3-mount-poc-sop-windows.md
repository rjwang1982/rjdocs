# S3 + rclone 挂载方案 POC SOP（Windows 版）

**作者**: RJ.Wang  
**邮箱**: wangrenjun@gmail.com  
**创建时间**: 2025-12-03  
**用途**: Windows 环境下 S3 + rclone 挂载方案验证标准操作流程

---

## 📋 POC 目标

验证 S3 + rclone 挂载方案在 Windows 环境下的可行性，评估：
- ✅ 基本功能（读写、删除、重命名）
- ✅ 性能表现（延迟、吞吐量）
- ✅ 稳定性（长时间运行、异常恢复）
- ✅ 成本估算（存储、请求、数据传输）
- ✅ Windows 盘符挂载体验

---

## 🎯 测试环境

### 系统要求
- **操作系统**: Windows 10/11 或 Windows Server 2016+
- **网络**: 稳定的互联网连接
- **权限**: AWS IAM 用户具有 S3 完全访问权限
- **管理员权限**: 安装软件需要管理员权限

### AWS 资源
- **区域**: cn-northwest-1（宁夏）或 cn-north-1（北京）
- **S3 存储桶**: 测试专用，POC 结束后可删除
- **IAM 用户**: 具有 S3FullAccess 权限

---

## 📦 准备工作

### 1. 安装 AWS CLI

#### 下载并安装
1. 访问 AWS CLI 下载页面: https://aws.amazon.com/cli/
2. 下载 Windows 64位安装程序
3. 双击安装程序，按照向导完成安装
4. 打开新的 PowerShell 窗口验证：

```powershell
aws --version
```

#### 配置 AWS 凭证

```powershell
# 配置 AWS 凭证
aws configure --profile poc-test

# 按提示输入：
# AWS Access Key ID: [您的 Access Key]
# AWS Secret Access Key: [您的 Secret Key]
# Default region name: cn-northwest-1
# Default output format: json
```

### 2. 安装 rclone

#### 方式 A: 手动安装（推荐）

1. 访问 rclone 官网下载页面: https://rclone.org/downloads/
2. 下载 **Windows Intel/AMD 64 Bit** 版本
3. 解压下载的 zip 文件到 `C:\Program Files\rclone`
4. 将 rclone 添加到系统 PATH：
   - 右键"此电脑" → 属性 → 高级系统设置
   - 环境变量 → 系统变量 → Path → 编辑
   - 新建 → 输入 `C:\Program Files\rclone`
   - 确定保存
5. **打开新的 PowerShell 窗口**验证安装：

```powershell
rclone version
```

#### 方式 B: 使用 PowerShell 脚本安装

```powershell
# 以管理员身份运行 PowerShell

# 下载 rclone
$url = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"
$output = "$env:TEMP\rclone.zip"
Invoke-WebRequest -Uri $url -OutFile $output

# 解压到 Program Files
Expand-Archive -Path $output -DestinationPath "C:\Program Files\" -Force

# 重命名目录（找到解压后的目录）
$rcloneDir = Get-ChildItem "C:\Program Files\" | Where-Object {$_.Name -like "rclone-*-windows-amd64"} | Select-Object -First 1
Rename-Item $rcloneDir.FullName "C:\Program Files\rclone"

# 添加到 PATH
$oldPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($oldPath -notlike "*rclone*") {
    $newPath = $oldPath + ";C:\Program Files\rclone"
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
}

Write-Host "rclone 安装完成，请打开新的 PowerShell 窗口验证"
```

### 3. 安装 WinFsp（必需）

rclone mount 在 Windows 上需要 WinFsp 支持。

#### 下载并安装 WinFsp

1. 访问 WinFsp 官网: https://winfsp.dev/
2. 下载最新版本的安装程序（winfsp-xxx.msi）
3. 双击安装程序，按照向导完成安装
4. 安装完成后**重启计算机**

#### 使用 PowerShell 自动安装

```powershell
# 以管理员身份运行 PowerShell

# 下载 WinFsp
$url = "https://github.com/winfsp/winfsp/releases/download/v2.0/winfsp-2.0.23075.msi"
$output = "$env:TEMP\winfsp.msi"
Invoke-WebRequest -Uri $url -OutFile $output

# 静默安装
Start-Process msiexec.exe -ArgumentList "/i $output /qn" -Wait

Write-Host "WinFsp 安装完成，请重启计算机"
```

**重要提示**:
- 安装 WinFsp 后必须重启计算机
- 如果挂载失败，检查 WinFsp 服务是否运行：
  - 按 `Win + R`，输入 `services.msc`
  - 查找 `WinFsp.Launcher` 服务，确保状态为"正在运行"

---

## 🔧 配置步骤

### 步骤 1: 创建测试 S3 存储桶

```powershell
# 打开 PowerShell

# 设置 AWS Profile
$env:AWS_PROFILE = "poc-test"

# 验证当前账号
aws sts get-caller-identity

# 创建测试存储桶（存储桶名称必须全局唯一）
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bucketName = "rclone-poc-test-$timestamp"
aws s3 mb s3://$bucketName --region cn-northwest-1

# 记录存储桶名称
Write-Host "测试存储桶: $bucketName"
$bucketName | Out-File -FilePath "$env:TEMP\rclone-poc-bucket.txt"
```

### 步骤 2: 配置 rclone

#### 方式 A: 交互式配置（推荐）

```powershell
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

```powershell
# 创建 rclone 配置目录
$rcloneConfigDir = "$env:APPDATA\rclone"
if (!(Test-Path $rcloneConfigDir)) {
    New-Item -ItemType Directory -Path $rcloneConfigDir
}

# 创建配置文件
$configContent = @"
[s3-poc]
type = s3
provider = AWS
env_auth = true
region = cn-northwest-1
endpoint = s3.cn-northwest-1.amazonaws.com.cn
acl = private
"@

$configContent | Out-File -FilePath "$rcloneConfigDir\rclone.conf" -Encoding UTF8

# 验证配置
rclone config show s3-poc
```

### 步骤 3: 验证 S3 连接

```powershell
# 读取存储桶名称
$bucketName = Get-Content "$env:TEMP\rclone-poc-bucket.txt"

# 测试列出存储桶内容
rclone ls s3-poc:$bucketName

# 上传测试文件
"Hello rclone POC - $(Get-Date)" | Out-File -FilePath "$env:TEMP\test.txt"
rclone copy "$env:TEMP\test.txt" s3-poc:$bucketName/

# 验证上传
rclone ls s3-poc:$bucketName
```

---

## 🚀 挂载测试

### 测试 1: 基本挂载

#### 创建挂载点并挂载

```powershell
# 读取存储桶名称
$bucketName = Get-Content "$env:TEMP\rclone-poc-bucket.txt"

# 基本挂载到 Z: 盘（前台运行，用于测试）
rclone mount s3-poc:$bucketName Z: --vfs-cache-mode writes --verbose

# 在另一个 PowerShell 窗口测试
Get-ChildItem Z:\
```

**测试项目**:
- [ ] 能否看到 Z: 盘
- [ ] 能否看到之前上传的 test.txt
- [ ] 能否读取文件内容: `Get-Content Z:\test.txt`
- [ ] 能否创建新文件: `"test" | Out-File Z:\new.txt`
- [ ] 能否删除文件: `Remove-Item Z:\new.txt`

**停止挂载**: 在运行 rclone mount 的 PowerShell 窗口按 `Ctrl+C`

### 测试 2: 优化挂载（推荐配置）

```powershell
# 读取存储桶名称
$bucketName = Get-Content "$env:TEMP\rclone-poc-bucket.txt"

# 使用优化参数挂载（后台运行）
Start-Process powershell -ArgumentList "-NoExit", "-Command", @"
rclone mount s3-poc:$bucketName Z: ``
  --vfs-cache-mode full ``
  --vfs-cache-max-size 1G ``
  --vfs-cache-max-age 1h ``
  --buffer-size 32M ``
  --dir-cache-time 5m ``
  --poll-interval 15s ``
  --log-file `$env:USERPROFILE\rclone-mount-poc.log ``
  --log-level INFO
"@

# 等待几秒让挂载完成
Start-Sleep -Seconds 5

# 验证挂载
Get-PSDrive Z
```

**参数说明**:
- `--vfs-cache-mode full`: 完整缓存模式，性能最好
- `--vfs-cache-max-size 1G`: 最大缓存 1GB
- `--vfs-cache-max-age 1h`: 缓存保留 1 小时
- `--buffer-size 32M`: 读写缓冲区 32MB
- `--dir-cache-time 5m`: 目录列表缓存 5 分钟
- `--poll-interval 15s`: 每 15 秒检查变化
- `--log-file`: 日志文件路径
- `--log-level INFO`: 日志级别

### 测试 3: 创建自动挂载脚本

```powershell
# 创建挂载脚本
$mountScript = @'
# S3 rclone 挂载脚本
$bucketName = Get-Content "$env:TEMP\rclone-poc-bucket.txt"
$driveLetter = "Z:"
$logFile = "$env:USERPROFILE\rclone-mount-poc.log"

# 检查是否已挂载
if (Test-Path $driveLetter) {
    Write-Host "驱动器 $driveLetter 已经挂载"
    exit 0
}

# 启动挂载
Write-Host "正在挂载 S3 存储桶到 $driveLetter ..."
rclone mount s3-poc:$bucketName $driveLetter `
  --vfs-cache-mode full `
  --vfs-cache-max-size 1G `
  --vfs-cache-max-age 1h `
  --buffer-size 32M `
  --dir-cache-time 5m `
  --poll-interval 15s `
  --log-file $logFile `
  --log-level INFO

Write-Host "rclone 挂载已启动"
Write-Host "挂载点: $driveLetter"
Write-Host "日志文件: $logFile"
'@

# 保存脚本
$mountScript | Out-File -FilePath "$env:USERPROFILE\Desktop\mount-s3.ps1" -Encoding UTF8

Write-Host "挂载脚本已创建: $env:USERPROFILE\Desktop\mount-s3.ps1"
Write-Host "双击脚本即可挂载 S3 存储桶"
```

**使用方法**:
1. 双击桌面上的 `mount-s3.ps1` 脚本
2. 如果提示执行策略错误，以管理员身份运行 PowerShell 执行：
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

---

## 🧪 功能测试

### 测试 4: 文件操作测试

```powershell
# 进入挂载的 Z: 盘
Set-Location Z:\

# 1. 创建测试文件
"POC Test $(Get-Date)" | Out-File test-write.txt
Get-Content test-write.txt

# 2. 创建目录
New-Item -ItemType Directory -Name test-dir
Get-ChildItem

# 3. 复制文件
Copy-Item test-write.txt test-dir\
Get-ChildItem test-dir\

# 4. 重命名文件
Rename-Item test-write.txt renamed.txt
Get-ChildItem

# 5. 删除文件
Remove-Item renamed.txt
Get-ChildItem

# 6. 删除目录
Remove-Item test-dir -Recurse
Get-ChildItem
```

**记录结果**:
- [ ] 创建文件: ✅ / ❌
- [ ] 读取文件: ✅ / ❌
- [ ] 创建目录: ✅ / ❌
- [ ] 复制文件: ✅ / ❌
- [ ] 重命名文件: ✅ / ❌
- [ ] 删除文件: ✅ / ❌
- [ ] 删除目录: ✅ / ❌

### 测试 5: Office 文件测试（重要）

```powershell
# 测试 Excel 文件
# 1. 在 Z: 盘创建一个 Excel 文件
# 2. 用 Excel 打开并编辑
# 3. 保存文件
# 4. 关闭 Excel
# 5. 重新打开验证内容

# 测试 Word 文件
# 1. 在 Z: 盘创建一个 Word 文档
# 2. 用 Word 打开并编辑
# 3. 保存文件
# 4. 关闭 Word
# 5. 重新打开验证内容
```

**记录结果**:
- [ ] Excel 文件读写: ✅ / ❌
- [ ] Word 文件读写: ✅ / ❌
- [ ] 文件锁定提示: ✅ 有 / ❌ 无（注意：rclone 不支持文件锁）

### 测试 6: 性能测试

#### 写入性能测试

```powershell
Set-Location Z:\

# 测试小文件写入（1MB x 10）
Write-Host "=== 小文件写入测试 ==="
Measure-Command {
    1..10 | ForEach-Object {
        $bytes = New-Object byte[] 1MB
        [System.IO.File]::WriteAllBytes("Z:\small-$_.dat", $bytes)
    }
}

# 测试大文件写入（100MB x 1）
Write-Host "=== 大文件写入测试 ==="
Measure-Command {
    $bytes = New-Object byte[] 100MB
    [System.IO.File]::WriteAllBytes("Z:\large.dat", $bytes)
}

# 清理测试文件
Remove-Item Z:\small-*.dat
Remove-Item Z:\large.dat
```

#### 读取性能测试

```powershell
Set-Location Z:\

# 创建测试文件（50MB）
$bytes = New-Object byte[] 50MB
[System.IO.File]::WriteAllBytes("Z:\read-test.dat", $bytes)

# 测试读取性能
Write-Host "=== 首次读取测试 ==="
Measure-Command {
    $content = [System.IO.File]::ReadAllBytes("Z:\read-test.dat")
}

# 再次读取（测试缓存效果）
Write-Host "=== 缓存读取测试 ==="
Measure-Command {
    $content = [System.IO.File]::ReadAllBytes("Z:\read-test.dat")
}

# 清理
Remove-Item Z:\read-test.dat
```

**记录性能数据**:
```
小文件写入（1MB x 10）: _____ 秒
大文件写入（100MB）: _____ 秒
首次读取（50MB）: _____ 秒
缓存读取（50MB）: _____ 秒
```

### 测试 7: Windows 资源管理器测试

1. 打开"此电脑"，查看是否显示 Z: 盘
2. 双击进入 Z: 盘
3. 右键 → 新建 → 文本文档
4. 编辑并保存
5. 复制粘贴文件
6. 拖拽文件到其他位置
7. 删除文件

**记录结果**:
- [ ] 资源管理器显示正常: ✅ / ❌
- [ ] 右键菜单功能正常: ✅ / ❌
- [ ] 拖拽操作正常: ✅ / ❌
- [ ] 缩略图显示: ✅ / ❌（图片文件）

---

## 📊 稳定性测试

### 测试 8: 长时间运行测试

```powershell
# 创建长时间测试脚本
$longRunScript = @'
$duration = 3600  # 测试 1 小时
$logFile = "$env:USERPROFILE\long-run-test.log"

"开始长时间运行测试: $(Get-Date)" | Out-File $logFile
"测试时长: $duration 秒" | Out-File $logFile -Append

$startTime = Get-Date
$counter = 0

while (((Get-Date) - $startTime).TotalSeconds -lt $duration) {
    $counter++
    
    # 写入测试
    "Test $counter at $(Get-Date)" | Out-File "Z:\long-run-$counter.txt"
    
    # 读取测试
    $content = Get-Content "Z:\long-run-$counter.txt"
    
    # 删除测试
    Remove-Item "Z:\long-run-$counter.txt"
    
    # 每 10 次记录一次
    if ($counter % 10 -eq 0) {
        "完成 $counter 次操作 at $(Get-Date)" | Out-File $logFile -Append
        Write-Host "完成 $counter 次操作"
    }
    
    Start-Sleep -Seconds 10
}

"测试完成: $(Get-Date)" | Out-File $logFile -Append
"总操作次数: $counter" | Out-File $logFile -Append
'@

# 保存脚本
$longRunScript | Out-File -FilePath "$env:USERPROFILE\Desktop\long-run-test.ps1" -Encoding UTF8

# 后台运行测试
Start-Process powershell -ArgumentList "-File", "$env:USERPROFILE\Desktop\long-run-test.ps1"

Write-Host "长时间测试已启动，查看日志: $env:USERPROFILE\long-run-test.log"
```

### 测试 9: 异常恢复测试

```powershell
# 1. 正常创建文件
Set-Location Z:\
"Before disconnect" | Out-File recovery-test.txt

# 2. 模拟网络中断
# - 禁用网络适配器
# - 或拔掉网线
# - 等待 30 秒

# 3. 尝试操作（应该失败或挂起）
"During disconnect" | Out-File recovery-test2.txt

# 4. 恢复网络连接
# - 启用网络适配器
# - 或插回网线

# 5. 等待 rclone 自动重连（观察日志）
Get-Content $env:USERPROFILE\rclone-mount-poc.log -Tail 20 -Wait

# 6. 验证恢复后的操作
"After reconnect" | Out-File recovery-test3.txt
Get-ChildItem Z:\

# 7. 验证数据完整性
Get-Content Z:\recovery-test.txt
Get-Content Z:\recovery-test3.txt
```

**记录结果**:
- [ ] 网络中断时操作行为: _____
- [ ] 自动重连时间: _____ 秒
- [ ] 重连后数据完整性: ✅ / ❌
- [ ] 是否需要手动重新挂载: ✅ / ❌

---

## 💰 成本评估

### 测试 10: 成本计算

```powershell
# 获取存储桶统计信息
$bucketName = Get-Content "$env:TEMP\rclone-poc-bucket.txt"

# 查看存储用量
aws s3 ls s3://$bucketName --recursive --human-readable --summarize

# 创建成本估算脚本
$costScript = @'
param(
    [int]$StorageGB = 10,
    [int]$RequestsPerDay = 1000,
    [int]$TransferGB = 5
)

# 中国区宁夏价格（2025）
$storagePrice = 0.144      # ¥/GB/月
$putPrice = 0.01           # ¥/千次
$getPrice = 0.001          # ¥/千次
$transferPrice = 0.6       # ¥/GB

# 计算
$storageCost = $StorageGB * $storagePrice
$putCost = ($RequestsPerDay * 30 / 1000) * $putPrice * 0.5
$getCost = ($RequestsPerDay * 30 / 1000) * $getPrice * 0.5
$transferCost = $TransferGB * $transferPrice
$totalCost = $storageCost + $putCost + $getCost + $transferCost

Write-Host "=== S3 + rclone 月成本估算 ==="
Write-Host "存储容量: $StorageGB GB"
Write-Host "每日请求: $RequestsPerDay 次"
Write-Host "月传输量: $TransferGB GB"
Write-Host ""
Write-Host "存储成本: ¥$($storageCost.ToString('F2'))"
Write-Host "PUT 请求: ¥$($putCost.ToString('F2'))"
Write-Host "GET 请求: ¥$($getCost.ToString('F2'))"
Write-Host "数据传输: ¥$($transferCost.ToString('F2'))"
Write-Host "----------------------------"
Write-Host "总计: ¥$($totalCost.ToString('F2')) / 月"
'@

# 保存脚本
$costScript | Out-File -FilePath "$env:USERPROFILE\Desktop\cost-estimate.ps1" -Encoding UTF8

# 运行成本估算（示例：10GB 存储，每天 1000 次请求，每月 5GB 传输）
& "$env:USERPROFILE\Desktop\cost-estimate.ps1" -StorageGB 10 -RequestsPerDay 1000 -TransferGB 5
```

---

## 🔍 监控和日志

### 查看 rclone 日志

```powershell
# 实时查看日志
Get-Content $env:USERPROFILE\rclone-mount-poc.log -Tail 20 -Wait

# 查看错误日志
Select-String -Path $env:USERPROFILE\rclone-mount-poc.log -Pattern "ERROR"

# 查看最近 50 行日志
Get-Content $env:USERPROFILE\rclone-mount-poc.log -Tail 50
```

### 监控挂载状态

```powershell
# 创建监控脚本
$monitorScript = @'
$driveLetter = "Z:"
$logFile = "$env:USERPROFILE\monitor-rclone.log"

while ($true) {
    if (Test-Path $driveLetter) {
        $message = "[$(Get-Date)] ✅ rclone 挂载正常"
        Write-Host $message
        $message | Out-File $logFile -Append
    } else {
        $message = "[$(Get-Date)] ❌ rclone 挂载断开，请检查"
        Write-Host $message -ForegroundColor Red
        $message | Out-File $logFile -Append
        
        # 可选：自动重新挂载
        # & "$env:USERPROFILE\Desktop\mount-s3.ps1"
    }
    Start-Sleep -Seconds 60
}
'@

# 保存脚本
$monitorScript | Out-File -FilePath "$env:USERPROFILE\Desktop\monitor-rclone.ps1" -Encoding UTF8

# 后台运行监控
Start-Process powershell -ArgumentList "-File", "$env:USERPROFILE\Desktop\monitor-rclone.ps1"
```

### 查看 Windows 事件日志

```powershell
# 查看 WinFsp 相关事件
Get-EventLog -LogName Application -Source "WinFsp" -Newest 20

# 查看系统错误
Get-EventLog -LogName System -EntryType Error -Newest 20 | Where-Object {$_.Message -like "*WinFsp*"}
```

---

## 🧹 清理工作

### 卸载挂载

```powershell
# 方式 1: 在资源管理器中右键 Z: 盘 → 弹出

# 方式 2: 使用 PowerShell
# 找到 rclone 进程并终止
Get-Process | Where-Object {$_.ProcessName -eq "rclone"} | Stop-Process -Force

# 验证卸载
Test-Path Z:\
```

### 停止后台进程

```powershell
# 停止所有 rclone 进程
Get-Process | Where-Object {$_.ProcessName -eq "rclone"} | Stop-Process -Force

# 停止监控脚本
Get-Process | Where-Object {$_.CommandLine -like "*monitor-rclone*"} | Stop-Process -Force

# 停止长时间测试
Get-Process | Where-Object {$_.CommandLine -like "*long-run-test*"} | Stop-Process -Force
```

### 删除测试资源

```powershell
# 删除 S3 存储桶内容
$bucketName = Get-Content "$env:TEMP\rclone-poc-bucket.txt"
aws s3 rm s3://$bucketName --recursive

# 删除存储桶
aws s3 rb s3://$bucketName

# 删除本地文件
Remove-Item $env:USERPROFILE\rclone-mount-poc.log -ErrorAction SilentlyContinue
Remove-Item $env:USERPROFILE\long-run-test.log -ErrorAction SilentlyContinue
Remove-Item $env:USERPROFILE\monitor-rclone.log -ErrorAction SilentlyContinue
Remove-Item $env:TEMP\rclone-poc-bucket.txt -ErrorAction SilentlyContinue

# 删除桌面脚本
Remove-Item $env:USERPROFILE\Desktop\mount-s3.ps1 -ErrorAction SilentlyContinue
Remove-Item $env:USERPROFILE\Desktop\long-run-test.ps1 -ErrorAction SilentlyContinue
Remove-Item $env:USERPROFILE\Desktop\monitor-rclone.ps1 -ErrorAction SilentlyContinue
Remove-Item $env:USERPROFILE\Desktop\cost-estimate.ps1 -ErrorAction SilentlyContinue

# 删除 rclone 配置（可选）
rclone config delete s3-poc
```

### 卸载软件（可选）

```powershell
# 卸载 WinFsp
# 控制面板 → 程序和功能 → WinFsp → 卸载

# 删除 rclone
Remove-Item "C:\Program Files\rclone" -Recurse -Force

# 从 PATH 中移除 rclone
$oldPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$newPath = $oldPath -replace ";C:\\Program Files\\rclone", ""
[Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
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
| Office 文件编辑 | ✅ / ❌ | |
| 资源管理器集成 | ✅ / ❌ | |

#### 2. 性能测试
| 测试项 | 结果 | 备注 |
|--------|------|------|
| 小文件写入（1MB x 10） | ___ 秒 | |
| 大文件写入（100MB） | ___ 秒 | |
| 首次读取（50MB） | ___ 秒 | |
| 缓存读取（50MB） | ___ 秒 | |
| Office 文件打开速度 | ___ 秒 | |

#### 3. 稳定性测试
| 测试项 | 结果 | 备注 |
|--------|------|------|
| 长时间运行（1小时） | ✅ / ❌ | |
| 网络中断恢复 | ✅ / ❌ | |
| 自动重连时间 | ___ 秒 | |
| 系统重启后挂载 | ✅ / ❌ | |

#### 4. 用户体验
| 项目 | 评分（1-5） | 备注 |
|------|------------|------|
| 安装难度 | ___ | |
| 配置复杂度 | ___ | |
| 使用便利性 | ___ | |
| 响应速度 | ___ | |
| 稳定性 | ___ | |

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
- ✅ 像本地磁盘一样使用
- ✅ 支持 Windows 盘符挂载
- ✅ 

**缺点**:
- ❌ 不支持文件锁（多人编辑 Office 文档有风险）
- ❌ 性能不如本地磁盘
- ❌ 依赖网络连接
- ❌ 首次访问有延迟
- ❌ 

#### 7. 适用场景评估

**✅ 推荐使用的场景**:
- 单用户文件访问
- 静态文件存储
- 备份和归档
- 图片/视频存储
- 日志文件存储

**❌ 不推荐使用的场景**:
- 多人同时编辑 Office 文档
- 数据库文件存储
- 高频率小文件操作
- 对延迟敏感的应用
- 需要文件锁的场景

#### 8. 最终建议

**是否推荐采用**: ✅ 推荐 / ⚠️ 有条件推荐 / ❌ 不推荐

**推荐理由**:
- 

**注意事项**:
- 

**替代方案**:
- 如果需要文件锁，建议使用 FSx for Windows（最小配置约 ¥25/月）
- 如果可以修改应用代码，建议直接使用 S3 SDK

---

## 🔗 参考资源

### 官方文档
- [rclone 官方文档](https://rclone.org/docs/)
- [rclone mount 文档](https://rclone.org/commands/rclone_mount/)
- [rclone Windows 指南](https://rclone.org/install/#windows)
- [WinFsp 官网](https://winfsp.dev/)
- [AWS S3 定价](https://aws.amazon.com/cn/s3/pricing/)

### 相关文档
- [AWS 存储服务选择指南](./AWS存储服务选择指南.md)

### 常见问题
- [rclone FAQ](https://rclone.org/faq/)
- [WinFsp 常见问题](https://github.com/winfsp/winfsp/wiki/Frequently-Asked-Questions)

### 社区支持
- [rclone 论坛](https://forum.rclone.org/)
- [rclone GitHub](https://github.com/rclone/rclone)

---

## ⚠️ 重要注意事项

### 1. 文件锁限制
- **rclone 不支持文件锁**
- 多人同时编辑同一个 Office 文档会导致数据丢失
- 不适合需要并发写入的场景

### 2. 性能考虑
- 首次访问文件会有网络延迟（通常 100-500ms）
- 启用缓存后性能显著提升
- 大文件传输速度取决于网络带宽

### 3. 网络依赖
- 完全依赖网络连接
- 网络中断会导致挂载不可用
- 建议配置监控和自动重连

### 4. 成本控制
- 频繁的小文件操作会产生大量 API 请求
- 建议启用缓存减少请求次数
- 定期检查 AWS 账单

### 5. 安全建议
- 使用 IAM 用户而非 root 账号
- 遵循最小权限原则
- 定期轮换访问密钥
- 启用 S3 存储桶加密

### 6. Windows 特定注意事项
- WinFsp 安装后必须重启
- 某些杀毒软件可能阻止 WinFsp
- 防火墙需要允许 rclone 访问网络
- 盘符冲突时选择其他盘符（如 Y:, X:）

---

## 🆘 故障排查

### 问题 1: 挂载失败

**症状**: 执行 `rclone mount` 后无法看到 Z: 盘

**解决方案**:
```powershell
# 1. 检查 WinFsp 服务
Get-Service | Where-Object {$_.Name -like "*WinFsp*"}

# 2. 启动 WinFsp 服务
Start-Service WinFsp.Launcher

# 3. 检查盘符是否被占用
Get-PSDrive

# 4. 更换盘符重试
rclone mount s3-poc:bucket Y: --vfs-cache-mode full
```

### 问题 2: 访问速度慢

**症状**: 打开文件或列出目录很慢

**解决方案**:
```powershell
# 增加缓存设置
rclone mount s3-poc:bucket Z: `
  --vfs-cache-mode full `
  --vfs-cache-max-size 2G `
  --buffer-size 64M `
  --dir-cache-time 10m
```

### 问题 3: 网络中断后无法恢复

**症状**: 网络恢复后 Z: 盘仍然无法访问

**解决方案**:
```powershell
# 1. 终止 rclone 进程
Get-Process rclone | Stop-Process -Force

# 2. 重新挂载
& "$env:USERPROFILE\Desktop\mount-s3.ps1"
```

### 问题 4: Office 文件保存失败

**症状**: 编辑 Office 文件后无法保存

**解决方案**:
- 确保使用 `--vfs-cache-mode full`
- 增加 `--vfs-write-back` 参数
- 或者先保存到本地磁盘，再复制到 Z: 盘

### 问题 5: 权限错误

**症状**: 提示"访问被拒绝"

**解决方案**:
```powershell
# 检查 AWS 凭证
aws sts get-caller-identity --profile poc-test

# 检查 S3 权限
aws s3 ls s3://bucket-name --profile poc-test

# 重新配置 rclone
rclone config
```

---

## 📞 技术支持

### 联系方式
- **邮箱**: wangrenjun@gmail.com
- **参考文档**: [AWS 存储服务选择指南](./AWS存储服务选择指南.md)

### 获取帮助
1. 查看 rclone 日志文件
2. 查看 Windows 事件日志
3. 访问 rclone 官方论坛
4. 联系 AWS 技术支持

---

**文档版本**: 1.0  
**最后更新**: 2025-12-03  
**测试环境**: Windows 10/11, Windows Server 2016+  
**AWS 区域**: 中国区（宁夏/北京）  
**目标用户**: 企业客户、IT 管理员

---

## 📋 快速检查清单

POC 执行前检查：
- [ ] Windows 10/11 或 Windows Server 2016+
- [ ] 管理员权限
- [ ] 稳定的网络连接
- [ ] AWS 账号和 IAM 用户
- [ ] 已安装 AWS CLI
- [ ] 已安装 rclone
- [ ] 已安装 WinFsp
- [ ] 已重启计算机（安装 WinFsp 后）

POC 执行后检查：
- [ ] 完成所有功能测试
- [ ] 完成性能测试
- [ ] 完成稳定性测试
- [ ] 记录测试结果
- [ ] 填写 POC 报告
- [ ] 清理测试资源
- [ ] 删除测试存储桶

---

**祝测试顺利！** 🎉
