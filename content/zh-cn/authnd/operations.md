---
title: "运行：信号、重启，以及它输出什么"
linkTitle: "运维"
weight: 80
description: "authnd 只读取一次什么、为什么 SIGHUP 不会重新加载、它如何停止、它向输出写入什么，以及如何判断它已在运行。"
tags: [authnd, 运维, 信号, systemd]
---

## 一切只读取一次 {#it-reads-everything-once}

配置文件、其背后的每个来源、TLS 证书和
keytab 都在**启动时**读取。没有重新加载，打包提供的单元
也没有 `ExecReload=`。更改其中任何一项之后：

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

运行期间唯一会生效的是
[人员通过 authnd 更改的密码]({{< relref "/authnd/passwords.md" >}})，
它会重新读取 `user` 块，且仅此而已。

## 信号 {#signals}

| 信号 | 发生什么 |
|---|---|
| `SIGTERM`、`SIGINT` | 它输出 `stopping`，关闭监听器**以及每个已建立的连接**，停止域，关闭各来源，并在服务器真正结束后以 0 退出 |
| `SIGHUP` | 它被捕获并记录，而 authnd **保持运行**，不重新加载任何内容 |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
hangup: authnd does not reload; restart it to apply a changed configuration, certificate or keytab
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

这是一次运行：一个 `kill -HUP`，两次更改密码的尝试（第一次
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
vendorVersion: v0.12.4
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
