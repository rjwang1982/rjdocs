# AWS中国区 ALB + CloudFront mTLS双向认证实现指南

**作者：** RJ.Wang  
**邮箱：** wangrenjun@gmail.com  
**创建时间：** 2025-10-31

## 概述

本文档详细介绍如何在AWS中国区使用Application Load Balancer (ALB) 和 CloudFront 实现客户端证书双向认证，以安全访问S3资源。

## 架构图

```
客户端(带证书) → CloudFront → ALB(mTLS验证) → 后端服务 → S3
```

## 前置准备

### 1. 准备证书文件

```bash
# 需要准备的证书文件
ca.crt          # CA根证书
server.crt      # 服务器证书
server.key      # 服务器私钥
client.crt      # 客户端证书
client.key      # 客户端私钥
```

### 2. 创建CA证书包

```bash
# 将CA证书打包上传到S3
aws s3 cp ca.crt s3://your-cert-bucket/ca-bundle.pem --region cn-north-1
```

## 实施步骤

### 步骤1：创建信任存储

#### 使用AWS CLI创建
```bash
aws elbv2 create-trust-store \
    --name client-cert-truststore \
    --ca-certificates-bundle-s3-bucket your-cert-bucket \
    --ca-certificates-bundle-s3-key ca-bundle.pem \
    --region cn-north-1
```

#### 记录信任存储ARN
```bash
# 输出示例
{
    "TrustStores": [
        {
            "Name": "client-cert-truststore",
            "TrustStoreArn": "arn:aws-cn:elasticloadbalancing:cn-north-1:123456789012:truststore/client-cert-truststore/1234567890abcdef"
        }
    ]
}
```

### 步骤2：导入服务器证书到ACM

#### 导入证书
```bash
aws acm import-certificate \
    --certificate fileb://server.crt \
    --private-key fileb://server.key \
    --certificate-chain fileb://ca.crt \
    --region cn-north-1
```

#### 记录证书ARN
```bash
# 输出示例
{
    "CertificateArn": "arn:aws-cn:acm:cn-north-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}
```

### 步骤3：创建目标组

```bash
aws elbv2 create-target-group \
    --name s3-proxy-targets \
    --protocol HTTP \
    --port 80 \
    --vpc-id vpc-12345678 \
    --target-type instance \
    --health-check-path /health \
    --region cn-north-1
```

### 步骤4：创建Application Load Balancer

```bash
aws elbv2 create-load-balancer \
    --name s3-proxy-alb \
    --subnets subnet-12345678 subnet-87654321 \
    --security-groups sg-12345678 \
    --scheme internet-facing \
    --type application \
    --ip-address-type ipv4 \
    --region cn-north-1
```

### 步骤5：创建HTTPS监听器（支持mTLS）

```bash
aws elbv2 create-listener \
    --load-balancer-arn arn:aws-cn:elasticloadbalancing:cn-north-1:123456789012:loadbalancer/app/s3-proxy-alb/1234567890abcdef \
    --protocol HTTPS \
    --port 443 \
    --certificates CertificateArn=arn:aws-cn:acm:cn-north-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 \
    --ssl-policy ELBSecurityPolicy-TLS-1-2-2017-01 \
    --default-actions Type=forward,TargetGroupArn=arn:aws-cn:elasticloadbalancing:cn-north-1:123456789012:targetgroup/s3-proxy-targets/1234567890abcdef \
    --mutual-authentication Mode=verify,TrustStoreArn=arn:aws-cn:elasticloadbalancing:cn-north-1:123456789012:truststore/client-cert-truststore/1234567890abcdef \
    --region cn-north-1
```

### 步骤6：配置安全组

#### ALB安全组配置
```bash
# 创建ALB安全组
aws ec2 create-security-group \
    --group-name alb-mtls-sg \
    --description "ALB mTLS Security Group" \
    --vpc-id vpc-12345678 \
    --region cn-north-1

# 允许HTTPS流量
aws ec2 authorize-security-group-ingress \
    --group-id sg-12345678 \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region cn-north-1

# 允许HTTP流量（用于健康检查）
aws ec2 authorize-security-group-ingress \
    --group-id sg-12345678 \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region cn-north-1
```

### 步骤7：部署后端服务

#### 创建EC2实例作为代理服务器
```bash
# 启动EC2实例
aws ec2 run-instances \
    --image-id ami-12345678 \
    --count 1 \
    --instance-type t3.micro \
    --key-name your-key-pair \
    --security-group-ids sg-87654321 \
    --subnet-id subnet-12345678 \
    --user-data file://user-data.sh \
    --region cn-north-1
```

