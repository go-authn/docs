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
go get github.com/go-authn/secretsource@v0.9.0
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
| `systemd-creds:NAME` | (Linux，自 v0.8.0 起)一个 systemd 凭据，按字节原样返回：与 `file:` 不同，不去掉末尾换行。先找 `$CREDENTIALS_DIRECTORY` 中的文件 `NAME`(由 `LoadCredential=`、`LoadCredentialEncrypted=`、`SetCredentialEncrypted=` 放置)；否则在 `/etc`、`/run`、`/usr/lib` 的 `credstore.encrypted` 中找 `NAME` 或 `NAME.cred`，用 `systemd-creds decrypt` 解密。在其他系统上以 `ErrUnavailable` 拒绝 |

**`file:` 不跟随符号链接**（自 v0.9.0 起）。路径最后一个组成部分若是链接，无论是否悬空，都会被拒绝：在 Unix 上以 `O_NOFOLLOW` 打开文件，在 Windows 上以 `FILE_FLAG_OPEN_REPARSE_POINT` 打开，并拒绝任何重解析点（云文件占位符同样被拒绝：请指向普通的本地副本）。在 Unix 上，文件还必须归调用用户所有；root 也不例外。**迁移：** 指向真实文件（`readlink -f PATH`）。路径前面的目录中若有符号链接，仍然可用。

`keepassxc:by-uuid/...` 和 `keepassxc:by-path/...` 会被**拒绝**：当查找命中没有
URL 的条目时，KeePassXC 2.8.0 会崩溃。

**没有任何方案会执行命令**：选项绝不能能够启动进程。没有方案的引用会被拒绝，
而不是被猜成路径（路径要写成 `file:`）。超过 4096 字节的密钥，或管理器或 `file:` 返回的
空密钥，都会被拒绝（`ErrEmpty`）；一次调用随其上下文结束（没有截止时间时为 2 分钟），即使
管理器正在等你解锁。

## systemd 凭据 {#systemd-creds}

语法严格为 `systemd-creds:NAME`：小写的方案名、冒号，然后是传给
`LoadCredential=`、`LoadCredentialEncrypted=` 或 `systemd-creds encrypt --name=`
的凭据名，例如 `systemd-creds:smtp`。`NAME` 是 1 到 255 字节的普通文件名：不含
`/`(因此不是路径)，不是 `.` 或 `..`，不含控制字符，也不带 `.cred` 后缀(后缀属于
文件；`smtp` 会找到 `smtp` 或 `smtp.cred`)。

- `$CREDENTIALS_DIRECTORY` 中的文件以 `O_NOFOLLOW` 打开，必须是属于 root 或调用者的
  普通文件，且"其他人"无任何访问权限(接受组权限位：systemd 会给 `User=` 服务一个带
  ACL 的 root 所有 0440 文件)；目录同样如此。符号链接或过宽的权限会被拒绝。
- 否则直接运行 `systemd-creds decrypt --name=NAME PATH -`：不经 shell、环境为空，
  只从标准输出读取机密，最多 4096 字节，随上下文结束。非 root 的调用者先尝试
  `--user`(systemd 256 或更高版本)。
- 不做裁剪：末尾换行、NUL 字节和非 UTF-8 字节都会保留，因此请用 `printf %s` 封存密码。
- 在 systemd 257(Debian 13)上用 `--with-key=host` 测得；未用 TPM2 密钥测量。解密
  失败会返回 `ErrUnavailable`，并提示凭据可能需要重新封存。
- PCR 绑定：`--tpm2-pcrs=` 默认为空。单独的 `--tpm2-pcrs=7` 可能在固件或 shim 更新、
  或 vTPM 迁移后锁死所有凭据。请优先使用 `--with-key=host+tpm2`、签名的 PCR 策略
  (`--tpm2-public-key`，PCR 11)或 `systemd-pcrlock`，并保留机密的副本以便重新封存。

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
