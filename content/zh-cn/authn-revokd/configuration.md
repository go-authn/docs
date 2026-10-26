---
title: "配置"
linkTitle: "配置"
weight: 20
description: "authn-revokd 的 revokd.hcl：列表从哪里来、必须由谁签名、写入哪些文件，以及镜像。"
tags: [authn-revokd, 配置]
---

一个文件，默认为 `/etc/authn-revokd/revokd.hcl`（`-config` 可指定另一个）。
它在启动时读取一次。

```hcl
state_dir = "/var/lib/authn-revokd/state"   # the verified copies: what orders the next list
refresh   = "1m"

source "univ-a-ssh" {
  url    = "https://login.univ-a.example/ssh/krl"    # and .../ssh/krl.sig beside it
  ssh_ca = "/etc/authn-revokd/ca/univ-a-ssh.pub"     # what the list must be signed by
}
source "univ-b-ssh" {
  url    = "http://mirror.cluster.local:8080/univ-b-ssh"   # a mirror: plain http is fine
  ssh_ca = "/etc/authn-revokd/ca/univ-b-ssh.pub"
}
source "univ-a-x509" {
  url     = "https://login.univ-a.example/x509/crl"
  x509_ca = "/etc/authn-revokd/ca/univ-a-x509.pem"
}

output "sshd" {                              # sshd_config: RevokedKeys /var/lib/authn-revokd/sshd.krl
  path    = "/var/lib/authn-revokd/sshd.krl"
  sources = ["univ-a-ssh", "univ-b-ssh"]     # merged into one file
}
output "tls" {                               # nginx: ssl_crl /var/lib/authn-revokd/univ-a.crl
  path    = "/var/lib/authn-revokd/univ-a.crl"
  sources = ["univ-a-x509"]
  format  = "pem"
}

# listen = "127.0.0.1:8080"                  # serve the verified lists: a mirror
```

## 各个键 {#the-keys}

| 键 | 默认值 | |
|---|---|---|
| `state_dir` | | 必需，绝对路径；缺失时以 `0700` 创建 |
| `refresh` | `1m` | 每个来源被获取的频率，一秒或更长；每次等待会在前后十分之一的范围内浮动，使整批机器不会保持同步 |
| `listen` | | `host:port`：提供已验证的列表，即镜像；与 `-once` 并用时被忽略 |

**`source "<name>"`**：一个列表。名称由字母、数字、`.`、`_` 和
`-` 组成，不以点开头，至多 64 个字符：它命名状态目录中的一个文件
以及镜像的一个路径。

| 键 | |
|---|---|
| `url` | `https://`、`http://` 或 `file://`；KRL 的签名从同一 URL 加上 `.sig` 获取 |
| `ssh_ca` | SSH CA 的公钥，一行 `authorized_keys`：即 KRL 来源。这里不接受证书 |
| `x509_ca` | CA 的 PEM 证书：即 CRL 来源 |
| `max_age` | 除其自身的过期时间之外，还拒绝签发时间早于此值的列表；在为 CRL 输出提供数据的来源上会被拒绝 |
| `revoke_keys` | 允许此来源的列表在与其他来源共用的输出中吊销**普通密钥**；仅限 KRL 来源 |

**`output "<name>"`**：服务器读取的一个文件。

| 键 | |
|---|---|
| `path` | 绝对路径；写在它自己旁边，然后重命名覆盖 |
| `sources` | KRL 来源，合并为一个文件；或者恰好一个 CRL 来源 |
| `format` | `der`（默认）或 `pem`；仅限 CRL 输出 |
| `on_change` | 一个命令及其参数，在文件改变之后运行，并在每次同步时再次运行，直到成功为止 |

## 多个 CA 共用一个 KRL {#one-krl-for-several-cas}

在 OpenSSH 10.3 之前，`RevokedKeys` 只接受一个文件，因此一个输出的各个 KRL 来源会被合并，**每个列表对其自己的 CA 保持完整效力，
而对其他 CA 没有任何效力**：

- **保留：** 它的序列号和 key ID，它不指名 CA 的各节（范围限定于它
  自己的 CA），以及它自己的 CA 密钥，后者吊销它的所有证书。
