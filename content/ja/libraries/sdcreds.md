---
title: "sdcreds — systemd なしの systemd クレデンシャル"
linkTitle: "sdcreds"
weight: 37
description: "go-authn/sdcreds は systemd のクレデンシャル形式(systemd-creds encrypt と decrypt)を Go から読み書きし、コマンドラインと、監視対象サービスに $CREDENTIALS_DIRECTORY を与える s6 ヘルパーを備えています。"
tags: [libraries, sdcreds, secrets, s6]
---

**systemd ユニットが `LoadCredentialEncrypted=` で受け取るクレデンシャルをサービスが必要としているのに、systemd がなかったら?** `sdcreds` は
[systemd クレデンシャル](https://systemd.io/CREDENTIALS/)の形式
(`systemd-creds encrypt` / `decrypt`)を Go から読み書きし、コマンドラインと、
s6 が監視するサービスに同じ `$CREDENTIALS_DIRECTORY` を与えるヘルパーを備えています。

対応する鍵は **null**、**host**(`/var/lib/systemd/credential.secret`)、
**host-scoped**(`--uid` / `--user`)です。TPM2 と公開鍵のクレデンシャルは認識された上で
`*UnsupportedModeError` により拒否され、推測は一切行われません。

## インストール {#install}

```sh
go install github.com/go-authn/sdcreds/cmd/sdcreds@latest
```

これらのページが説明するバージョンは v0.4.3 です。32 ビット OpenBSD（i386、armv7）は拒否されます。マウントのレイアウト（`mfsArgsSize` 144 とマウント構造体）は amd64 と arm64 の LP64 のもので、32 ビットのヘッダーとは照合していないため、ビルドは意図的に失敗します。

## コマンドライン {#cli}

```sh
sdcreds setup                                  # create the host secret if missing
sdcreds encrypt --name=db-password plain.txt db-password.cred
sdcreds decrypt db-password.cred -             # the name must match the file name
```

Go からの同じ操作:

```go
host := sdcreds.HostKeyFile{} // $SYSTEMD_CREDENTIAL_SECRET or the default path
blob, err := sdcreds.Encrypt(secret, sdcreds.EncryptOptions{Key: sdcreds.IDHost, HostKey: host, Name: "db-password"})
text := sdcreds.Armor(blob, sdcreds.ArmorWidth) // what systemd-creds prints
raw, _ := sdcreds.Unarmor([]byte(text))
plain, md, err := sdcreds.Decrypt(raw, sdcreds.DecryptOptions{HostKey: host, Name: &name})
```

## s6 {#s6}

```sh
sdcreds s6-run --service=web --user=svc --source=/etc/creds -- /usr/bin/web
```

`s6-run` は、何かをマウントする**前に** `--source` のすべてのファイルを復号し、
サービスごとの `tmpfs`(`nodev,noexec,nosuid,nosymfollow,noswap`、モード 0700、
サイズと inode 数に上限あり。カーネルがこれらのオプションを持たない場合は `ramfs`)を
マウントし、平文をサービスユーザー所有の 0400 で書き込み、読み取り専用で再マウントし、
`CREDENTIALS_DIRECTORY` を設定したうえで、権限を落とす(`no_new_privs`、空の
ケイパビリティ集合)子プロセスでサービスを起動し、その終了を待ちます。

- `s6-run` は引き続き s6 が監視するプロセスです。`TERM`、`INT`、`HUP`、`QUIT`、
  `USR1`、`USR2`、`ALRM`、`CONT` をサービスに転送し、サービスの終了ステータスで終了し
  (シグナルで殺された場合は 128 にシグナル番号を加えた値)、受け取ったディスクリプタを
  引き継ぎ、`s6-run` が死ぬとサービスも kill されます。
- クレデンシャルは、サービスが終了したとき、およびプログラムを実行できず `s6-run` が
  失敗する前に取り除かれます。
- マウントは既定でプライベートな名前空間に置かれ(`--unshare=false` で無効化)、
  サービスとともに消えます。
- null 鍵で封印されたクレデンシャルは `--allow-null` を指定しない限り拒否され、
  名前を持たないものは常に拒否されます。
- `sdcreds s6-finish --service=web` は遅延アンマウントを行いディレクトリを削除します。
  冪等です。`--unshare=false` の場合、`s6-run` が `SIGKILL` されると `s6-finish` が
  実行されるまでマウントが残ります。サービスの finish スクリプトに入れてください。
- サービスあたり最大 1024 個のクレデンシャルと 16 MiB。Linux のみで、それ以外では
  コマンドは `ErrUnsupported` を報告します。

`--secret` と `--machine-id-file` で指定する鍵ファイルは root 所有で、グループやその他から
書き込めてはならず、`/` までの上位ディレクトリすべてについても同様です。鍵ファイルは
末尾のリンクをたどらずに一度だけ開かれ、鍵はクレデンシャルの処理が終わった時点で
`s6-run` のメモリから消去されます。サービスの ID を引き受けるのは子プロセスだけで、
`s6-run` とそのすべてのスレッドは root のままです。

### ケイパビリティを保持する: `--keep-cap` {#keep-cap}

```sh
sdcreds s6-run --service=vpn --user=svc --source=/etc/creds --keep-cap=CAP_NET_ADMIN -- /usr/bin/vpn
```

このフラグは繰り返し指定でき、カンマ区切りも可能です(`--keep-cap=CAP_NET_ADMIN,CAP_NET_RAW`、
またはフラグを一つずつ)。**デフォルトはありません**。指定しなければ、サービスはすべての
ケイパビリティ集合が空の状態で実行されます。

これは 7 つのケイパビリティからなる**許可リスト**で、いずれも root 相当ではなく、
資格情報の tmpfs の読み書きや `s6-run` へのシグナル送信はできません:
`CAP_NET_ADMIN`、`CAP_NET_BIND_SERVICE`、`CAP_NET_RAW`、`CAP_NET_BROADCAST`、
`CAP_IPC_LOCK`、`CAP_WAKE_ALARM`、`CAP_BLOCK_SUSPEND`。それ以外のケイパビリティや、
ケイパビリティではない名前はエラーとなり、許可リストが示されます。このエラーは鍵が
読まれる前、何かがマウントされる前に報告されます。

サービスは、bounding、permitted、inheritable、effective、ambient の各集合に、保持した
ケイパビリティだけを持ちます。`no_new_privs` は有効のままで、securebits は 0x3
(`SECBIT_NOROOT` を設定してロック)です。`s6-run` 自身の権限は変わりません。

`CAP_NET_ADMIN` はサービスが動作するネットワーク名前空間に作用します。サービスが独自の
ネットワーク名前空間で起動されない限り、それはホストのものです(`--unshare` が与えるのは
プライベートなマウント名前空間だけです)。そこではインターフェース、ルート、ファイアウォールを
変更できます。重要な場合は、そのようなサービスを独自のネットワーク名前空間で実行してください。

## `sdcreds run`: OpenBSD と Linux {#run}

```sh
sdcreds run --service=web --user=svc --source=/etc/creds [--class=daemon] -- /usr/local/bin/web
```

`run` は `--source` の封印されたファイルを復号し、`--user` が所有する読み取り専用のファイルとして
`$CREDENTIALS_DIRECTORY` の下でプログラムから見えるようにし、そのユーザーとしてプログラムを実行し、
終了時にそれらを削除します。Linux では同じフラグの `s6-run` です。`--check` はすべての拒否を実行しますが、
何も復号しません(rc.d の `rc_pre` で使います)。拒否はステータス 2 で終了し、ホスト鍵を読む前に起こります。
OpenBSD では、ファイルはサービスのためにマウントされるメモリファイルシステム(MFS)に置かれ、終了時にゼロで
埋められます。

- **マウント名前空間はありません。** プログラムの実行中、クレデンシャルはそのディレクトリに到達できる
  すべてのプロセスから見え、root は常に読めます。
- **ホスト鍵**は `/etc/sdcreds/host.key` で、所有者は root、モードは 0600 です。それ以外のモードや
  所有者は拒否されます。`sdcreds setup --path /etc/sdcreds/host.key` で作成し、その後 `chmod 600`
  します。マシン ID は `sysctl hw.uuid` です。`--secret` と `--machine-id-file` は両方を上書きし、
  同じ所有者とモードの検査を通ります。
- **`--user` が root になることはありません**: uid 0、gid 0、補助グループ 0 は、`run` でもライブラリ
  (`s6.Run`、`delivery`)でも拒否され、許可するフラグはありません。プログラムは、ユーザーが実行できる
  絶対パスの正規化されたものでなければなりません。
- **sdcreds を殺すとプログラムも殺され**、`SIGKILL` でもアンマウントされます。ヘルパープロセスが
  サービスのロックを保持して sdcreds を監視し、どんな終わり方でも、サービスユーザーが実行している
  すべてを(uid で。`setsid` を呼んだプログラムも逃れられません)殺してからアンマウントします。
  root が一覧から読んだ pid にシグナルを送ることはありません。v0.4.0 からは、root が起動する短命の
  キラープロセスが殺します。キラーはシグナルを送る前に分割した資格情報(予約されたキラーユーザーの実 uid
  と保存 uid、サービスユーザーの実効 uid)に切り替えます。これによりカーネルはサービスユーザーの全
  プロセスへのシグナル送信を許し、そのユーザーのどのプロセスもキラーにシグナルを送れません。キラーは
  カーネルが何も見つけなくなるまで `kill(-1, SIGKILL)` を送ります。一つのサービスユーザーの
  キルは、そのユーザーのロック(`/var/run/sdcreds-killer-<uid>.lock`)で直列化され、別のユーザーの
  キルが解放を待たせたり諦めさせたりすることはありません。異なるユーザーの二つのキラーはキラーの実 uid
  を共有するため、互いにシグナルを送れます。それで死んだキラーは再び実行されます。決めるのはプロセス
  テーブルだからです。予算の時点で空でないユーザーは報告されます(安全側に倒れます)。
  **インストール要件:** キラーユーザーを作成して
  ください。プロセスを一つも所有せず、root でもサービスユーザーでもないものにします:
  `useradd -s /sbin/nologin -d /var/empty -c "sdcreds killer" _sdkill`。これがない場合、またはこれが
  プロセスを所有している場合、配信の起動は拒否されます(起動は、実行中の解放のキラーを最大 20 秒待ちます)。別のユーザーが実行する set-uid ファイル経由でのみそのユーザーを保持しているプロセスは、
  起動時の検査では数えられますが、キラーは届きません。その場合、解放はプロセスが生き残ったと報告し、
  それがなくなるまで次の起動は拒否されます(安全側に倒れます)。プロセスが 20 秒の
  予算を超えて生き残った場合も、ヘルパーはアンマウントし(秘密は消えます)、失敗を報告して非ゼロで終了
  します。ユーザーは一度に一つの配信だけが所有します(`/var/run/sdcreds` の `.uid-<N>.lock`)。すでに
  他のプロセスを持つユーザーは `run` が拒否します。サービスには専用のユーザーを与えてください。sdcreds と
  ヘルパーの両方が死んだ場合は、`sdcreds sweep [--base DIR] [--service S]`(またはサービスの次の起動)が
  残りを削除します。プログラム終了後に解放が失敗すると、sdcreds はプログラム自身のステータスが何であれ
  ステータス 70 で終了します(プログラムのステータスは理由とともに stderr に出力されます)。
- **`run` の終了ステータス**(v0.4.0 以降)。プログラム自身のステータスはそのまま渡されます(シグナル
  `n` で殺されたプログラムは `128+n`)。sdcreds 自身の終わり方には、デーモンがよく使う 0-2 と 64-78 の
  範囲の外に予約されたステータスがあります: **125** sdcreds が拒否した(何も起動していない。不正なフラグ、
  未知のユーザーまたは root、暗号化されていないスワップ、まだ生きている実行。何かが変わるまで恒久的)。
  **126** 開始後に sdcreds が失敗した(配信、ヘルパーの喪失、プログラムを実行できない。一時的なことも
  あります)。**70** プログラムは終了したが解放が失敗した(プログラム自身のステータスが何であれ。そのステータスは stderr に出力されます)。自分で 125 や 126 で終了するプログラムは
  区別できません。v0.4.0 より前は、拒否は 2、失敗は 1 で終了していました。
- **再起動。** 起動は、同じサービスの前回の実行が後始末を終えるまで最大 47 秒待ち(後始末には最大 46 秒かかることがあります)、拒否されません。
  47 秒後もまだ生きている実行は拒否されます(125)。同じユーザーの二つ目のサービスは引き続きすぐに拒否されます。
- **スワップは暗号化されていなければなりません。** `sysctl vm.swapencrypt.enable` が 0 のとき、読めない
  とき、存在しないとき、`run` は起動を拒否します。上書きするフラグはありません。ライブラリでは
  `s6.Config` に `ReadSource`(コマンドは信頼を辿るリーダーを渡します)が必要で、なければ `s6.Run` が
  拒否します。
- **埋め込まれたファイルシステムイメージは固定されています**: 各 `delivery/images/ffs-<N>MiB.gz` の
  sha256 が、ヘルパーが展開する前に検査されます。
- **`--class`** は、まず `/etc/login.conf.d/<class>`、次に `/etc/login.conf` から探されます。
  `login.conf.db` は参照されません。クラスのリソース制限はプログラムに適用されますが、本来の値を下げる
  方向にだけ働きます。読めない、または解析できないクラスは拒否されます。優先度と umask は適用されず、
  プログラムの umask は 077 です。
- **プログラムの環境は許可リストです**: `PATH`(固定の既定値)、`CREDENTIALS_DIRECTORY`、`LANG`、`TZ`、
  `TERM`、`LC_*`。2 より大きい記述子は実行前に閉じられます。
- **環境と記述子の受け渡し**(OpenBSD、v0.4.0 以降)。`--pass-env NAME`(繰り返し可)は sdcreds 自身の
  環境の変数 `NAME` をそのままプログラムに渡します(未設定なら渡しません)。`--pass-fd N`(繰り返し可)は
  記述子 `N` をプログラム内で同じ番号のまま開いたままにします。sdcreds が所有するものは拒否されます:
  `PATH`、`CREDENTIALS_DIRECTORY`、`__SDCREDS_*`、記述子 0 から 3、開いていない記述子または
  close-on-exec の記述子。notify 型サービスのスーパーバイザーは、たとえば
  `--pass-env NOTIFY_SOCKET --pass-env LISTEN_FDS --pass-env LISTEN_PID --pass-fd 4` を渡します。
  `LISTEN_PID` はそのまま渡されます。これは呼び出し側が想定した pid を指し、プログラムの pid ではありません。
- **メモリ。** 平文は短い間 sdcreds プロセスのメモリにあります。OpenBSD では Go プロセスから `mlockall`
  を使えない(8.0 で測定)ため、保護は `vm.swapencrypt.enable`(起動時に検査)、コアダンプの無効化、
  `kern.nosuidcoredump` です。管理者が取ったクラッシュダンプには平文が残りうります。
- `--keep-cap` は Linux のみです。

リポジトリの `docs/openbsd/authn_bridge` は、この方法で go-authn/bridge を実行する rc.d スクリプトです。
配信はライブラリ(パッケージ `delivery`)でもあります。

## 相互運用性 {#interop}

両方向とも、`v262.2` タグからビルドした実際の `systemd-creds` **262.2**(ディストリビューション
パッケージは使用しません)に対してテストされています。

- `testdata/systemd-v262.2` には systemd-creds が書いた 44 個のクレデンシャル
  (null、host、host-scoped。名前あり・なし。not-after なし・過去・未来。0 B、1 B、64 KiB の
  ペイロード。改ざんされた 5 種)が含まれ、`manifest.json` には 272 回の復号試行
  (正しい名前と誤った名前、not-after の前と後、`--uid` あり・なし)それぞれに対して
  systemd-creds 自身が返した結果が記録されています。ライブラリはそのすべてに対して、
  同じ種類のエラーを含め同じ結果を返します。
- IV を固定すれば、`Encrypt` は systemd のバイト列をそのまま再現します。
- コンテナ内では、`Encrypt` が書いたものを `systemd-creds decrypt` が開き、
  コマンドラインも両方向で同じ往復に合格します。

```sh
docker build -t sdcreds-interop docker
docker run --rm --privileged -e SDCREDS_REQUIRE_SYSTEMD=1 -e SDCREDS_S6_INTEGRATION=1 \
  -v "$PWD":/src/sdcreds -w /src/sdcreds sdcreds-interop \
  sh -c 'echo 0123456789abcdef0123456789abcdef > /etc/machine-id && go test -count=1 ./...'
```

`SDCREDS_REQUIRE_SYSTEMD=1` がなければ、バイナリを必要とするテストはスキップされます。
CI ではこれを設定しているため、バイナリがないと失敗になります。1 MiB の境界は
ライブラリのテストだけが扱い、相互運用ベクターでは扱いません。

## systemd との相違点 {#deviations}

- マシン ID が一致しないホストシークレットは**拒否**されます(`ErrHostKeyMachine`)。
  systemd はそれを削除します。
- `--with-key=auto` は `host` を意味します。ここには TPM2 がありません。
- null 鍵で封印されたクレデンシャルには秘匿性がありません。`sdcreds decrypt` は
  `--allow-null` を指定しない限り、どのマシンでもそれを拒否します(systemd は代わりに
  TPM2 と SecureBoot の状態を参照します。そのライブラリのポリシー `SystemNullPolicy` は
  CLI では使われません)。
- `SDCREDS_MACHINE_ID_FILE`(`encrypt`、`decrypt`、`setup`)は別のマシン ID ファイルを
  指します。`s6-run` はこれと `SYSTEMD_CREDENTIAL_SECRET` を無視し、鍵は既定のファイル、
  または `--secret` と `--machine-id-file` から取得します。
- 可変の IV サイズは、systemd と同様に読み込み時には受け入れられます。このライブラリが
  書き込むのは常に 12 バイトです。
- シークレットは末尾のシンボリックリンクをたどらずに開かれ、systemd の要件どおり、
  リンク数 1 でモード `0400` の通常ファイルでなければなりません。

## 安全性 {#safety}

すべての長さは、使用する前、何かを割り当てる前に、その境界の両側で検査されます。
クレデンシャルは 1 MiB(systemd と同じ)、ホストシークレットは 16 MiB に制限されます。
パーサーは CI でコーパスをコミットした状態でファジングされ、`govulncheck` も CI で
実行されます。README にはまだ性能表がありません。測定は先送りされており、結果ではなく
未解決の項目です。

## リファレンス {#reference}

[github.com/go-authn/sdcreds](https://github.com/go-authn/sdcreds) の README がこのページの
一次情報です。モジュールの `LICENSE` を参照してください。
