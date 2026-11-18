---
title: "secretsource — 从引用获取密钥"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource 从引用（文件、macOS 钥匙串、Secret Service、KeePassXC）获取 PIN、密码或恢复码，使磁盘上不必留下明文文件。"
tags: [库, secretsource, 密钥]
---

**不应留在文件里的 PIN，从哪里取得？** **引用**说明密钥存放在哪里；
`secretsource.Open` 负责取回。引用本身不含密钥，所以可以出现在选项、脚本或
shell 历史记录里。

```sh
go get github.com/go-authn/secretsource@v0.3.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| 引用 | 读取 |
|---|---|
| `file:PATH` | 仅所有者可读的普通文件（权限 0600 或更严格）；去掉结尾的一个换行符 |
| `keychain:SERVICE/ACCOUNT` | macOS 钥匙串中的一个通用密码项 |
| `secretservice:SERVICE/ACCOUNT` | 属性为 `service=SERVICE`、`account=ACCOUNT` 的 freedesktop Secret Service 项（GNOME Keyring、KWallet、KeePassXC 的 Secret Service 集成） |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | 带有所有这些属性的唯一一个 Secret Service 项；匹配到多个则拒绝 |
| `keepassxc:URL` | **URL 字段**为该 URL 的 KeePassXC 条目（`https://NAME.invalid/...` 是个好选择，永远不会被解析）；两个条目 URL 相同会因有歧义而被拒绝 |

`keepassxc:by-uuid/...` 和 `keepassxc:by-path/...` 会被**拒绝**：当查找命中没有
URL 的条目时，KeePassXC 2.8.0 会崩溃。

**没有任何方案会执行命令**：选项绝不能能够启动进程。没有方案的引用会被拒绝，
而不是被猜成路径（路径要写成 `file:`）。超过 4096 字节的密钥，或管理器返回的
空密钥，都会被拒绝；一次调用随其上下文结束（没有截止时间时为 2 分钟），即使
管理器正在等你解锁。

## KeePassXC {#keepassxc}

KeePassXC 通过其浏览器集成协议访问，支持 macOS 和 Linux；Windows 尚未实现。

1. 在 KeePassXC 中启用 *Settings > Browser Integration*。
2. 每个数据库关联这台机器一次，并在 KeePassXC 中批准：
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. 创建条目，并在其 **URL 字段**填入 `https://fido.invalid/yubikey-5c`（任何
   没有其他条目使用的 URL：引用就是这个 URL）。在不打印密钥的情况下检查引用：
   ```sh
   secretsource check 'keepassxc:https://fido.invalid/yubikey-5c'
   ```

第一次读取某个条目时，KeePassXC 会显示其访问对话框。

`fido --pin-from`（见 [fido]({{< relref "/libraries/fido.md" >}})）以及
`theca --pin-from`、`--password-from` 和 `--recovery-from` 使用它。

## 参考 {#reference}

本页以
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) 的
README 为准。
