---
title: "secretsource — 参照からシークレットを取得する"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource は、PIN・パスワード・リカバリーコードを参照 (ファイル、macOS キーチェーン、Secret Service、KeePassXC) から取得し、平文のファイルをディスクに残さずに済ませます。"
tags: [ライブラリ, secretsource, シークレット]
---

**ファイルに置きたくない PIN は、どこから取得するのか。** **参照**はシークレットの
所在を示し、`secretsource.Open` がそれを取得します。参照自体はシークレットを
含まないので、フラグ、スクリプト、シェルの履歴に書いても構いません。

```sh
go get github.com/go-authn/secretsource@v0.12.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| 参照 | 読み取るもの |
|---|---|
| `file:PATH` | 所有者だけが読める通常ファイル (Unix: モード 0600 以下。Windows (v0.7.0 以降): 所有者、SYSTEM、Administrators グループ以外に読み取りや書き込みの権利を与えないアクセスリスト)。末尾の改行 1 つは取り除かれます。空のファイル、または行末だけを含むファイルは `ErrEmpty` で拒否され (v0.6.0 以降)、FIFO は通常ファイルではないとして拒否されます |
| `keychain:SERVICE/ACCOUNT` | macOS キーチェーンの汎用パスワード項目 |
| `secretservice:SERVICE/ACCOUNT` | 属性 `service=SERVICE`、`account=ACCOUNT` を持つ freedesktop Secret Service の項目 (GNOME Keyring、KWallet、KeePassXC の Secret Service 連携) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | それらすべての属性を持つ唯一の Secret Service 項目。複数一致は拒否されます |
| `keepassxc:URL` | **URL フィールド**がその URL である KeePassXC のエントリ (`https://NAME.invalid/...` は、名前解決されることのない良い選択です)。同じ URL のエントリが 2 つあると曖昧として拒否されます |
| `systemd-creds:NAME` | (Linux、v0.8.0 以降) systemd のクレデンシャルをバイト単位でそのまま返します。`file:` と違い、末尾の改行は取り除きません。まず `$CREDENTIALS_DIRECTORY` 内のファイル `NAME` (`LoadCredential=`、`LoadCredentialEncrypted=`、`SetCredentialEncrypted=` が配置)、なければ `/etc`、`/run`、`/usr/lib` の `credstore.encrypted` にある `NAME` または `NAME.cred` を `systemd-creds decrypt` で復号します。他のシステムでは `ErrUnavailable` で拒否されます |

**`file:` はシンボリックリンクをたどりません**（v0.9.0 以降）。パスの最後の要素がリンクであれば、リンク切れかどうかに関わらず拒否されます。Unix ではファイルを `O_NOFOLLOW` で開き、Windows では `FILE_FLAG_OPEN_REPARSE_POINT` で開いて、あらゆるリパースポイントを拒否します（クラウドファイルのプレースホルダーも拒否されるので、通常のローカルコピーを指してください）。Unix ではさらに、ファイルが呼び出したユーザーの所有でなければなりません。root も例外ではありません。**移行:** 実体のファイルを指してください（`readlink -f PATH`）。パスの途中のディレクトリにあるシンボリックリンクは、これまでどおり使えます。

`keepassxc:by-uuid/...` と `keepassxc:by-path/...` は**拒否されます**:
KeePassXC 2.8.0 は、検索が URL のないエントリを見つけるとクラッシュします。

**コマンドを実行するスキームはありません**: フラグがプロセスを起動できては
ならないからです。スキームのない参照は、パスと推測されずに拒否されます
(パスは `file:` で書きます)。4096 バイトを超えるシークレットや、マネージャーから
または `file:` からの空のシークレットは拒否され (`ErrEmpty`)、呼び出しはそのコンテキスト (期限がなければ
2 分) で終わり、マネージャーがロック解除を待っていても同じです。

## systemd クレデンシャル {#systemd-creds}