#### 用户数据脚本 (user-data.sh)
```bash
#!/bin/bash
yum update -y
yum install -y nginx

# 配置Nginx作为S3代理
cat > /etc/nginx/conf.d/s3-proxy.conf << 'EOF'
server {
    listen 80;
    server_name _;
    
    location /health {
        return 200 "OK";
        add_header Content-Type text/plain;
    }
    
    location / {
        # 验证客户端证书信息（从ALB传递的头部）
        if ($http_x_amzn_mtls_clientcert_serial = "") {
            return 403 "Client certificate required";
        }
        
        # 代理到S3
        proxy_pass https://your-bucket.s3.cn-north-1.amazonaws.com.cn;
        proxy_set_header Host your-bucket.s3.cn-north-1.amazonaws.com.cn;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        # 传递客户端证书信息
        proxy_set_header X-Client-Cert-Serial $http_x_amzn_mtls_clientcert_serial;
        proxy_set_header X-Client-Cert-Subject $http_x_amzn_mtls_clientcert_subject;
    }
}
EOF

systemctl start nginx
systemctl enable nginx
```

### 步骤8：注册目标到目标组

```bash
aws elbv2 register-targets \
    --target-group-arn arn:aws-cn:elasticloadbalancing:cn-north-1:123456789012:targetgroup/s3-proxy-targets/1234567890abcdef \
    --targets Id=i-1234567890abcdef0,Port=80 \
    --region cn-north-1
```

### 步骤9：创建CloudFront分配

#### 创建分配配置文件 (cloudfront-config.json)
```json
{
  "CallerReference": "s3-mtls-proxy-2024",
  "Comment": "S3 mTLS Proxy via ALB",
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "alb-origin",
        "DomainName": "s3-proxy-alb-1234567890.cn-north-1.elb.amazonaws.com.cn",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "https-only",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          }
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "alb-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "ForwardedValues": {
      "QueryString": true,
      "Cookies": {"Forward": "none"},
      "Headers": {
        "Quantity": 3,
        "Items": ["Authorization", "X-Client-Cert", "X-Client-Cert-Serial"]
      }
    },
    "TrustedSigners": {
      "Enabled": false,
      "Quantity": 0
    },
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000
  },
  "Enabled": true,
  "PriceClass": "PriceClass_All"
}
```

#### 创建CloudFront分配
```bash
aws cloudfront create-distribution \
    --distribution-config file://cloudfront-config.json \
    --region cn-north-1
```

## 测试和验证

### 步骤10：客户端测试

#### Python测试脚本
```python
import requests
import ssl

# 配置客户端证书
cert_file = 'client.crt'
key_file = 'client.key'

# 测试请求
url = 'https://d1234567890abc.cloudfront.net/test-file.txt'

try:
    response = requests.get(
        url,
        cert=(cert_file, key_file),
        verify=True,  # 验证服务器证书
        timeout=30
    )
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")
    
except requests.exceptions.SSLError as e:
    print(f"SSL Error: {e}")
except requests.exceptions.RequestException as e:
    print(f"Request Error: {e}")
```

#### 使用curl测试
```bash
curl -v \
  --cert client.crt \
  --key client.key \
  --cacert ca.crt \
  https://d1234567890abc.cloudfront.net/test-file.txt
```

### 步骤11：监控和日志

#### 启用ALB访问日志
```bash
aws elbv2 modify-load-balancer-attributes \
    --load-balancer-arn arn:aws-cn:elasticloadbalancing:cn-north-1:123456789012:loadbalancer/app/s3-proxy-alb/1234567890abcdef \
    --attributes Key=access_logs.s3.enabled,Value=true Key=access_logs.s3.bucket,Value=your-log-bucket \
    --region cn-north-1
```

#### 监控指标
```bash
# 查看ALB指标
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApplicationELB \
    --metric-name RequestCount \
    --dimensions Name=LoadBalancer,Value=app/s3-proxy-alb/1234567890abcdef \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 3600 \
    --statistics Sum \
    --region cn-north-1
```

## 故障排除

### 常见问题检查

```bash
# 1. 检查信任存储状态
aws elbv2 describe-trust-stores --region cn-north-1

# 2. 检查监听器配置
aws elbv2 describe-listeners \
    --load-balancer-arn arn:aws-cn:elasticloadbalancing:cn-north-1:123456789012:loadbalancer/app/s3-proxy-alb/1234567890abcdef \
    --region cn-north-1

# 3. 检查目标健康状态
aws elbv2 describe-target-health \
    --target-group-arn arn:aws-cn:elasticloadbalancing:cn-north-1:123456789012:targetgroup/s3-proxy-targets/1234567890abcdef \
    --region cn-north-1
```

