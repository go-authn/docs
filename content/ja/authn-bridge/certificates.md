---
title: "証明書"
linkTitle: "証明書"
weight: 50
description: "authn-bridge が署名する SSH ユーザー証明書、その EuroHPC Federation Platform プロファイル、そして NFS over TLS 向けに発行する X.509 クライアント証明書。"
tags: [authn-bridge, ssh, x509, eurohpc]
---

ログインした人は、SSH 公開鍵に数時間有効な証明書を発行してもらったり、X.509 クライアント証明書を
発行してもらったりできます。プロバイダーの CA を信頼するサーバーは、そこで編集すべき
アカウントファイルがなくても、その人を通します。すべての証明書は、**渡される前に
`certificates_file` に記録されます**。記録できない証明書は発行されません。失効させることが
できなくなるからです。失効した証明書は
[KRL と CRL]({{< relref "/authn-bridge/revocation.md" >}}) で公開されます。

## SSH 証明書 {#ssh-certificates}

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

ssh_ca {
  key_file = "/var/lib/authn-bridge/ssh-ca"   # authn-bridge keygen --ssh-ca; Ed25519
  validity = "12h"                            # the default; a week at most
}

client "sftp" {
  device           = true
  ssh_certificates = true
}
```

`authn-bridge ssh-cert --issuer https://login.example.org --client sftp` は、コードでログインし、
`~/.ssh/id_ed25519.pub` (または `--key`) を `ssh` スコープのトークンとともに
`/ssh/certificate` に POST し、`ssh` と `sftp` が見つける場所である鍵の隣に
`<key>-cert.pub` を書き込みます。

CA 鍵は Ed25519 でなければなりません。RSA の CA 鍵は、別途指定しない限り SHA-1 で署名しますが、
OpenSSH は 8.8 以降、既定でこれを拒否しています。

**証明書が述べること。**

- **ちょうど一つのプリンシパル**。クライアントのプロファイルが別のクレームを指定しない限り、
  その人の `preferred_username` です。プリンシパルのない証明書は*どの*ユーザーにも有効
  (PROTOCOL.certkeys) なので、ユーザー名のない人には発行されません。カンマ、空白、引用符、
  バックスラッシュ、制御文字を含む名前は拒否されます (`403`)。`sshd` は `principals="a,b"` や
  `AuthorizedPrincipalsFile` のエントリをリストとして読むため、そのような名前は二つになって
  しまいます。
- **キー ID** `<principal> sub=<sub> jti=<token id>`: `sshd` がログに記録するもの。
- 既定では **`permit-*` 拡張はありません**。SFTP には不要で、pty、フォワーディング、rc ファイルを
  許可しない証明書は、ファイルアクセスだけを許可します。
- トークンがグループを運ぶ場合は、`groups@go-authn.org` 拡張に**その人のグループ**を一行に一つ
  入れます。OpenSSH は無視しますが、署名されているので、グループで認可するサーバーはそれを
  信じることができます。
- 五分前 (時計のずれに備えて) から、現在から `validity` 後まで、または IdP のセッションがそれより
  早く終わる場合はそこまで**有効**です。
- **鍵**は Ed25519、ECDSA P-256/384/521、セキュリティキー (`sk-`)、または 2048 ビット以上の
  RSA でなければなりません。証明書は鍵としては拒否されます。

## EuroHPC SSH CA プロファイル {#the-eurohpc-ssh-ca-profile}

EuroHPC Federation Platform の SSH CA (GÉANT / MyAccessID) は、有効期間一時間の Ed25519
証明書を発行します。プリンシパルは一つで、フェデレーション全体でその人を指し、宛先のホストは
GÉANT の `ssh-domain-grant@core.aai.geant.org` 拡張に入ります。クライアントは、その形で証明書を
発行してもらうことができます。すべてのキーはクライアントごとの任意指定で、何も設定しない
クライアントは上記の証明書を受け取ります。

