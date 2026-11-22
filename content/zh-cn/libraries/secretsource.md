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
go get github.com/go-authn/secretsource@v0.7.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| 引用 | 读取 |
|---|---|
| `file:PATH` | 仅所有者可读的普通文件（Unix：权限 0600 或更严格；Windows，自 v0.7.0 起：除所有者、SYSTEM 和 Administrators 组外，不向任何人授予读写权利的访问列表）；去掉结尾的一个换行符；为空、或只含一个行结束符的文件以 `ErrEmpty` 被拒绝（自 v0.6.0 起），FIFO 则因不是普通文件而被拒绝 |
| `keychain:SERVICE/ACCOUNT` | macOS 钥匙串中的一个通用密码项 |
| `secretservice:SERVICE/ACCOUNT` | 属性为 `service=SERVICE`、`account=ACCOUNT` 的 freedesktop Secret Service 项（GNOME Keyring、KWallet、KeePassXC 的 Secret Service 集成） |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | 带有所有这些属性的唯一一个 Secret Service 项；匹配到多个则拒绝 |
| `keepassxc:URL` | **URL 字段**为该 URL 的 KeePassXC 条目（`https://NAME.invalid/...` 是个好选择，永远不会被解析）；两个条目 URL 相同会因有歧义而被拒绝 |

`keepassxc:by-uuid/...` 和 `keepassxc:by-path/...` 会被**拒绝**：当查找命中没有
URL 的条目时，KeePassXC 2.8.0 会崩溃。

**没有任何方案会执行命令**：选项绝不能能够启动进程。没有方案的引用会被拒绝，
而不是被猜成路径（路径要写成 `file:`）。超过 4096 字节的密钥，或管理器或 `file:` 返回的
空密钥，都会被拒绝（`ErrEmpty`）；一次调用随其上下文结束（没有截止时间时为 2 分钟），即使
管理器正在等你解锁。

## KeePassXC {#keepassxc}

KeePassXC 通过其浏览器集成协议访问，支持 macOS 和 Linux；Windows 尚未实现。自 v0.6.0 起，在 Unix 上，当套接字是符号链接，或其所在目录归其他用户所有、
或组或其他人可写时，套接字被拒绝，拨号之后会检查已连接对端的 uid；不再跟随旧的
`$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer` 符号链接（而是跟随
`app/org.keepassxc.KeePassXC/` 下的真实套接字）。

自 v0.6.1 起，关联文件（后备存储，在既没有 macOS 钥匙串也没有 Secret Service 时使用）先写入同一目录中的新临时文件，
再重命名为最终名称，因此留在该名称上的符号链接会被替换而不是被跟随，权限更宽松的文件会变成 0600。
在 Unix 上，会先像检查套接字所在目录那样检查该目录：归当前用户所有、组或其他人不可写、不是符号链接；
否则不写入任何内容。

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

## 保存密钥：`secretsource store` {#store}

不必手工创建条目。`secretsource store REF [--group G] [--login L] [--replace]
[--generate N]` 为 `keychain:`、`secretservice:SERVICE/ACCOUNT`、
`secretservice:KEY=VALUE` 和 `keepassxc:URL` 写入密钥：

```sh
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c'
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c' --generate 24
printf '%s' "$PIN" | secretsource store keychain:fido/yubikey-5c
```

密钥在关闭回显的情况下输入两次，或在标准输入不是终端时从标准输入读取；绝不从
参数或环境变量获取。`--generate N` 生成 N 个字母和数字，不打印任何机密内容。
已存在的条目会被拒绝，除非加 `--replace`（对 KeePassXC，这会更新按 URL 找到的
那个条目）。`file:` 会被拒绝。

对 `keepassxc:`，它使用浏览器协议的 `set-login`，因此条目始终带有能再次找到它的
URL，重复项按 URL 查找。登录名默认为 URL 的主机（`--login`），分组为
`KeePassXC-Browser Passwords`，除非 `--group` 指定了根下的某个分组；`--title`
会被拒绝，因为 KeePassXC 2.8.0 会忽略它。KeePassXC 会显示它自己的对话框。

## 参考 {#reference}

本页以
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) 的
README 为准。
