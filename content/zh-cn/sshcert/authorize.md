---
title: "sshcert-authorize"
linkTitle: "sshcert-authorize"
weight: 10
description: "sshd 将 sshcert-authorize 作为 AuthorizedPrincipalsCommand 运行时它检查什么、拒绝什么，以及为什么没有域授权的证书同样会被拒绝。"
tags: [sshcert, ssh, sshd, eurohpc]
---

对于每次证书登录，`sshd` 都会询问它：哪些 principal 可以登录该
账户。只有当证书的域授权指明了本主机时，它才回答该账户的 principal；
否则不回答任何内容，`sshd` 便拒绝该证书。它采用 GÉANT 的
`ssh-cert-authorize` 的参数、标志、输出和日志格式，区别在于它拒绝的内容。

## sshd 如何调用它 {#how-sshd-calls-it}

```
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/efp-ssh-ca.pub
AuthorizedPrincipalsCommand /usr/local/bin/sshcert-authorize %u %k
AuthorizedPrincipalsCommandUser nobody
```

```sh
install -o root -g root -m 0755 sshcert-authorize /usr/local/bin/
echo login.example.org > /etc/ssh/cert-allowed-domain.conf
```

此外，对于每个本地账户，可以登录该账户的 principal 每行一个，
写在 `/etc/ssh/auth_principals/<account>` 中。sshd 只会运行位于
归 root 所有且他人不可写的路径中的该命令。

`%u` 是要登录的账户。`%k` 是证书，base64 编码；完整的
`ssh-...-cert-v01@openssh.com BASE64` 行也可读取，而当该参数
缺省时，证书从标准输入读取。若给出第三个参数（sshd 的 `%t`），
它必须是该证书的类型，否则证书被拒绝。

| 退出码 | 输出 | sshd |
|---|---|---|
| `0` | 账户的 principal，每行一个 | 若证书的某个 principal 在其中，则放行该证书 |
| `1` | 无 | 拒绝 |
| `2` | 无 | 拒绝：参数有误 |

{{< callout type="info" >}}
**它不检查签名、CA 或有效期**

该命令中没有任何内容验证证书的签名或其
有效期：这由通过 `TrustedUserCAKeys` 信任 CA 的 sshd 完成。
该命令只判定一个问题：这张证书是否
面向本主机和该账户。
{{< /callout >}}

## 它拒绝什么 {#what-it-refuses}

按检查顺序：

1. 为空、为 `.`、为 `..`，或包含 `/`、`\` 或 NUL 的账户名；
2. 没有配置域的主机，或不是有效主机名的主机；
3. 无法解析的证书、普通密钥，或主机证书；
4. 与证书类型不符的 `%t`；
5. 使用 `--krl` 时，列表所吊销的证书，或在列表无法读取或已过期时的**所有**证书；
6. 存在但格式错误的域授权，**无论使用什么标志**；
7. **完全没有域授权**，除非使用 `--allow-no-grant`；
8. 其所有模式都不匹配主机任何名称的授权；
9. 没有 principal 文件或文件为空的账户。

主机的名称来自 `--domain`、`--domain-env` 所指名的变量，或
`--domain-file` 的各行（忽略空行和 `#` 注释；多行即多个名称，其中
任何一个都可以匹配）。

下面针对由测试 CA 签名的证书、账户 `alice`（其
principal 文件列出 `a1b2c3@univ-example.example`），在名为
`login.hpc.example.org` 的主机上：

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
a1b2c3@univ-example.example
```

最后一行是 sshd 读取的答复；它之前的几行是日志，此处输出到
标准错误。被授权访问其他主机的证书：

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-other-cert.pub)"
INFO: action=cert_processed serial=1003 key_id="a1b2c3@univ-example.example other host" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
WARNING: action=denied user=alice domain=login.hpc.example.org reason="domain not granted" grant=["*.elsewhere.example.net"] serial=1003 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
```

没有授权的证书：

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
WARNING: action=denied user=alice domain=login.hpc.example.org reason="no domain grant" serial=1002 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
```

没有 principal 文件的账户，以及普通密钥：

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals bob "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
WARNING: action=denied user=bob domain=login.hpc.example.org reason="no principals file for the user" serial=1001 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice.pub)"
WARNING: action=denied user=alice domain=login.hpc.example.org reason="a ssh-ed25519 key, not a certificate"
```

以上每一次都以 `1` 退出，且标准输出上没有任何内容。