```hcl
client "efp" {
  device              = true
  ssh_certificates    = true
  ssh_principal_claim = "voperson_id"               # the default is preferred_username
  ssh_validity        = "1h"                        # never longer than ssh_ca's, nor the IdP's session
  ssh_extensions      = ["permit-pty"]              # none by default
  ssh_domain_grants   = ["login.hpc.example.org"]   # the hosting entity's hosts
  # ssh_source_address = ["192.0.2.0/24"]           # the source-address critical option
}
```

| キー | |
|---|---|
| `ssh_principal_claim` | `preferred_username`、`sub`、`voperson_id`、`eduperson_principal_name`。後の二つは `eduperson` スコープで公開され、トークンがそれを持っていなければなりません (`authn-bridge ssh-cert --scope eduperson`)。そうでない場合、または IdP がそのような属性を出さなかった場合は、どれかを述べる `403` が返ります |
| `ssh_extensions` | `permit-pty`、`permit-user-rc`、`permit-port-forwarding`、`permit-agent-forwarding`、`permit-X11-forwarding` のうち |
| `ssh_source_address` | アドレスまたは CIDR プレフィックス。正規形で `source-address` に書き込まれる |
| `ssh_validity` | このクライアントについて、`ssh_ca` の `validity` を超えない (同じ値は可) |
| `ssh_domain_grants` | ドメインパターン。[go-authn/sshcert]({{< relref "/sshcert/_index.md" >}}) の `ValidatePattern` で検証され、`EncodeDomainGrant` でエンコードされる |

### プロファイルが拒否するもの {#what-the-profile-refuses}

いずれも起動時に、`authn-bridge check` から:

```
authn-bridge: client "efp": ssh_validity = 24h0m0s: longer than the ssh_ca validity, 12h0m0s
authn-bridge: client "efp": ssh_extensions: "no-touch-required" is not one of permit-X11-forwarding, permit-agent-forwarding, permit-port-forwarding, permit-pty, permit-user-rc
authn-bridge: client "src": ssh_source_address: "192.0.2.1/24" has bits set under its mask: 192.0.2.0/24?
authn-bridge: client "x": ssh_principal_claim, ssh_extensions, ssh_source_address, ssh_validity and ssh_domain_grants shape SSH certificates: they need ssh_certificates = true
```

`no-touch-required` は提供されません。これは、その人**自身の**セキュリティキーのユーザー在席
確認を免除するもので、あるクライアントの全員のためにプロバイダーが手放してよいものでは
ありません。

ドメイン許可は、仕様の構文、続いてこのプロバイダー自身のポリシーに照らして検証されます。
小文字であること、ラベルが二つ以上あること、ワイルドカードは登録可能なドメインの下にのみ
置けること、です。最後のワイルドカードの右側に固定されているものは、パブリックサフィックス
(Public Suffix List) であってはなりません。`*.ac.uk` は、その下のすべての機関に許可を
与えてしまうからです。

```
authn-bridge: client "efp": ssh_domain_grants: "*.ac.uk": a wildcard over the public suffix "ac.uk" grants every domain under it
authn-bridge: client "efp": ssh_domain_grants: "Login.hpc.example.org": written in lower case, as hosting entities' domains are compared
authn-bridge: client "efp": ssh_domain_grants: "login.hpc.*": sshcert: invalid domain pattern: pattern "login.hpc.*" has a wildcard in its rightmost label
```

### サイト側から信頼する {#trusting-it-from-a-site}

`GET /ssh/config` は CA 鍵を EFP が自身のものを公開するのと同じ形で公開するので、サイトは
このプロバイダーの URL で EFP の信頼手順に従えます。

```
$ curl -s http://127.0.0.1:28473/ssh/config
{"PublicKey":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNOYvUrAPdRTB+38aml+twPN+2k1shD3l62v8NxrIje"}
```