### 常见错误及解决方案

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| SSL handshake failed | 客户端证书无效 | 检查证书有效期和CA签名 |
| 403 Forbidden | 证书验证失败 | 确认信任存储包含正确的CA证书 |
| 502 Bad Gateway | 后端服务不可用 | 检查目标组健康状态 |
| 504 Gateway Timeout | 后端响应超时 | 检查后端服务性能 |

## 安全最佳实践

### 1. 证书管理
- 定期轮换客户端和服务器证书
- 使用强加密算法（RSA 2048位或ECC 256位）
- 设置合理的证书有效期

### 2. 网络安全
- 限制安全组入站规则
- 使用VPC端点访问S3
- 启用VPC Flow Logs

### 3. 监控和审计
- 启用CloudTrail记录API调用
- 配置CloudWatch告警
- 定期审查访问日志

## 成本优化

### 1. CloudFront缓存策略
- 配置合适的TTL值
- 使用压缩减少传输成本
- 选择合适的价格等级

### 2. ALB优化
- 使用适当的实例类型
- 配置自动扩缩容
- 监控并优化目标组大小

## AWS官方文档参考

### ALB mTLS相关文档
1. **Application Load Balancer 相互 TLS 身份验证**
   - 中文：https://docs.amazonaws.cn/elasticloadbalancing/latest/application/mutual-authentication.html
   - 英文：https://docs.aws.amazon.com/elasticloadbalancing/latest/application/mutual-authentication.html

2. **创建和管理信任存储**
   - https://docs.amazonaws.cn/elasticloadbalancing/latest/application/create-trust-store.html

3. **ALB 监听器配置**
   - https://docs.amazonaws.cn/elasticloadbalancing/latest/application/load-balancer-listeners.html

4. **ALB 安全最佳实践**
   - https://docs.amazonaws.cn/elasticloadbalancing/latest/application/load-balancer-security.html

### CloudFront相关文档
5. **CloudFront 用户指南**
   - 中文：https://docs.amazonaws.cn/AmazonCloudFront/latest/DeveloperGuide/
   - 配置源站：https://docs.amazonaws.cn/AmazonCloudFront/latest/DeveloperGuide/DownloadDistS3AndCustomOrigins.html

6. **CloudFront 安全概述**
   - https://docs.amazonaws.cn/AmazonCloudFront/latest/DeveloperGuide/SecurityAndPrivacyOverview.html

### 证书管理文档
7. **AWS Certificate Manager 用户指南**
   - https://docs.amazonaws.cn/acm/latest/userguide/
   - 导入证书：https://docs.amazonaws.cn/acm/latest/userguide/import-certificate.html

### CLI参考文档
8. **AWS CLI 命令参考**
   - ELBv2：https://docs.amazonaws.cn/cli/latest/reference/elbv2/
   - CloudFront：https://docs.amazonaws.cn/cli/latest/reference/cloudfront/
   - ACM：https://docs.amazonaws.cn/cli/latest/reference/acm/

### 监控和日志文档
9. **CloudWatch 用户指南**
   - https://docs.amazonaws.cn/AmazonCloudWatch/latest/monitoring/

10. **VPC Flow Logs**
    - https://docs.amazonaws.cn/vpc/latest/userguide/flow-logs.html

### 中国区特殊说明
11. **AWS中国区域服务**
    - https://www.amazonaws.cn/about-aws/global-infrastructure/regional-product-services/

12. **中国区域与全球区域的差异**
    - https://docs.amazonaws.cn/aws/latest/userguide/aws-ug.pdf

## 总结

本方案通过ALB的mTLS功能实现了真正的客户端证书双向认证，结合CloudFront提供全球加速和缓存功能。该架构具有以下优势：

- **高安全性**：真正的双向TLS认证
- **高性能**：CloudFront全球加速
- **高可用性**：多可用区部署
- **可扩展性**：支持自动扩缩容
- **成本效益**：按需付费模式

通过遵循本文档的步骤和最佳实践，您可以在AWS中国区成功部署一个安全、高效的S3访问解决方案。

---
**作者：** RJ.Wang  
**邮箱：** wangrenjun@gmail.com  
**文档版本：** v1.0  
**最后更新：** 2025-10-31  
**适用于：** AWS中国区（北京、宁夏）