文法は厳密に `systemd-creds:NAME` です。スキームは小文字、続けてコロン、そして
`LoadCredential=`、`LoadCredentialEncrypted=`、`systemd-creds encrypt --name=`
に渡したクレデンシャル名です。例: `systemd-creds:smtp`。`NAME` は 1 から 255
バイトの単純なファイル名で、`/` を含まず (パスではない)、`.` や `..` ではなく、
制御文字を含まず、`.cred` サフィックスも付けません (サフィックスはファイル側の
ものです。`smtp` は `smtp` または `smtp.cred` を見つけます)。

- `$CREDENTIALS_DIRECTORY` 内のファイルは `O_NOFOLLOW` で開かれ、root または
  呼び出し元が所有し、「その他」にアクセス権のない通常ファイルでなければ
  なりません (グループビットは許容されます。systemd は `User=` のサービスに、
  ACL 付きで root 所有の 0440 ファイルを渡します)。ディレクトリも同様です。
  シンボリックリンクや緩すぎるモードは拒否されます。
- そうでなければ `systemd-creds decrypt --name=NAME PATH -` を直接実行します。
  シェルなし、空の環境、秘密は標準出力のみから読み、最大 4096 バイト、
  コンテキストで終了します。root でない呼び出し元はまず `--user` (systemd 256
  以降) を試します。
- トリミングなし: 末尾の改行、NUL バイト、UTF-8 でないバイトはそのまま
  保持されるので、パスワードは `printf %s` で封印してください。
- systemd 257 (Debian 13) の `--with-key=host` で測定しました。TPM2 鍵では
  測定していません。復号に失敗すると `ErrUnavailable` を返し、クレデンシャルの
  再封印が必要かもしれないと伝えます。
- PCR バインド: `--tpm2-pcrs=` の既定は空です。`--tpm2-pcrs=7` だけを指定すると、
  ファームウェアや shim の更新、vTPM の移行の後にすべてのクレデンシャルが
  開けなくなることがあります。`--with-key=host+tpm2`、署名付き PCR ポリシー
  (`--tpm2-public-key`、PCR 11)、または `systemd-pcrlock` を使い、再封印用に
  秘密のコピーを保管してください。

## KeePassXC {#keepassxc}

KeePassXC には、そのブラウザー連携プロトコルで接続します (macOS と Linux。
Windows は未実装です)。v0.6.0 以降、Unix では、ソケットがシンボリックリンクである場合、またはその
ディレクトリが別のユーザーの所有であるか、グループまたはその他に書き込み可能な場合にソケットは拒否され、
接続したピアの uid がダイヤルの後に確認されます。従来の
`$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer` シンボリックリンクはもう辿られません
(`app/org.keepassxc.KeePassXC/` 配下の実際のソケットは辿られます)。

v0.6.1 以降、関連付けファイル (macOS のキーチェーンも Secret Service もないときに使うフォールバックの
保存先) は、同じディレクトリ内の新しい一時ファイルに書き込まれてから最終的な名前の上へ rename されます。
そのため、その名前に残されたシンボリックリンクは、辿られるのではなく置き換えられ、モードが緩いファイルは
0600 になります。Unix ではまずディレクトリが、ソケットのものと同様に検査されます: このユーザーの所有で、
グループにもその他にも書き込み不可で、シンボリックリンクでないこと。そうでなければ何も書き込まれません。

v0.8.1 以降、その書き込みは [`harden/privfile`]({{< relref "/libraries/harden.md#privfile" >}})
v0.2.0 が行います。Windows では、ファイルは go-authn/kinit v0.3.2 と同様に所有者専用の保護された
アクセスリストを持つようになり、ディレクトリは書き込みの前だけでなく書き込みの時点でも改めて
確認されます。

1. KeePassXC で *Settings > Browser Integration* を有効にします。
2. データベースごとに 1 回、このマシンを関連付け、KeePassXC で承認します:
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. エントリを作成し、その **URL フィールド**に `https://fido.invalid/yubikey-5c`
   を入力します (他のエントリが使っていない任意の URL。参照はその URL です)。
   シークレットを表示せずに参照を確認します:
   ```sh
   secretsource check 'keepassxc:https://fido.invalid/yubikey-5c'
   ```

エントリの最初の読み取りで、KeePassXC のアクセス確認ダイアログが表示されます。

