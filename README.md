# AWS 技术文档集合

**作者**: RJ.Wang  
**邮箱**: wangrenjun@gmail.com  
**创建时间**: 2025-12-03

---

## 📚 文档目录

### CloudFront 优化
- [CloudFront 优化最终报告](cloudfront-optimization-final-report.md)
- [CloudFront 优化摘要](cloudfront-optimization-summary.md)

### AWS 中国区指南
- [AWS 中国区 ALB/CloudFront mTLS 指南](AWS_China_ALB_CloudFront_mTLS_Guide.md)
- [AWS 存储服务选择指南](AWS存储服务选择指南.md)

### Aurora 数据库
- [Aurora 蓝绿切换检查说明](aurora-bg-switchover-check-README.md)
- [Aurora 蓝绿切换检查脚本](aurora-bg-switchover-check.sh)
- [Aurora Secrets Manager 迁移指南](aurora-secrets-manager-migration.md)

### AWS MSP 案例研究
- [AWS MSP 案例研究检查清单](AWS_MSP_Case_Study_Checklist.md)
- [AWS MSP 案例研究示例](AWS_MSP_Case_Study_Example.md)
- [AWS MSP 案例研究模板](AWS_MSP_Case_Study_Template.md)
- [AWS 专业化项目案例研究指南](AWS_Specialization_Programs_Public_Case_Study_Guide_CN.md)

### 安全与网络
- [AWS Secrets Manager 博客](aws-secrets-manager-blog.md)
- [AWS 网络故障排查指南](aws-network-troubleshooting-guide.md)

### 云原生
- [云原生指南](Cloud_Native_Guide.md)

### 存储与文件系统
- [rclone 技术指南](rclone-technical-guide.md) - rclone 功能介绍、工作原理和最佳实践
- [rclone vs Mountpoint 对比分析](rclone-vs-mountpoint-comparison.md) - rclone 与 AWS Mountpoint 全面对比，包含性能、功能、使用场景等
- [rclone S3 挂载 POC SOP (SUSE)](rclone-s3-mount-poc-sop-suse.md) - SUSE Linux 环境下 S3 + rclone 挂载方案验证
- [rclone S3 挂载 POC SOP (Windows)](rclone-s3-mount-poc-sop-windows.md) - Windows 环境下 S3 + rclone 挂载方案验证
- [rclone S3 挂载 POC SOP (通用)](rclone-s3-mount-poc-sop.md) - 通用 S3 + rclone 挂载方案验证

---

## 🎯 使用说明

这些文档涵盖了 AWS 各个服务的最佳实践、故障排查、优化方案等内容,适合:
- AWS 解决方案架构师
- DevOps 工程师
- 云平台运维人员
- AWS 学习者

---

## 📝 文档分类

### 优化类
- CloudFront 缓存优化
- 性能调优指南

### 运维类
- 数据库迁移
- 故障排查
- 监控告警

### 架构类
- 安全架构设计
- 网络架构规划
- 存储方案选择

### 案例类
- MSP 案例研究
- 最佳实践分享

### 实验类
- POC 验证流程
- 技术预研文档

---

## 🔄 更新日志

- **2025-12-03**: 
  - 初始化仓库，整理所有 AWS 技术文档
  - 新增 rclone 技术指南，详细介绍 VFS 缓存模式、工作原理和关键参数
  - 新增 rclone S3 挂载 POC 验证文档（SUSE/Windows/通用版本）
  - 完善 rclone vs Mountpoint 对比文档，新增：
    - Windows 平台支持详情（rclone 完整支持，Mountpoint 不支持）
    - 6 个典型使用场景对比（高性能数据处理、跨云迁移、Windows 环境等）
    - API 调用成本分析
    - 完整的安装部署指南（Linux/macOS/Windows）
    - 详细的配置示例和 systemd 服务配置
    - 故障排查指南（常见问题和解决方案）
    - 监控和日志最佳实践
    - 决策树帮助选择合适的工具

---

## 📧 联系方式

如有问题或建议,请联系: wangrenjun@gmail.com
