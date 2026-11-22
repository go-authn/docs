---
title: "harden：两个共用的安全原语"
linkTitle: "harden"
weight: 36
description: "go-authn/harden 收录了 go-authn 各个仓库曾各自复制的安全原语：仅限 https 或环回的重定向规则、原子写入的私有文件，以及带有 core dump 防护的内存锁定。"
tags: [库, harden, 安全]
---

**go-authn 的每个仓库都复制了什么？** 两条小规则，现在合并在一个除标准库外没有任何依赖的模块中。

```sh
go get github.com/go-authn/harden@v0.3.0
```

## `redirect` {#redirect}

在令牌、密钥集或已签名的断言经过一条链接之前应用的规则：**URL 是 https，或者指向本机。**

```go
import "github.com/go-authn/harden/redirect"

client := &http.Client{Timeout: 30 * time.Second, CheckRedirect: redirect.CheckRedirect}

if err := redirect.HTTPSOrLoopback(issuer); err != nil { ... }
```

| 函数 | |
|---|---|
| `CheckRedirect(req, via) error` | `http.Client` 的策略：10 次重定向后停止，并拒绝既非 https 也非环回的目标（它正是为另一主机上从 https 到 http 的情形而存在）。可在它之后串接你自己的策略 |
| `HTTPSOrLoopback(rawURL) error` | 对 `https://host.example/...`，或主机为环回的 `http://` 返回 nil。拒绝没有主机、其他方案以及明文。错误信息给出方案和主机，绝不给出完整 URL |
| `Loopback(host) bool` | `host` 即 `url.URL.Hostname()` 返回的形式 |

`Loopback` 接受环回的 IP 字面量（127.0.0.0/8、`::1`、IPv4 映射的 `::ffff:127.0.0.1`），
以及 `localhost` 或 `.localhost` 之下的任何名称（RFC 6761 第 6.3 节），不区分大小写，
末尾带不带点均可。它从不做前缀匹配，因此 `127.evil.example` 被拒绝，`0x7f.1`、`127.1`、`2130706433`、
IPv6 区域标识和带方括号的 `[::1]` 同样如此（方括号是 URL 语法，不属于主机）。

`Loopback` 和 `HTTPSOrLoopback` 对照对 RFC 的第二种解读做了模糊测试；语料已提交。

[oidc]({{< relref "/libraries/oidc.md" >}})（v0.8.1）、
[saml]({{< relref "/libraries/saml.md" >}})（v0.7.3）、
[wireguard]({{< relref "/libraries/wireguard.md" >}})、rp（v0.5.1）和 awscred
（v0.3.1）应用的就是它。

## `privfile` {#privfile}

```go
import "github.com/go-authn/harden/privfile"

err := privfile.Write(path, ticket)
```

`Write` 以 0600 权限把数据放到 `path`：在同一目录中创建临时文件，`fsync`，然后 `rename`。因此：

- 读取者看到的是旧文件或新文件，绝不会是半个文件；
- 留在 `path` 上的符号链接会被**替换而不是被跟随**（它所指向的内容不受影响），
  权限更宽松的文件不会保留其权限；
- 在 Unix 上，符号链接目录、属于他人的目录或组或其他用户可写的目录，在写入任何内容之前就会被拒绝。

它不创建目录。在 Windows 上没有可读取的权限位；自 v0.2.0 起，文件创建时带有受保护的访问列表，
其中只有当前账户一条，由 `CreateFile` 设置（即 kinit v0.3.2 的列表），因此绝不继承文件夹的条目。
该模块依赖 `golang.org/x/sys`，仅 Windows 构建使用。

写入 kinit 的 `--cred-file`（v0.3.3）、wireguard 的 `FloorFile`（v0.2.1）、
`authn-revokd` 的状态文件（revocation v0.7.2）以及
[secretsource]({{< relref "/libraries/secretsource.md" >}}) 的 KeePassXC 关联文件（v0.8.1）的，
就是它。

## 下限 {#floors}

go-authn/wireguard 和 go-authn/revocation 都会跨重启保留一个排序下限，但它们并不共用下限：
wireguard 在自己的一个小文件中只保存裸的版本号和签发时间，revocation 保存整份已签名的列表，
并通过验证它来重新计算下限。只有文件写入是共同的，那就是 `privfile`。

## `memlock` {#memlock}

自 v0.3.0 起（自 theca 迁入）：让密钥材料远离交换区、core 文件和调试器。

```go
import "github.com/go-authn/harden/memlock"

region, err := memlock.Lock(unsafe.Pointer(&key[0]), uintptr(len(key)))
if err != nil { ... } // 被拒绝：报告出来，或者停下
defer region.Release()
```

| 函数 | |
|---|---|
| `Lock(p, n) (*Region, error)` | 用 `mlock`（Linux、macOS、各 BSD）或 `VirtualLock`（Windows）锁定该范围的页。**拒绝就是错误**：不会有任何东西保持锁定，由调用方决定。两个区域共享的页，在两者都释放之前一直保持锁定 |
| `(*Locker).LockBestEffort(p, n, report)` | 相同，但每次拒绝都交给 `report`，其余仍照样锁定。名字已经说明：只用于不加锁运行也可接受的场合 |
| `(*Region).Release()` | 解锁；对 nil 和重复调用都是安全的 |
| `DisableDumps() error` | 把 `RLIMIT_CORE` 设为 0，在 Linux 上还把 `PR_SET_DUMPABLE` 设为 0；仅在 macOS 上还调用 `PT_DENY_ATTACH` |

其他任何平台都会得到 `*UnsupportedError`（与 `errors.ErrUnsupported` 匹配），
绝不会悄悄成功。

**它保证**：该范围的页从 `Lock` 到 `Release` 一直锁定在内存中，否则你会得到错误。
**它不保证**：不存在副本。Go 的垃圾回收器可能在堆对象被锁定之前复制它；
因此应锁定不会移动的内存，并把秘密只放在一处。系统限制依然适用
（`RLIMIT_MEMLOCK`；在 Windows 上是工作集大小）。Windows 没有
`PR_SET_DUMPABLE` 或 `PT_DENY_ATTACH` 的对应物：同一用户的调试器或管理员可以读取该进程。

## 参考 {#reference}

[github.com/go-authn/harden](https://github.com/go-authn/harden) 的 README
是本页的权威来源。BSD 3-Clause。
