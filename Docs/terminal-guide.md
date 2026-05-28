# Terminal 功能指南

## 概述

Remodex 内置了一个**原生 iOS SSH 终端客户端**，允许用户直接从 iPhone/iPad 通过 SSH 连接到远程服务器。它**不依赖 daemon/relay 中转**，而是由 iOS 设备直接发起 SSH 连接到目标主机。

终端渲染引擎使用 **Ghostty**，支持 Catppuccin 主题，提供完整的终端体验。

---

## 架构

```
┌──────────────────────────────────────────────────┐
│  View Layer (SwiftUI)                           │
│  TerminalScreen → GhosttyTerminalSurface        │
│  TerminalRouteChrome / TerminalOptionsMenu       │
│  TerminalConnectionEditorSheet                  │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│  Service Layer                                   │
│  CodexService+Terminal (会话管理)                 │
│  RemodexNativeSSHTerminal (SSH 客户端)           │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│  Data Layer                                      │
│  RemodexTerminalProfileStore (Keychain 持久化)    │
│  RemodexTerminalPrivateKeyStore (私钥存储)        │
│  RemodexSSHKnownHostStore (主机密钥验证)           │
└──────────────────────────────────────────────────┘
```

### 核心文件

| 层 | 文件 | 职责 |
|---|---|---|
| Model | `Services/Terminal/RemodexTerminalModels.swift` | 连接配置、运行时快照、状态枚举 |
| Service | `Services/Terminal/RemodexNativeSSHTerminal.swift` | Citadel SSH 客户端封装 |
| Service | `Services/Terminal/CodexService+Terminal.swift` | 终端生命周期管理（打开/关闭/写入/调整大小） |
| Storage | `Services/Terminal/RemodexTerminalProfileStore.swift` | Keychain 存储连接配置 |
| Storage | `Services/Terminal/RemodexTerminalPrivateKeyStore.swift` | Keychain 存储私钥和密码 |
| Storage | `Services/Terminal/RemodexSSHKnownHostStore.swift` | 主机密钥验证存储 |
| View | `Views/Terminal/TerminalScreen.swift` | 主终端页面 |
| View | `Views/Terminal/GhosttyTerminalSurface.swift` | SwiftUI 包装 + Catppuccin 主题 |
| View | `Views/Terminal/GhosttyTerminalView.swift` | UIKit 层 Ghostty 渲染器 |
| View | `Views/Terminal/TerminalRouteChrome.swift` | 工具栏、D-Pad 控制器、修饰键 |
| View | `Views/Terminal/TerminalConnectionEditorSheet.swift` | SSH 连接配置界面 |
| View | `Views/Terminal/TerminalFallbackSurface.swift` | Ghostty 不可用时的文本回退界面 |

---

## 如何使用

### 入口

1. **侧边栏** — 点击 Terminal 按钮
2. **对话上下文** — AI 对话中涉及项目工作目录时，可直接打开终端到对应路径

导航路径：`SidebarView → ContentView.openTerminal() → ContentNavigationRoute.terminal → TerminalScreen`

### 首次配置

首次打开终端时需要配置 SSH 连接信息：

1. **Connection** — 输入连接字符串，支持格式：
   - `user@host` （默认端口 22）
   - `user@host:port` （自定义端口）
   - `ssh user@host` （自动去除 `ssh ` 前缀）
2. **Nickname** — 可选，连接的显示名称
3. **Authentication** — 导入 SSH 私钥（Ed25519 或 RSA），可选密码保护
4. **Advanced**（默认折叠）— 自定义端口（1-65535）和初始工作目录（cwd）

### 连接参数

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `host` | String | `""` | 远程主机地址（IP 或域名） |
| `username` | String | `""` | SSH 登录用户名 |
| `port` | Int | `22` | SSH 端口，范围 1-65535 |
| `cwd` | String | `""` | 初始工作目录 |
| `nickname` | String | `""` | 连接显示名称 |

### 终端功能

- **多会话** — 支持多个终端实例，通过菜单切换
- **文本选择 / 复制粘贴** — 长按选择，原生粘贴板集成
- **修饰键** — cmd、shift、alt、ctrl 切换按钮，支持组合键
- **D-Pad 方向键** — 工具栏内方向键，支持长按重复
- **特殊键** — Tab、Escape、Ctrl-C 等通过工具栏发送
- **字体缩放** — 6pt 到 14pt，步长 0.5pt，默认 10pt
- **终端类型** — `xterm-256color`
- **动态调整大小** — 屏幕旋转或键盘弹出时自动上报新的 cols/rows
- **缓冲区** — 最大 200,000 字符 / 200,000 字节

---

## 端口配置与连接

### 连接流程

```
用户输入连接信息 → RemodexTerminalProfile（标准化）
       ↓
从 Keychain 读取私钥和密码
       ↓
Citadel SSHClient.connect(host, port, authMethod, hostKeyValidator)
       ↓
withPTY(xterm-256color, cols, rows) → 获取 stdin/stdout 通道
       ↓
stdout 数据 → RemodexTerminalSnapshot.buffer → Ghostty 渲染
stdin 数据 ← 用户输入（键盘 + 工具栏）
```

### 端口配置方式

1. **连接字符串** — `user@host:PORT`，PORT 会被自动解析
2. **高级设置** — 在编辑器的 Advanced 区域手动填写端口号
3. **代码默认值** — `RemodexTerminalProfile.empty` 使用端口 `22`

端口验证逻辑：`max(1, min(65535, port))`

### 安全机制

- **私钥存储** — iOS Keychain，访问级别 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **主机密钥验证** — Trust-on-first-use 模式，已知主机密钥持久化存储；密钥变更时拒绝连接并提示
- **密钥类型** — 支持 Ed25519 和 RSA
- **密钥规范化** — 自动 `\r\n` → `\n` 转换
- **重连保护** — 每个会话有 UUID 实例 ID，旧会话的回调不会影响新会话

---

## 主题

终端使用 Catppuccin 配色方案，自动跟随系统外观：

| 主题 | Background | Foreground | Cursor |
|---|---|---|---|
| Light (Latte) | `#eff1f5` | `#4c4f69` | `#dc8a78` |
| Dark (Frappe) | `#101113` | `#d7d7dc` | `#4dd78a` |

16 色 ANSI 调色板在 `GhosttyTerminalSurface.swift` 中定义。

---

## 依赖

| 库 | 用途 |
|---|---|
| **GhosttyKit** | 终端渲染引擎 |
| **Citadel** | Swift SSH 客户端 |
| **NIOSSH** | SSH 协议实现 |
| **Swift Crypto** | 密钥处理 |
| **QuartzCore** | Core Animation 渲染 |

---

## 回退机制

当 Ghostty 不可用时（如未集成 GhosttyKit），自动切换到 `TerminalFallbackSurface`——基于文本的终端界面，提供基本功能但无完整渲染支持。

---

## 常见问题

**Q: 终端是否通过 relay/daemon 中转？**
A: 不。终端使用原生 SSH 直连，iOS 设备直接与远程主机建立 TCP 连接。

**Q: 支持哪些认证方式？**
A: 仅支持公钥认证（Ed25519 / RSA），不支持密码登录。

**Q: 私钥存储在哪里？**
A: iOS Keychain，受设备解锁保护。

**Q: 如何更换端口？**
A: 在连接字符串中使用 `user@host:PORT` 格式，或在高级设置中手动填写。