- **排除并记录日志：** 另一个 CA 的节，以及另一个 CA 的密钥。
- 当输出有多个来源时，**普通用户密钥**会被排除，
  除非该来源有 `revoke_keys = true`。KRL 无法把密钥限定在某一个
  CA：sshd 会拿证书自己的密钥对照该文件检查，无论是谁签发的，
  因此某个 CA 指名的密钥会使其持有者在该文件的每个 CA 之下都被锁在门外。
  只有一个来源的输出会保留它们。

每个列表首先单独合并。无法合并的列表**只对其自己的 CA**
故障即拒绝；合并后的文件随其当前输入中最早到期的一个而到期，
因此检查过期时间的读取方会看到 authn-revokd 停止了。

## 镜像 {#the-mirror}

有 `listen` 时，authn-revokd 提供它所持有的内容，从内存中提供，绝不从
可能正写到一半的文件中提供：

| | |
|---|---|
| `GET /<source>` | 列表，带有 `ETag`；`If-None-Match` 答复 `304` |
| `GET /<source>.sig` | KRL 的签名；对另一个 ETag 使用 `If-Match` 答复 `412` |
| `GET /healthz` | `200 ok`，或 `503` 并指名每个没有当前列表的来源和每个失败的输出 |

```
$ curl -s http://127.0.0.1:28474/healthz
ok
$ curl -s -D - -o /dev/null http://127.0.0.1:28474/bridge-ssh
HTTP/1.1 200 OK
Cache-Control: max-age=30
Content-Type: application/octet-stream
Etag: "dfd84d8513eb48d07ed72f2110316858"
Date: Mon, 26 Oct 2026 11:27:10 GMT
Content-Length: 130

$ curl -s -o /dev/null -w "%{http_code}\n" -H 'If-Match: "stale"' http://127.0.0.1:28474/bridge-ssh.sig
412
```

CRL 来源没有 `.sig`（`404`）。镜像可以串联：镜像的来源可以是
另一个镜像，因为每个列表都自行验证。缓慢的上游绝不会
阻塞镜像的应答。

## 启动时拒绝什么 {#what-is-refused-at-start}

以下每一项都会在获取任何内容之前以 `2` 退出：

```
authn-revokd: v/relative-state.hcl: state_dir "state": an absolute path
authn-revokd: v/refresh.hcl: refresh "500ms": a duration of a second or more
authn-revokd: v/both-ca.hcl: source "bridge-ssh": ssh_ca and x509_ca together: one source is one list
authn-revokd: v/sig-name.hcl: source "bridge-ssh.sig": a name that ends in .sig, or healthz, is a path the mirror already serves
authn-revokd: v/mixed.hcl: output "sshd" mixes KRL and CRL sources
authn-revokd: v/krl-format.hcl: output "sshd": format is for CRL outputs; a KRL is what sshd reads
authn-revokd: v/revoke-keys-crl.hcl: source "bridge-x509": revoke_keys is for a KRL source (ssh_ca): a CRL revokes its own CA's certificates only
```

不存在的配置也是如此：

```
$ authn-revokd -config nowhere.hcl -once
authn-revokd: nowhere.hcl: no such file or directory
```

在 v0.6.2 之前，这是 HCL 解析器的信息：
`nowhere.hcl: <nil>: Failed to read file; The configuration file "nowhere.hcl" could not be read.`

CRL 输出也只接受一个来源（TLS 服务器对每个签发方读取一个 CRL），
并且带有 `max_age` 的 CRL 来源会被拒绝，因为没有任何机制能够强制执行它：

```
authn-revokd: v/crl-maxage.hcl: output "tls": source "bridge-x509" has a max_age, which a CRL output cannot enforce: the TLS server judges a CRL by its nextUpdate alone. Remove max_age, or ask the CA for a closer nextUpdate
```

加载了 CRL 的 TLS 服务器会把它保留在内存中直到其 `nextUpdate`，
无论 authn-revokd 写出什么。

**状态目录**受 sshd 的 StrictModes 规则约束。能够替换或删除其文件的人
决定下一个是哪个列表，而被清空的状态会让重放的较旧列表进入。因此它不得是符号链接、不得
对组或其他用户可写，也不得由 authn-revokd 的用户或 root 之外的任何人
拥有。这些情况以 `1` 退出：

```
authn-revokd: state_dir /tmp/authn/revokd/state-wide is writable by its group or by others (mode -rwxrwxrwx): whoever can write there decides which list comes next
authn-revokd: state_dir /tmp/authn/revokd/state-link is a symbolic link (L---------): whoever owns it decides where the state is; name the directory itself
```