## 为什么没有授权的证书会被拒绝 {#why-a-certificate-with-no-grant-is-refused}

GÉANT 的 `ssh-cert-authorize` 会放行没有域授权的证书
（“might be valid for non-domain-based auth”），也会放行授权无法
解析或为空的证书。于是，在 `TrustedUserCAKeys` 中信任**两个** CA 的站点
（联邦的 CA，以及自己用于员工或测试的 CA），
会让来自第二个 CA 的证书在每台主机上通过，可冒用 principal 文件中的
任何 principal，完全没有域检查。只有拒绝没有说明可在何处使用的证书，
域过滤才真正是一个过滤器。

确实想要 GÉANT 行为的站点需要明确声明，而该命令每次
应用该行为时都会记录日志：

```
$ sshcert-authorize --syslog=false --allow-no-grant --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
WARNING: action=no_grant_allowed user=alice domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
a1b2c3@univ-example.example
```

即便如此，存在但格式错误的授权仍会被拒绝。

## `--krl` {#krl}

`RevokedKeys` 是 sshd 自己的检查，在命令运行之前对每个密钥
和证书进行，它也会吊销 CA 密钥；应优先使用它。`--krl FILE` 在命令内部检查
OpenSSH KRL，并补充 sshd 不做的事：列表一旦过期（其
`expires@go-authn.github.io` 扩展，sshd 会忽略它），它就拒绝
**所有**证书；列表无法读取时同样拒绝所有证书。没有过期时间的列表
则不受过期限制地使用。

三次运行：使用 [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})
写出的 KRL，先是当前有效的列表，然后是颁发者的列表[过期]({{< relref "/authn-revokd/lapse.md" >}})时
它写出的故障即拒绝列表；最后是
`--krl` 指名一个不存在的文件：

```
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
a1b2c3@univ-example.example
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
WARNING: action=denied user=alice domain=login.hpc.example.org reason="certificate revoked" serial=1001 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
$ sshcert-authorize --syslog=false --krl missing.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
WARNING: action=denied user=alice domain=login.hpc.example.org reason="KRL unreadable: open missing.krl: no such file or directory" serial=1001 ca_fingerprint=SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
```

第二次运行被拒绝，是因为故障即拒绝的列表吊销了该
证书的 **CA 密钥**：检查涵盖证书自身的密钥、其序列号
和密钥 ID，以及签发它的密钥。第三次被拒绝，是因为列表
无法读取：没有列表不会被当作没有任何吊销。

## 标志 {#flags}

```
$ sshcert-authorize -help
usage: sshcert-authorize [flags] USER [CERTIFICATE [KEYTYPE]]

An sshd AuthorizedPrincipalsCommand (%u %k) that refuses a certificate whose
ssh-domain-grant@core.aai.geant.org extension does not grant this host, or that has none.

  -allow-no-grant
    	let in a certificate with no domain grant (GÉANT's behaviour); a malformed grant is still refused
  -debug
    	log details
  -domain string
    	the host's domain (overrides --domain-env and --domain-file)
  -domain-env string
    	environment variable holding the host's domain
  -domain-file string
    	file holding the host's domain, one name per line (default "/etc/ssh/cert-allowed-domain.conf")
  -extension string
    	name of the domain-grant extension (default "ssh-domain-grant@core.aai.geant.org")
  -krl string
    	refuse certificates this OpenSSH KRL revokes, and every certificate once it has expired or cannot be read
  -principals-dir string
    	directory of principals files, one per user (default "/etc/ssh/auth_principals")
  -syslog
    	log to syslog, facility AUTH (--syslog=false: to stderr) (default true)
  -version
    	print the version and exit
```

**日志**为 `key=value` 行（`action=cert_processed`、`action=denied`、
`action=authorized`，带有 `serial` 和 `ca_fingerprint`），默认输出到 syslog，设施
AUTH。sshd 会丢弃该命令的标准错误，因此在
生产环境中请保持 syslog 开启；`--debug` 还会将所有内容写到标准错误。来自
客户端的值，例如账户名，若包含
空格、`=`、引号或控制字符，则会被加引号，因此它无法伪造日志字段。

**`-version`** 输出模块版本，对发布的二进制文件和
通过 `go install` 构建的文件都是如此：

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.7
$ sshcert-authorize -version
sshcert-authorize v0.1.7
```

在 v0.1.5 之前，通过 `go install` 得到的二进制文件输出 `sshcert-authorize dev`。