`fido --pin-from` ([fido]({{< relref "/libraries/fido.md" >}}) を参照) と、
`theca --pin-from`、`--password-from`、`--recovery-from` が使用します。

## コマンドラインフラグからシークレットを受け取る: `secretsource/secretflag` {#secretflag}

フラグの値として渡したシークレットは `ps` に見えてしまいます。`secretflag`
パッケージは、コマンドに `--<name>`（非推奨、stderr に警告）と
`--<name>-from <ref>` の組を、相互排他で提供し、参照は `secretsource.Open`
で解決されます:

```go
var password string
b := secretflag.Add(cmd, "password", &password, "the admin password") // cobra
// or: secretflag.AddStd(fs, os.Stderr, "password", &password, "the admin password", "p")
// ... after parsing:
if err := secretflag.Resolve(ctx, b); err != nil { return err }
```

`Add` は cobra コマンドに、`AddStd` は標準ライブラリの `flag.FlagSet` に
（`-t` のような別名付きで）この組を登録し、`Resolve` が参照を読み取ります。
v0.10.0 から利用できます。

`AddFrom` は、非推奨の素のフラグを持たず `--<name>-from` だけを登録します。素の
フラグが非推奨になった後に導入されるシークレット向けです。`AddFromList` は
繰り返し指定できる `--<name>-from` を登録し、`Resolve` は解決したすべての
シークレットを順番に `*[]string` へ追加します（鍵のローテーション用）。どちらも
`Add` と同様に前後の空白を取り除き、空のシークレットを拒否し、エラーに値を含めません。
v0.12.0 から利用できます。

## シークレットを保存する: `secretsource store` {#store}

エントリを手で作る必要はありません。`secretsource store REF [--group G]
[--login L] [--replace] [--generate N]` は、`keychain:`、
`secretservice:SERVICE/ACCOUNT`、`secretservice:KEY=VALUE`、`keepassxc:URL` に
シークレットを書き込みます:

```sh
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c'
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c' --generate 24
printf '%s' "$PIN" | secretsource store keychain:fido/yubikey-5c
```

シークレットはエコーなしで 2 回入力するか、標準入力がターミナルでなければそこから
読み取ります。引数や環境変数からは決して取りません。`--generate N` は N 文字の
英数字を生成し、秘密の内容は何も表示しません。既存のエントリは `--replace` が
ない限り拒否されます (KeePassXC では、URL で見つけたそのエントリを更新します)。
`file:` は拒否されます。

`keepassxc:` ではブラウザープロトコルの `set-login` を使うため、エントリは常に
それを再び見つけるための URL を持ち、重複は URL で調べます。ログインの既定は
URL のホスト (`--login`)、グループは、ルート直下の名前を `--group` で指定しない限り
`KeePassXC-Browser Passwords` で、`--title` は KeePassXC 2.8.0 が無視するため
拒否されます。KeePassXC は独自のダイアログを表示します。

## シークレットを削除する: `Delete` {#delete}

`Delete(ctx, ref)` は `Store` の対になるもので、キーチェーンにトークンを保存している
呼び出し側が、ログアウト時にそれを削除できます。v0.11.0 から利用できます。

- `keychain:` と `secretservice:SERVICE/ACCOUNT` はアイテムを削除します。Secret
  Service の検索が複数のアイテムに一致した場合、結果は `ErrAmbiguous` で、何も
  削除されません。
- `keepassxc:URL` はブラウザープロトコルの `delete-entry` を使います。KeePassXC は
  確認を求め、エントリをごみ箱に移動するため、ごみ箱を空にするまでパスワードは
  データベースに残ります。
- 存在しないエントリは、`ErrNotFound` であり同時に `fs.ErrNotExist` でもあるエラーに
  なるので、「すでに存在しない」ことを意図的に成功として扱えます。
- `file:`、`systemd-creds:`、`secretservice:KEY=VALUE` は `ErrNoDelete` で拒否されます。
  このパッケージは自分が保存していないファイルやクレデンシャルを管理せず、
  属性による検索は単一のアイテムを指さないためです。

エントリは削除の前に検索されます。秘密の内容は返されず、ログにも出ません。

## リファレンス {#reference}

このページの根拠は
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) の
README です。
