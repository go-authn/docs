---
title: "运行：信号、重启，以及它输出什么"
linkTitle: "运维"
weight: 80
description: "authnd 只读取一次什么、为什么 SIGHUP 不会重新加载、它如何停止、它向输出写入什么，以及如何判断它已在运行。"
tags: [authnd, 运维, 信号, systemd]
---

## 一切只读取一次 {#it-reads-everything-once}

配置文件和 keytab 在**启动时**读取。
它们没有重新加载，打包提供的单元也没有 `ExecReload=`。更改其中任何一项之后：

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

TLS 证书自 v0.15.0 起是例外：authnd 会再次查看 `cert_file` 和 `key_file`，所以续期无需重启。
参见[续期证书]({{< relref "/authnd/tls.md#renewal" >}})。

除来源（见下文）外，运行期间唯一会生效的是
[人员通过 authnd 更改的密码]({{< relref "/authnd/passwords.md" >}})，
它会重新读取 `user` 块，且仅此而已。

来源是“只读取一次”的例外。人员和组会在每个 `refresh`（默认 60 秒；`refresh = "0"`
表示关闭）重新读入一份在服务路径之外构建的新快照，并以原子方式替换，因此被移除的人员或
组成员会在一个周期内消失，无需重启。（v0.13.4 只读取一次，修改组需要重启。）刷新失败时
会保留最近一份良好的数据，且每一轮连续失败只记录一次日志，并点名来源。在撤销时效很重要的
场合，请设置 `max_age`（例如 `"10m"`）：一旦数据比它更旧，搜索、人员的 bind 和密码修改
会应答 `unavailable`（52），而不是返回过期数据。启动时无法读取的来源，例如无法执行的组查询，
或多个数据库中有一个宕机，会拒绝启动和 `check`，并指明来源和组。对于一条 LDAP 消息
装不下的条目（约 3 MiB，一个 10 MB 的属性值就足以达到），不会发布，并且与未通过模式
校验的条目一样，会在启动时以及由 `check` 说明。

## 信号 {#signals}

| 信号 | 发生什么 |
|---|---|
| `SIGTERM`、`SIGINT` | 它输出 `stopping`，关闭监听器**以及每个已建立的连接**，停止域，关闭各来源，并在服务器真正结束后以 0 退出 |
| `SIGHUP` | 它被捕获并记录，而 authnd **保持运行**。它会立即重新读取 TLS 证书（v0.15.0）；配置和 keytab 不会重新加载 |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 1 person from the configuration file
hangup: authnd does not reload its configuration or keytab; restart it to apply those (the TLS certificate is read again)
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

这是 v0.15.0 二进制文件的一次运行：一个 `kill -HUP`，两次更改密码的尝试（第一次
被拒绝，第二次被接受），然后一个 `kill -TERM`。
在 `SIGHUP` 之后进程仍然存在。

`SIGHUP` 过去会**终止** authnd——这是 Go 对无人处理的信号的默认行为——
而 systemd 把由 `SIGHUP` 导致的死亡视为正常退出，因此
`Restart=on-failure` 不会再次启动它：一次 `kill -HUP` 或一次 logrotate 的
`postrotate` 就会让目录永久停机。现在它被捕获，使这个
习惯不再有害，而输出的那一行说明了应当怎么做。

关闭已建立的连接，而不只是监听器，是有意为之：
停止接受连接却让已打开的连接继续应答的服务器，
看起来停止了，实际上并没有，这就是重启没有生效的情形。

## 它写出什么 {#what-it-writes}

一切都输出到标准输出，在 systemd 下就是日志
（`journalctl -u authnd`）：

- 启动时，它在哪里监听、为谁服务——`ldap on …`、`ldaps on …`
  或 `ldap+starttls on …`，有 `kerberos` 块时再加上 `realm EXAMPLE.ORG on … (udp and tcp)`；
- `mfa` 块之下每次被拒绝的绑定、每个被拒绝的令牌、每次
  被拒绝或完成的密码更改，**连同原因**——客户端
  永远得不到这些原因；参见[第二因素]({{< relref "/authnd/mfa.md#what-the-binds-look-like" >}})
  和[令牌]({{< relref "/authnd/tokens.md#what-the-binds-look-like" >}})；
- KDC 拒绝的每个请求，以 `kerberos:` 为前缀，并带有 Kerberos 错误
  代码；参见[域]({{< relref "/authnd/kerberos.md#kinit-against-it" >}})；
- LDAP 库自己的日志，为 `slog` 文本形式，级别为 info。

没有 `mfa` 块时，简单绑定上单纯的错误密码会得到
`invalidCredentials` 的答复，authnd 自己不记录日志。

## 限制与期限 {#limits}

