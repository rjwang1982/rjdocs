# Aurora 数据库迁移到 AWS Secrets Manager 指南

## 概述

本指南介绍如何将 AWS RDS Aurora 数据库连接从传统的用户名/密码方式迁移到 AWS Secrets Manager 管理。

## 重要说明

- **无需重启 Aurora**：Secrets Manager 是客户端功能，Aurora 无需任何配置变更
- **无缝迁移**：Aurora 仍然接收标准的数据库连接请求
- **向后兼容**：可以并行运行两种连接方式进行平滑迁移

## 迁移步骤

### 1. 创建 Secret

```bash
aws secretsmanager create-secret \
    --name "rds/aurora/prod" \
    --description "Aurora database credentials" \
    --secret-string '{
        "username": "your_username",
        "password": "your_password",
        "engine": "aurora-mysql",
        "host": "your-aurora-cluster.cluster-xxx.region.rds.amazonaws.com",
        "port": 3306,
        "dbname": "your_database"
    }'
```

### 2. 配置自动轮换（可选）

```bash
aws secretsmanager rotate-secret \
    --secret-id "rds/aurora/prod" \
    --rotation-rules AutomaticallyAfterDays=30
```

### 3. 更新 IAM 权限

为应用程序添加访问 Secrets Manager 的权限：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:region:account:secret:rds/aurora/prod-*"
        }
    ]
}
```

### 4. 修改应用代码

#### Python 示例

```python
import boto3
import json
import pymysql

def get_secret():
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId='rds/aurora/prod')
    return json.loads(response['SecretString'])

def connect_to_db():
    secret = get_secret()
    
    connection = pymysql.connect(
        host=secret['host'],
        user=secret['username'],
        password=secret['password'],
        database=secret['dbname'],
        port=secret['port']
    )
    return connection

# 使用连接
conn = connect_to_db()
```

#### Node.js 示例

```javascript
const AWS = require('aws-sdk');
const mysql = require('mysql2/promise');

const secretsManager = new AWS.SecretsManager();

async function getSecret() {
    const response = await secretsManager.getSecretValue({
        SecretId: 'rds/aurora/prod'
    }).promise();
    
    return JSON.parse(response.SecretString);
}

async function connectToDb() {
    const secret = await getSecret();
    
    const connection = await mysql.createConnection({
        host: secret.host,
        user: secret.username,
        password: secret.password,
        database: secret.dbname,
        port: secret.port
    });
    
    return connection;
}
```

## 迁移策略

### 推荐的迁移步骤

1. **测试环境验证**
   - 在测试环境先实施 Secrets Manager 集成
   - 验证所有功能正常工作

2. **并行运行**
   - 保持原有连接方式不变
   - 同时部署支持 Secrets Manager 的新代码
   - 通过配置开关控制使用哪种方式

3. **分批切换**
   - 逐步将应用实例切换到 Secrets Manager
   - 监控连接状态和应用性能

4. **清理旧配置**
   - 确认所有实例稳定运行后
   - 移除硬编码的数据库凭证
   - 删除相关的环境变量或配置文件

## 优势

- **安全性提升**：凭证集中管理，避免硬编码
- **自动轮换**：定期自动更新密码，提高安全性
- **审计追踪**：所有凭证访问都有详细日志
- **细粒度控制**：通过 IAM 精确控制访问权限
- **多环境管理**：不同环境使用不同的 Secret

## 注意事项

- 确保应用程序有足够的 IAM 权限访问 Secrets Manager
- 考虑网络延迟：首次获取 Secret 可能比直接连接稍慢
- 实施缓存策略：避免每次连接都调用 Secrets Manager API
- 监控 Secrets Manager 的 API 调用成本

## 故障排除

### 常见问题

1. **权限不足**
   ```
   AccessDenied: User is not authorized to perform secretsmanager:GetSecretValue
   ```
   解决：检查 IAM 权限配置

2. **Secret 不存在**
   ```
   ResourceNotFoundException: Secrets Manager can't find the specified secret
   ```
   解决：确认 Secret 名称和区域正确

3. **连接超时**
   - 检查网络连接
   - 验证 Aurora 集群状态
   - 确认安全组配置

## 最佳实践

- 使用描述性的 Secret 名称（如：`rds/aurora/prod`）
- 定期轮换密码（建议 30-90 天）
- 在应用中实施连接池和重试机制
- 监控 Secrets Manager 的使用情况和成本
- 为不同环境使用不同的 Secret

## 相关文档

- [AWS Secrets Manager 用户指南](https://docs.aws.amazon.com/secretsmanager/)
- [RDS 数据库身份验证](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/database-authentication.html)
- [IAM 策略示例](https://docs.aws.amazon.com/secretsmanager/latest/userguide/auth-and-access_examples.html)
