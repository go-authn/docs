---
title: "sdcreds — 无需 systemd 的 systemd 凭据"
linkTitle: "sdcreds"
weight: 37
description: "go-authn/sdcreds 可在 Go 中读写 systemd 凭据格式（systemd-creds encrypt 和 decrypt），并提供命令行和一个 s6 辅助工具，为受监管的服务提供其 $CREDENTIALS_DIRECTORY。"
tags: [libraries, sdcreds, secrets, s6]
---

**如果服务需要 systemd 单元通过 `LoadCredentialEncrypted=` 获得的凭据，而系统上没有 systemd，该怎么办？** `sdcreds` 可在 Go 中读写
[systemd 凭据](https://systemd.io/CREDENTIALS/)格式
（`systemd-creds encrypt` / `decrypt`），并提供命令行和一个辅助工具，为由 s6
监管的服务提供同样的 `$CREDENTIALS_DIRECTORY`。

支持的密钥：**null**、**host**（`/var/lib/systemd/credential.secret`）和
**host-scoped**（`--uid` / `--user`）。TPM2 和公钥凭据会被识别并以
`*UnsupportedModeError` 拒绝；不做任何猜测。

## 安装 {#install}

```sh
go install github.com/go-authn/sdcreds/cmd/sdcreds@latest
```

这些页面所描述的版本是 v0.4.3。32 位 OpenBSD（i386、armv7）会被拒绝：构建会有意失败，因为挂载布局（`mfsArgsSize` 144 和挂载结构）是 amd64 与 arm64 的 LP64 布局，尚未对照 32 位头文件检查。

## 命令行 {#cli}

```sh
sdcreds setup                                  # create the host secret if missing
sdcreds encrypt --name=db-password plain.txt db-password.cred
sdcreds decrypt db-password.cred -             # the name must match the file name
```

在 Go 中的相同操作：

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

`s6-run` 会在挂载任何东西**之前**解密 `--source` 中的每个文件，挂载一个每个服务独立的
`tmpfs`（`nodev,noexec,nosuid,nosymfollow,noswap`，权限 0700，大小和 inode 数量均有上限；
若内核没有这些选项则使用 `ramfs`），以 0400 权限、属主为服务用户写入明文，将其重新以只读方式挂载，
设置 `CREDENTIALS_DIRECTORY`，然后在一个会放弃特权（`no_new_privs`、空的能力集）的子进程中
启动服务并等待它结束。

- `s6-run` 仍然是 s6 所监管的进程：它把 `TERM`、`INT`、`HUP`、`QUIT`、`USR1`、
  `USR2`、`ALRM` 和 `CONT` 转发给服务，以服务的状态退出（若被信号终止，则为 128 加信号编号），
  传递它收到的文件描述符，并且在 `s6-run` 死亡时服务会被终止。
- 凭据会在服务结束时被清除，若程序无法执行，则在 `s6-run` 失败之前清除。
- 挂载默认位于私有命名空间中（`--unshare=false` 可将其关闭），因此会随服务一同消失。
- 用 null 密钥封存的凭据会被拒绝，除非给出 `--allow-null`；不带名称的凭据则始终被拒绝。
- `sdcreds s6-finish --service=web` 会延迟卸载并删除该目录；它是幂等的。使用 `--unshare=false`
  时，对 `s6-run` 发送 `SIGKILL` 会使挂载一直保留到 `s6-finish` 运行：请把它放进服务的 finish 脚本。
- 每个服务最多 1024 个凭据和 16 MiB。仅限 Linux；在其他系统上，这些命令报告 `ErrUnsupported`。

由 `--secret` 和 `--machine-id-file` 指定的密钥文件必须属于 root，且组和其他用户不可写，
从它们向上直到 `/` 的每一级目录同样如此。密钥文件只打开一次，不跟随末尾的链接，
并且密钥会在 `s6-run` 处理完凭据后从其内存中擦除。只有子进程会采用服务的身份；
`s6-run` 及其所有线程仍然保持 root。

### 保留一项能力:`--keep-cap` {#keep-cap}

```sh
sdcreds s6-run --service=vpn --user=svc --source=/etc/creds --keep-cap=CAP_NET_ADMIN -- /usr/bin/vpn
```

该标志可重复使用,也可用逗号分隔(`--keep-cap=CAP_NET_ADMIN,CAP_NET_RAW`,或每个一个标志),
并且**没有默认值**:不使用它时,服务以所有能力集合均为空的状态运行。

它是由七项能力组成的**允许列表**,其中没有一项等同于 root,也无法读写凭据 tmpfs 或向
`s6-run` 发送信号:`CAP_NET_ADMIN`、`CAP_NET_BIND_SERVICE`、`CAP_NET_RAW`、
`CAP_NET_BROADCAST`、`CAP_IPC_LOCK`、`CAP_WAKE_ALARM` 和 `CAP_BLOCK_SUSPEND`。
任何其他能力,或不是能力的名称,都是会指出允许列表的错误,并在读取密钥或挂载任何内容之前报告。

服务在其 bounding、permitted、inheritable、effective 和 ambient 集合中,恰好只有所保留的能力。
`no_new_privs` 保持开启,securebits 为 0x3(`SECBIT_NOROOT` 已设置并锁定)。`s6-run`
自身的权限不变。

`CAP_NET_ADMIN` 作用于服务所在的网络命名空间;除非服务在自己的网络命名空间中启动,否则那就是
主机的网络命名空间(`--unshare` 只给它一个私有的挂载命名空间):在那里它可以更改接口、路由和防火墙。
需要时,请在其自己的网络命名空间中运行这样的服务。

## `sdcreds run`:OpenBSD 与 Linux {#run}

```sh
sdcreds run --service=web --user=svc --source=/etc/creds [--class=daemon] -- /usr/local/bin/web
```

`run` 解密 `--source` 中已封存的文件,把它们作为归 `--user` 所有的只读文件放在
`$CREDENTIALS_DIRECTORY` 下供程序看到,以该用户身份运行程序,并在程序结束时删除它们。在 Linux 上,
它就是参数相同的 `s6-run`。`--check` 会执行每一项拒绝检查,但不解密任何内容(可用于 rc.d 的
`rc_pre`)。拒绝以状态 2 退出,并发生在读取主机密钥之前。在 OpenBSD 上,文件位于为该服务挂载的内存
文件系统(MFS)中,结束时清零:

- **没有挂载命名空间。** 程序运行期间,任何能访问该目录的进程都能看到这些凭据,root 始终可以读取。
- **主机密钥**是 `/etc/sdcreds/host.key`,属主为 root,权限 0600;其他权限或属主一律拒绝。用
  `sdcreds setup --path /etc/sdcreds/host.key` 创建,再执行 `chmod 600`。机器 ID 取自
  `sysctl hw.uuid`。`--secret` 与 `--machine-id-file` 可分别覆盖这两者,并经过同样的属主与权限检查。
- **`--user` 绝不能是 root**:uid 0、gid 0 以及任何属于组 0 的附加组都会被拒绝,`run` 与库
  (`s6.Run`、`delivery`)都是如此,没有任何参数可以允许。程序必须是用户可执行的、已规范化的绝对路径。
- **杀死 sdcreds 会杀死程序**并卸载,即使用 `SIGKILL` 也一样。一个辅助进程持有服务锁并监视 sdcreds;
  无论以何种方式结束,它都会杀死服务用户运行的所有进程(按 uid,所以调用过 `setsid` 的程序也逃不掉),
  然后卸载。root 从不向从列表中读到的 pid 发送信号。自 v0.4.0 起,杀死由 root 启动的一个短命杀手进程
  完成,它在发送任何信号之前先切换为分离的凭据(一个保留的杀手用户的真实 uid 与保存 uid,服务用户的有效
  uid):内核于是允许它向服务用户的每个进程发信号,而该用户的任何进程都无法向它发信号。杀手反复发送
  `kill(-1, SIGKILL)`,直到内核找不到任何进程;同一服务用户的杀死由该用户的一把锁(`/var/run/sdcreds-killer-<uid>.lock`)串行化,对另一用户的杀死
  绝不会让某次释放等待或放弃。不同用户的两个杀手共用杀手的真实 uid,可以互相发信号:因此而死亡的杀手会
  被重新运行,因为由进程表决定;到预算时仍不为空的用户会被报告(失败时保持安全)。
  **安装要求:** 创建杀手用户,它不得拥有任何进程,也不得是 root 或服务用户:
  `useradd -s /sbin/nologin -d /var/empty -c "sdcreds killer" _sdkill`。没有它,或它拥有某个进程时,交付的启动会被拒绝(启动最多等待 20 秒,等正在运行的释放的杀手)。
  仅通过另一用户运行的 set-uid 文件持有该用户身份的进程,会被启动检查计入,但杀手够不到它:释放时会报告
  有进程存活,下一次启动被拒绝,直到它消失(失败时保持安全)。若有进程在 20 秒的预算后仍然存活,辅助进程依然会卸载(机密随之消失),报告失败并以非零状态
  退出。一个用户同一时间只属于一次交付(`/var/run/sdcreds` 中的 `.uid-<N>.lock`),`run` 会拒绝已有其他
  进程的用户:请给服务一个专用用户。若 sdcreds 与辅助进程都死亡,`sdcreds sweep [--base DIR]
  [--service S]`(或服务的下一次启动)会清除残留。程序结束后若释放失败,sdcreds 以状态 70 退出,无论程序
  自身的状态是什么(程序的状态连同原因会打印在 stderr)。
- **`run` 的退出状态**(自 v0.4.0 起)。程序自身的状态原样传递(被信号 `n` 杀死的程序为 `128+n`)。
  sdcreds 自身的结束方式使用保留状态,位于守护进程常用的 0-2 与 64-78 范围之外:**125** sdcreds 拒绝,
  未启动任何东西(参数错误、未知用户或 root、未加密的交换区、仍在运行的实例;在有变化之前一直如此);
  **126** sdcreds 开始之后失败(交付、辅助进程丢失、程序无法执行;可能是暂时的);**70** 程序已结束,
  但释放失败,无论程序自身的状态是什么(该状态随后打印在 stderr)。自己以 125 或 126 退出的程序无法区分。v0.4.0 之前,拒绝以 2 退出,失败以 1 退出。
- **重启。** 启动最多等待 47 秒,让同一服务的上一次运行完成拆除(拆除最多可能花 46 秒),而不是被拒绝;47 秒后仍然存活的运行会被
  拒绝(125)。同一用户的第二个服务仍会立即被拒绝。
- **交换区必须加密。** 当 `sysctl vm.swapencrypt.enable` 为 0、无法读取或不存在时,`run` 拒绝启动,
  没有任何参数可以绕过。在库中,`s6.Config` 需要一个 `ReadSource`(命令会提供沿信任链检查的读取器),
  否则 `s6.Run` 拒绝。
- **内嵌的文件系统镜像是固定的**:每个 `delivery/images/ffs-<N>MiB.gz` 的 sha256 在辅助进程解压之前
  被检查。
- **`--class`** 先在 `/etc/login.conf.d/<class>` 中查找,再查 `/etc/login.conf`;不会查询
  `login.conf.db`。该类别的资源限制应用于程序,只会降低其本来拥有的值;无法读取或解析的类别会被拒绝。
  优先级与 umask 不会应用,程序的 umask 为 077。
- **程序的环境是白名单**:`PATH`(固定默认值)、`CREDENTIALS_DIRECTORY`、`LANG`、`TZ`、`TERM` 与
  `LC_*`。大于 2 的描述符在运行前关闭。
- **传递环境与描述符**(OpenBSD,自 v0.4.0 起)。`--pass-env NAME`(可重复)把 sdcreds 自身环境中的变量
  `NAME` 原样交给程序(未设置则不传递);`--pass-fd N`(可重复)让描述符 `N` 在程序中以相同编号保持打开。
  对 sdcreds 自己拥有的内容会拒绝:`PATH`、`CREDENTIALS_DIRECTORY`、`__SDCREDS_*`,描述符 0 到 3,以及
  未打开或带 close-on-exec 的描述符。notify 类型服务的监督者例如传入
  `--pass-env NOTIFY_SOCKET --pass-env LISTEN_FDS --pass-env LISTEN_PID --pass-fd 4`。
  `LISTEN_PID` 原样传递:它指的是调用者预期的 pid,而不是程序的 pid。
- **内存。** 明文会短时间存在于 sdcreds 进程的内存中。在 OpenBSD 上 Go 进程无法使用 `mlockall`
  (在 8.0 上实测),因此保护手段是 `vm.swapencrypt.enable`(启动时检查)、关闭核心转储以及
  `kern.nosuidcoredump`。管理员生成的崩溃转储仍可能包含明文。
- `--keep-cap` 仅适用于 Linux。

仓库中的 `docs/openbsd/authn_bridge` 是以这种方式运行 go-authn/bridge 的 rc.d 脚本。该交付机制也是
一个库,即 `delivery` 包。

## 互操作性 {#interop}

两个方向都针对真实的 `systemd-creds` **262.2** 进行了测试，它由 `v262.2` 标签构建
（不使用发行版软件包）。

- `testdata/systemd-v262.2` 包含由 systemd-creds 写入的 44 个凭据（null、host 和 host-scoped；
  有名称和无名称；无 not-after、过去和未来的 not-after；0 B、1 B 和 64 KiB 的负载；
  五个被篡改的变体），`manifest.json` 记录了 systemd-creds 自己对 272 次解密尝试
  （正确和错误的名称、not-after 之前和之后、带和不带 `--uid`）的每一次所给出的回答。
  对于每一次，该库都给出相同的回答，并且错误类别也相同。
- 在固定 IV 的情况下，`Encrypt` 能精确复现 systemd 的字节。
- 在容器中，`systemd-creds decrypt` 能打开 `Encrypt` 写出的内容，命令行在两个方向上
  也都通过了同样的往返测试。

```sh
docker build -t sdcreds-interop docker
docker run --rm --privileged -e SDCREDS_REQUIRE_SYSTEMD=1 -e SDCREDS_S6_INTEGRATION=1 \
  -v "$PWD":/src/sdcreds -w /src/sdcreds sdcreds-interop \
  sh -c 'echo 0123456789abcdef0123456789abcdef > /etc/machine-id && go test -count=1 ./...'
```

未设置 `SDCREDS_REQUIRE_SYSTEMD=1` 时，需要该二进制文件的测试会被跳过；CI 会设置它，
因此在 CI 中缺少该二进制文件即为失败。1 MiB 的边界仅由库测试覆盖，而不是由互操作向量覆盖。

## 与 systemd 的差异 {#deviations}

- 机器 ID 不匹配的主机密钥会被**拒绝**（`ErrHostKeyMachine`）；systemd 则会将其删除。
- `--with-key=auto` 表示 `host`：这里没有 TPM2。
- 用 null 密钥封存的凭据没有保密性：除非给出 `--allow-null`，`sdcreds decrypt` 在任何机器上
  都会拒绝它（systemd 则会查询 TPM2 和 SecureBoot 的状态；该库策略 `SystemNullPolicy`
  不被 CLI 使用）。
- `SDCREDS_MACHINE_ID_FILE`（`encrypt`、`decrypt`、`setup`）指向另一个机器 ID 文件。
  `s6-run` 会忽略它以及 `SYSTEMD_CREDENTIAL_SECRET`：其密钥来自默认文件，或来自
  `--secret` 和 `--machine-id-file`。
- 读取时接受可变的 IV 大小，与 systemd 一致；该库写入时始终为 12 字节。
- 打开密钥时不跟随末尾的符号链接，并且它必须是只有一个链接、权限为 `0400` 的常规文件，
  这与 systemd 的要求相同。

## 安全 {#safety}

每个长度在使用之前、在分配任何内存之前都会被检查，并且在其边界的两侧都会检查；凭据被限制为
1 MiB（与 systemd 相同），主机密钥被限制为 16 MiB。解析器在 CI 中进行模糊测试，语料库已提交，
并且 `govulncheck` 在 CI 中运行。README 目前还没有性能表：测量被推迟，是一个未决事项，而不是结果。

## 参考 {#reference}

[github.com/go-authn/sdcreds](https://github.com/go-authn/sdcreds) 的 README 是本页面的权威来源。
请参见该模块的 `LICENSE`。