自 v0.15.0 起，authnd 限定了客户端、缓慢的来源或洪流能让它占用的资源。四个可选的键，位于配置的顶层：

| 键 | 默认值 | 含义 |
|---|---|---|
| `max_connections` | `4096`（以前不限） | 同时打开的连接数上限；`0` 表示不限 |
| `max_connections_per_ip` | 无 | 来自同一地址的上限；不得超过 `max_connections` |
| `operation_timeout` | `30s`（以前无） | 一次 LDAP 操作最多可以花多长时间；`"0"` 表示无，否则至少为 `100ms` |
| `startup_timeout` | `60s` | 打开并首次读取所有来源最多可以花多长时间；`"0"` 表示无 |

超出上限的连接会在断开通知（notice of disconnection）中收到 `busy`（51）并被关闭，绝不排队（RFC 4511 4.4.1）。
在 `operation_timeout` 时仍在运行的操作会收到 `timeLimitExceeded`（3），**即使它的处理程序被阻塞且忽略期限**：
迟到的结果会被丢弃。启动时某个来源不响应，authnd 会在 `startup_timeout` 之后拒绝启动，错误会指出阶段和来源。
负数或无法解析的时长会在启动时和 `check` 中被拒绝。设置 `max_connections = 0` 和 `operation_timeout = "0"`
可恢复 v0.14 的行为。

`check` 会打印它将使用的限制，免得有人在不知情的情况下运行默认值：

```
$ authnd check etc2/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org
limits: 200 connections, 20 per address; an operation may take 10s; startup may take no limit

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid

GROUP  MEMBERS  PUBLISHED AS
staff  alice    groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

该配置设置了 `max_connections = 200`、`max_connections_per_ip = 20`、`operation_timeout = "10s"` 和
`startup_timeout = "0"`。没有这四个键时，该行为 `limits: 4096 connections, no limit per address; an operation may
take 30s; startup may take 1m0s`，同一个二进制文件也打印过它。

### 故障不是密码错误 {#outage}

当人员是对另一个目录（`ldap` 来源）验证的，而该目录无法被询问时，即连接被拒绝或重置、它回答 `busy`、`unavailable`
或 `other`、或在 `operation_timeout` 内没有回答，authnd 会回答 LDAP `unavailable`（52），**绝不**回答
`invalidCredentials`（49）。这适用于简单绑定、密码更改中的旧密码，以及 `mfa` 绑定的密码因素。在 v0.15.0 之前，
这会被报告为密码错误，所以目录宕机时，登录表单会告诉用户密码错了。密码错误仍然是 49。原因记录在日志里，
而不是告诉客户端，故障也不计入失败的猜测。

## 无法启动时 {#when-it-does-not-start}

拒绝信息是标准错误上以 `authnd:` 为前缀的一行，退出
状态为 1；在单元下，`Restart=on-failure` 随后每五秒
重试一次，每次日志中都有那一行。`check` 拒绝的一切在这里也同样
被拒绝，而只有服务器才能发现的一件事是它无法监听的
地址——参见
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}})。
LDAP 监听器、证书和域都在输出第一行之前打开，因此无法启动的
服务器只输出那条拒绝信息。这里第二个实例遇到了第一个实例的
Kerberos 端口：

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

`ldap on …` 这一行，以及其后的 `realm … on …`，表示两部分都
在监听。

## 判断它已在运行 {#telling-that-it-is-up}

没有健康检查端点，也没有指标。有的是：

- **进程及其退出状态**——在 systemd 下是 `systemctl is-active
  authnd`。如果 LDAP 监听器或域自行停止，
  整个进程会带着该错误结束，因此存活的进程就是两部分
  都能应答的进程；
- **根 DSE**，它会应答匿名客户端，并说明正在与哪个版本
  通信：

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.13.0
```

在 [StartTLS 监听器]({{< relref "/authnd/tls.md#starttls-which-refuses-until-it-is-asked-for" >}})上，
该查询需要 `-ZZ`。能证明更多——某个来源仍然
在应答——的探测方式，是以专为此用途保留的人员或 reader 身份进行绑定；
有 `users "ldap"` 块时，该绑定会到达此服务之后的目录。

## 什么存放在哪里，以及重启会丢失什么 {#what-lives-where-and-what-a-restart-loses}

| | |
|---|---|
| 配置、密码、DSN、证书、keytab | 配置所指名的文件；不复制任何内容 |
| SQLite 数据库 | 其 DSN 所指之处；在单元下为 `/var/lib/authnd` |
| 第二因素的计数和锁定 | 仅在内存中：**重启会忘记它们**，包括在一百次错误代码之后被锁定的人员 |
| 已使用的一次性代码 | 仅在内存中 |
