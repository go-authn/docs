---
title: "sshcert-authorize"
linkTitle: "sshcert-authorize"
weight: 10
description: "sshd が AuthorizedPrincipalsCommand として実行したとき sshcert-authorize が確認するもの、拒否するもの、そしてドメイン許可のない証明書も拒否する理由。"
tags: [sshcert, ssh, sshd, eurohpc]
---

`sshd` は証明書ログインのたびに、どのプリンシパルがそのアカウントにログインしてよいかをこれに
問い合わせます。証明書のドメイン許可がこのホストを指している場合にのみ、アカウントのプリンシパル
を返し、そうでなければ何も返さず、`sshd` は証明書を拒否します。GÉANT の `ssh-cert-authorize` の
引数、フラグ、出力、ログ形式を引き継ぎ、何を拒否するかが異なります。

## sshd からの呼び出し方 {#how-sshd-calls-it}

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

そして各ローカルアカウントについて、そこにログインしてよいプリンシパルを一行に一つずつ
`/etc/ssh/auth_principals/<account>` に書きます。sshd がコマンドを実行するのは、root が所有し、
他の誰にも書き込めないパスからに限られます。

`%u` はログイン先のアカウントです。`%k` は証明書の base64 です。
`ssh-...-cert-v01@openssh.com BASE64` の行全体も読まれ、引数がない場合は証明書が標準入力から
読まれます。三番目の引数がある場合 (sshd の `%t`)、それは証明書の種類でなければならず、そうで
なければ証明書は拒否されます。

| 終了コード | 出力 | sshd |
|---|---|---|
| `0` | アカウントのプリンシパルを一行に一つ | 証明書のプリンシパルのいずれかがそこにあれば通す |
| `1` | なし | 拒否する |
| `2` | なし | 拒否する: 引数が間違っていた |

{{< callout type="info" >}}
**署名、CA、有効期間は確認しない**

コマンドには、証明書の署名や有効期間を検証するものはありません。`TrustedUserCAKeys` で CA を
信頼する sshd がそれを行います。このコマンドが判断するのは、証明書がこのホストとこのアカウント
向けかどうかという一点です。
{{< /callout >}}

## 拒否するもの {#what-it-refuses}

確認する順序で:

1. 空、`.`、`..` のアカウント名、または `/`、`\`、NUL を含むもの
2. ドメインが設定されていないホスト、または有効なホスト名でないもの
3. 解析できない証明書、単なる鍵、またはホスト証明書
4. 証明書の種類ではない `%t`
5. `--krl` がある場合、リストが失効させた証明書、またはリストが読めない、もしくは期限切れの
   ときは**すべての**証明書
6. 存在するが不正な形式のドメイン許可。**フラグにかかわらず**
7. `--allow-no-grant` でない限り、**ドメイン許可がまったくないもの**
8. どのパターンもホストの名前のどれにも一致しない許可
9. プリンシパルファイルがない、または空のアカウント

ホストの名前は、`--domain`、`--domain-env` が名指しする変数、または `--domain-file` の行です
(空行と `#` コメントは無視され、複数の行は複数の名前で、どれが一致してもよい)。

テスト用 CA が署名した、アカウント `alice` 向けの証明書に対して、プリンシパルファイルに
`a1b2c3@univ-example.example` が列挙され、ホスト名が `login.hpc.example.org` の場合:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
```

最後の行が sshd の読む応答で、それより前の行はログで、ここでは標準エラーに出ています。
他のホストに許可された証明書:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-other-cert.pub)"
INFO: action=cert_processed serial=1003 key_id="a1b2c3@univ-example.example other host" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="domain not granted" grant=["*.elsewhere.example.net"] serial=1003 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

許可のない証明書:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="no domain grant" serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

プリンシパルファイルのないアカウントと、単なる鍵:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals bob "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=bob domain=login.hpc.example.org reason="no principals file for the user" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice.pub)"
WARNING: action=denied user=alice domain=login.hpc.example.org reason="a ssh-ed25519 key, not a certificate"
```

これらはいずれも `1` で終了し、標準出力には何も出力しませんでした。

## 許可のない証明書を拒否する理由 {#why-a-certificate-with-no-grant-is-refused}

GÉANT の `ssh-cert-authorize` は、ドメイン許可のない証明書を通します
("might be valid for non-domain-based auth")。解析できない許可や空の許可のものも通します。そうする
と、`TrustedUserCAKeys` で**二つ**の CA (フェデレーションのものと、職員用やテスト用の自サイトの
もの) を信頼するサイトは、二つ目の CA の証明書を、プリンシパルファイルにあるどのプリンシパル
についても、ドメインのチェックなしで、すべてのホストで通してしまいます。使える場所を述べない
証明書が拒否されて初めて、ドメインフィルターはフィルターになります。

GÉANT の動作を本当に望むサイトは、そう宣言し、コマンドはそれを適用するたびにログに記録します。

```
$ sshcert-authorize --syslog=false --allow-no-grant --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=no_grant_allowed user=alice domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
```

その場合でも、存在するが不正な形式の許可は拒否されます。

## `--krl` {#krl}

`RevokedKeys` は sshd 自身のチェックで、コマンドが実行される前に、すべての鍵と証明書に対して
行われ、CA 鍵も失効させます。そちらを優先してください。`--krl FILE` は OpenSSH の KRL を
コマンド内で確認し、sshd が行わないことを加えます。リストの期限が切れた場合
(`expires@go-authn.github.io` 拡張。sshd は無視する) には**すべての**証明書を拒否し、リストが
読めない場合にもすべての証明書を拒否します。有効期限のないリストは、期限なしで使われます。

三回の実行です。[authn-revokd]({{< relref "/authn-revokd/_index.md" >}})が書き込む KRL で、まず
現在のもの、次に発行者のリストが[失効した]({{< relref "/authn-revokd/lapse.md" >}})ときに
書き込まれるフェイルクローズのもの、最後に存在しないファイルを指す `--krl` です。

```
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="certificate revoked" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
$ sshcert-authorize --syslog=false --krl missing.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="KRL unreadable: open missing.krl: no such file or directory" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

二回目の実行が拒否されるのは、フェイルクローズのリストが証明書の **CA 鍵**を失効させているから
です。チェックは、証明書自身の鍵、そのシリアルとキー ID、そしてそれに署名した鍵を対象とします。
三回目が拒否されるのは、リストが読めないからです。リストがないことは、何も失効していないという
意味とは受け取られません。

## フラグ {#flags}

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

**ログ**は `key=value` の行 (`action=cert_processed`、`action=denied`、`action=authorized`。
`serial` と `ca_fingerprint` を伴う) で、既定では syslog のファシリティ AUTH に出力されます。sshd は
コマンドの標準エラーを破棄するので、本番では syslog を有効にしておいてください。`--debug` は
すべてを標準エラーにも書きます。アカウント名のようにクライアント由来の値は、空白、`=`、引用符、
制御文字を含む場合は引用符で囲まれるので、ログのフィールドを偽造することはできません。

**`-version`** は、リリースバイナリでも `go install` でビルドしたものでも同様に、モジュール
バージョンを表示します。

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

v0.1.5 より前は、`go install` のバイナリは `sshcert-authorize dev` と表示していました。
