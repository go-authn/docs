---
title: "設定"
linkTitle: "設定"
weight: 20
description: "authn-revokd の revokd.hcl: リストの取得元、署名されていなければならない対象、書き込み先のファイル、そしてミラー。"
tags: [authn-revokd, 設定]
---

一つのファイルで、既定は `/etc/authn-revokd/revokd.hcl` です (`-config` で別のものを指定)。
起動時に一度だけ読み込まれます。

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

## キー {#the-keys}

| キー | 既定値 | |
|---|---|---|
| `state_dir` | | 必須、絶対パス。なければ `0700` で作成される |
| `refresh` | `1m` | すべてのソースを取得する頻度。一秒以上。各待機は前後一割ずつ変動し、複数台が足並みをそろえ続けないようにする |
| `listen` | | `host:port`: 検証済みのリストを提供する、ミラー。`-once` では無視される |

**`source "<name>"`**: 一つのリスト。名前は英字、数字、`.`、`_`、`-` で、ドットで始まらず、
最大 64 文字です。状態ディレクトリ内のファイルと、ミラーのパスの名前になります。

| キー | |
|---|---|
| `url` | `https://`、`http://`、`file://`。KRL の署名は、同じ URL に `.sig` を付けて取得する |
| `ssh_ca` | SSH CA の公開鍵、`authorized_keys` の一行: KRL ソース。ここでの証明書は拒否される |
| `x509_ca` | CA の PEM 証明書: CRL ソース |
| `max_age` | 自身の有効期限に加えて、これより前に発行されたリストも拒否する。CRL 出力に供給するソースでは拒否される |
| `revoke_keys` | 他のソースと共有する出力で、このソースのリストが**単なる鍵**を失効させることを許す。KRL ソースのみ |

**`output "<name>"`**: サーバーが読む一つのファイル。

| キー | |
|---|---|
| `path` | 絶対パス。同じ場所の隣に書き込まれ、リネームで上書きされる |
| `sources` | 一つのファイルにマージされる KRL ソース。または、ちょうど一つの CRL ソース |
| `format` | `der` (既定) または `pem`。CRL 出力のみ |
| `on_change` | ファイルが変わった後に実行されるコマンドとその引数。成功するまで、同期のたびに再度実行される |

## 複数の CA に一つの KRL {#one-krl-for-several-cas}

OpenSSH 10.3 より前は `RevokedKeys` が単一のファイルしか受け付けないので、出力の KRL ソースは
マージされ、**各リストは自身の CA に対しては完全な効果を保ち、他の CA に対しては何の効果も
持ちません**。

- **保持されるもの:** そのシリアルとキー ID、CA を指名しないセクション (自身の CA にスコープ
  される)、そして自身の CA 鍵。これはその CA のすべての証明書を失効させる。
- **除外され、ログに記録されるもの:** 他の CA のセクションと、他の CA の鍵。
- **単なるユーザー鍵**は、出力に複数のソースがある場合は除外されます。ソースに
  `revoke_keys = true` がある場合を除きます。KRL は鍵を一つの CA にスコープできません。sshd は
  証明書自身の鍵を、誰が署名したかにかかわらずファイルと照合するので、ある CA が名指しした鍵は、
  ファイルのどの CA の下でも、その持ち主を締め出してしまいます。ソースが一つの出力では保持されます。

各リストは、まず単独でマージされます。マージできないものは**自身の CA についてのみ**フェイル
クローズします。マージされたファイルは、現在の入力のうち最も早いものとともに期限切れになるので、
期限を確認する読み手には authn-revokd が停止したことが分かります。

## ミラー {#the-mirror}

`listen` があると、authn-revokd は保持しているものを、メモリから、書き込みの途中かもしれない
ファイルからではなく、提供します。

| | |
|---|---|
| `GET /<source>` | `ETag` 付きのリスト。`If-None-Match` には `304` を返す |
| `GET /<source>.sig` | KRL の署名。別の ETag の `If-Match` には `412` を返す |
| `GET /healthz` | `200 ok`、または現在のリストがない各ソースと失敗した各出力を挙げる `503` |

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

CRL ソースには `.sig` がありません (`404`)。ミラーは連鎖できます。すべてのリストが単独で
検証されるので、ミラーのソースを別のミラーにできます。遅い上流がミラーの応答を妨げることは
ありません。

## 起動時に拒否されるもの {#what-is-refused-at-start}

以下はいずれも、何かが取得される前に、`2` で終了します。

```
authn-revokd: v/relative-state.hcl: state_dir "state": an absolute path
authn-revokd: v/refresh.hcl: refresh "500ms": a duration of a second or more
authn-revokd: v/both-ca.hcl: source "bridge-ssh": ssh_ca and x509_ca together: one source is one list
authn-revokd: v/sig-name.hcl: source "bridge-ssh.sig": a name that ends in .sig, or healthz, is a path the mirror already serves
authn-revokd: v/mixed.hcl: output "sshd" mixes KRL and CRL sources
authn-revokd: v/krl-format.hcl: output "sshd": format is for CRL outputs; a KRL is what sshd reads
authn-revokd: v/revoke-keys-crl.hcl: source "bridge-x509": revoke_keys is for a KRL source (ssh_ca): a CRL revokes its own CA's certificates only
```

存在しない設定も同様です。

```
$ authn-revokd -config nowhere.hcl -once
authn-revokd: nowhere.hcl: no such file or directory
```

v0.6.2 より前は、HCL パーサーのメッセージでした。
`nowhere.hcl: <nil>: Failed to read file; The configuration file "nowhere.hcl" could not be read.`

CRL 出力も一つのソースしか受け付けず (TLS サーバーは発行者ごとに一つの CRL を読む)、
`max_age` のある CRL ソースは、強制できるものがないので拒否されます。

```
authn-revokd: v/crl-maxage.hcl: output "tls": source "bridge-x509" has a max_age, which a CRL output cannot enforce: the TLS server judges a CRL by its nextUpdate alone. Remove max_age, or ask the CA for a closer nextUpdate
```

CRL を読み込んだ TLS サーバーは、authn-revokd が何を書き込もうと、`nextUpdate` までそれを
メモリに保持します。

**状態ディレクトリ**は、sshd の StrictModes ルールに従います。そのファイルを置き換えたり
削除したりできる者が、次にどのリストが来るかを決め、空にされた状態は、再生された古いリストを
招き入れます。そのためシンボリックリンクであってはならず、グループや他者に書き込み可能で
あってはならず、authn-revokd のユーザーか root 以外が所有していてはなりません。これらは `1` で
終了します。

```
authn-revokd: state_dir /tmp/authn/revokd/state-wide is writable by its group or by others (mode -rwxrwxrwx): whoever can write there decides which list comes next
authn-revokd: state_dir /tmp/authn/revokd/state-link is a symbolic link (L---------): whoever owns it decides where the state is; name the directory itself
```
