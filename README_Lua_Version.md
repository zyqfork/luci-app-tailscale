# Tailscale LuCI 插件 - Lua版本

这是Tailscale LuCI插件的Lua版本，专门为OpenWrt 18.0.3及更早版本设计，这些版本使用传统的Lua-based LuCI框架而不是现代的JavaScript-based LuCI。

## 特性

- **完全兼容OpenWrt 18.0.3**: 使用传统的Lua-based LuCI框架
- **完整的功能支持**: 包含JavaScript版本的所有核心功能
- **简化的架构**: 使用Lua CBI模块，无需复杂的JavaScript依赖
- **更好的性能**: 在老旧硬件上运行更高效

## 与JavaScript版本的区别

| 特性 | JavaScript版本 | Lua版本 |
|------|---------------|---------|
| LuCI框架 | JavaScript-based | Lua-based |
| 最低OpenWrt版本 | 19.07+ | 18.03+ |
| 性能 | 现代硬件优化 | 老旧硬件优化 |
| 依赖 | 需要现代LuCI | 传统LuCI支持 |

## 文件结构

```
luci-app-tailscale/
├── luasrc/
│   ├── controller/
│   │   └── tailscale.lua          # 主控制器
│   └── model/cbi/tailscale/
│       ├── setting.lua            # 全局设置页面
│       ├── interface.lua          # 接口信息页面
│       └── log.lua                # 日志页面
├── root/
│   ├── etc/
│   │   ├── config/tailscale      # 配置文件
│   │   ├── init.d/tailscale       # 启动脚本
│   │   └── uci-defaults/         # 默认配置
│   └── usr/
│       ├── share/
│       │   ├── luci/menu.d/       # 菜单配置
│       │   └── rpcd/acl.d/        # 权限配置
│       └── sbin/                  # 辅助脚本
├── po/                            # 翻译文件
└── Makefile                       # 构建文件
```

## 安装

1. 确保你的OpenWrt系统已安装必要的依赖：
```bash
opkg update
opkg install tailscale luci-base
```

2. 构建和安装插件：
```bash
# 进入插件目录
cd luci-app-tailscale

# 构建（如果在构建环境中）
make package/luci-app-tailscale/compile V=s

# 或者直接安装预编译包
opkg install luci-app-tailscale_1.2.6-1_all.ipk
```

## 使用说明

### 1. 全局设置 (Global Settings)
- **启用/禁用**: 控制Tailscale服务的开关
- **端口设置**: 配置Tailscale监听端口（默认41641）
- **工作目录**: 配置文件和日志的存储位置
- **防火墙模式**: 选择nftables或iptables
- **日志设置**: 配置标准输出和错误日志
- **高级设置**: 包括路由接受、DNS配置、出口节点等
- **自定义服务器**: 支持使用headscale私有服务器

### 2. 接口信息 (Interface Info)
- 显示Tailscale网络接口的详细信息
- 包括IPv4/IPv6地址、MTU、上传下载统计
- 支持实时刷新功能

### 3. 日志查看 (Logs)
- 查看Tailscale服务的运行日志
- 支持日志级别过滤
- 提供滚动到顶部/底部功能
- 支持实时刷新

## 技术细节

### Lua CBI模块
本版本使用LuCI的CBI（Configuration Binding Interface）框架：
- `Map`: 配置表单
- `Section`: 配置段
- `Option`: 配置选项
- `SimpleForm`: 简单表单

### 状态获取
通过系统命令获取Tailscale状态：
```lua
-- 检查服务状态
local running = sys.call("pgrep tailscaled >/dev/null") == 0

-- 获取详细状态
local tailscale_status = sys.exec("/usr/sbin/tailscale status --json")
```

### 权限控制
使用JSON格式的ACL配置文件控制访问权限，确保安全性。

## 兼容性

- **OpenWrt版本**: 18.03及更高版本
- **LuCI版本**: 传统Lua-based LuCI
- **Tailscale**: 最新版本
- **架构**: 所有支持OpenWrt的架构

## 故障排除

### 常见问题

1. **页面无法加载**
   - 检查是否正确安装了luci-base
   - 确认文件权限正确

2. **状态显示异常**
   - 检查tailscale命令是否存在
   - 确认服务正在运行

3. **配置无法保存**
   - 检查文件系统权限
   - 确认UCI配置正确

### 调试方法

查看LuCI日志：
```bash
logread | grep luci
```

检查Tailscale状态：
```bash
tailscale status
```

## 更新日志

### v1.2.6-1 (Lua版本)
- 初始Lua版本发布
- 完整功能移植
- OpenWrt 18.03兼容性测试

## 许可证

GPL-3.0-only

## 贡献

欢迎提交Issue和Pull Request来改进这个Lua版本。