```sh
curl -s https://login.example.org/ssh/config | jq -r '.PublicKey' > /etc/ssh/bridge-ssh-ca.pub
echo "TrustedUserCAKeys /etc/ssh/bridge-ssh-ca.pub" >> /etc/ssh/sshd_config
```

sshd はドメイン許可を無視します。サイトは `AuthorizedPrincipalsCommand` でそれによって
絞り込みます。[sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}) は、許可がそのホストを
指していない証明書と、許可がまったくない証明書を拒否します。CA は OpenID ディスカバリー
ドキュメントにはありません。SSH CA を指す OpenID Connect メタデータはないからです。

EFP 自身の CA との違いとして残るのは次のとおりです。上記のように
`ssh_principal_claim = "voperson_id"` とすると、プリンシパルは MyAccessID の識別子ではなく、
その人の機関が出した `subject-id` を小文字にしたものです。トークンがグループを運ぶ場合は
グループ拡張があります。そして**KRL があり**、`GET /ssh/krl` がここで無効化された人々の
証明書を列挙します。

## NFS over TLS 向けの X.509 クライアント証明書 {#x509-client-certificates-for-nfs-over-tls}

NFS over TLS (RFC 9289) は、クライアントを証明書で指名できます。

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

x509_ca {
  key_file  = "/var/lib/authn-bridge/nfs-ca/ca.key"   # authn-bridge keygen --x509-ca /var/lib/authn-bridge/nfs-ca
  cert_file = "/var/lib/authn-bridge/nfs-ca/ca.crt"   # what go-fileshare trusts
  validity  = "12h"                                   # the default; a week at most
}

client "nfs" {
  device            = true
  x509_certificates = true
}
```

`authn-bridge nfs-cert --issuer ... --client nfs` は、その人のマシン上で P-256 鍵を作り、
証明書要求を `nfs` スコープのトークンとともに `/x509/cert` に POST し、証明書と鍵を書き込みます。
CA 鍵は P-256 でなければならず、その証明書は証明書と CRL に署名する CA でなければなりません。

**証明書が述べること。** 要求のサブジェクトと拡張は無視されます。証明されるのはトークンの人
であって、本人が求めたものではありません。

- その人、`user@domain` が、UTF8String を保持する**一つの** subjectAltName `otherName`
  `1.3.6.1.4.1.2238.1.1.1` として入ります。FreeBSD の `rpc.tlsservd -u` がそこを読みます。
  `@` のないユーザー名や、三バイト未満のものは拒否されます。
- 各グループは、その隣の URI 名として入ります:
  `tag:go-authn.github.io,2026:group:<the group, percent-encoded>`。
- CN はユーザー名です。64 文字を超えるとサブジェクトは空になり、subjectAltName がクリティカルに
  なります (RFC 5280)。
- クライアント認証のみで、CRL 配布ポイントは `<issuer>/x509/crl` です。
- 五分前から、`validity`、IdP のセッション、CA 自身の証明書のうち、最も早く終わるものまで有効です。
- P-256 または RSA (2048 ビット以上) の鍵と、それで署名された要求。

{{< callout type="warning" >}}
**証明書が指名するのはマシンであり、その利用者ではない**

RFC 9289: サーバーは "cannot utilize the remote TLS peer identity to
authenticate RPC users"。Linux ではクライアント証明書がマウントごとに設定されるので、
そのマウントを使うすべての人が、証明書が指名する人になります。これは一人が使うマシンのためで
あり、`authn-bridge nfs-cert` もそう述べます。
{{< /callout >}}

## 無効化をまたいで開いたままの証明書要求 {#a-certificate-request-held-open-across-a-disabling}

トークンは要求の開始時に検証され、本文はその後、クライアントが送る速さで読まれます。そのため
証明書はまず記録され、その後でトークンと人が再度検証されます。その間に人が無効化されたか
トークンが失効していれば、記録したばかりの証明書は失効され、応答は `401` になります。失効が
証明書を見たか、証明書が失効を見たか、そのどちらかです。
