---
title: "authnd, 다른 곳에 있는 사람들을 위한 LDAP 서버"
linkTitle: "authnd"
weight: 10
description: "구성 파일, SQL 데이터베이스 또는 다른 디렉터리에 있는 사람들을 위한 LDAP 디렉터리이며, 선택적으로 Kerberos 렐름도 제공합니다."
tags: [authnd, ldap]
---

**사이트의 사람들은 이미 데이터베이스, 파일 또는 다른 디렉터리에 있습니다. 이들을
인증하려는 것들은 LDAP을 사용합니다.** authnd는 그 앞단입니다.
[go-authn/directory]({{< relref "/libraries/_index.md" >}})의 소스 위에서 바인드와
검색을 처리하므로, 데이터베이스에 있는 내용을 디렉터리에 질의할 줄 아는 어떤
것이든 읽을 수 있습니다. 순수 Go, `CGO_ENABLED=0`, 바이너리 하나입니다. 이 문서는
v0.11.1을 설명하며, 이 버전의 엔트리는 표준 스키마를 따르고 `cn=Subschema`에서
제공하는 스키마를 통과합니다. 그 아래에는 go-authn/ldap v0.8.0과
go-authn/directory v0.14.0이 있습니다. 무엇이 검증되었고 무엇이 아닌지는
[상태]({{< relref "/status.md" >}}) 페이지에 있습니다.

{{< callout type="warning" >}}
**v0.10.x에서 업그레이드하는 경우**

- `publish_nt_hash = true`에는 이제 [`samba` 블록]({{< relref "/authnd/tls.md#the-samba-block" >}})이
  필요하며, 없으면 authnd가 시작하지 않습니다.
- `uidNumber`, `gidNumber`, `homeDirectory`가 없는 사람은 더 이상
  `posixAccount`가 아니고, `gidNumber`가 없는 그룹은 더 이상 `posixGroup`이
  아니므로, 해당 클래스로 필터링하는 소비자는 더 적은 엔트리를 봅니다.
  [엔트리]({{< relref "/authnd/entries.md" >}})를 참조하십시오.
- `users "ldap"` 블록은 이제 기본적으로 그 뒤의 디렉터리를 더 많이 읽습니다.
  [사람들]({{< relref "/authnd/people.md#in-another-ldap-directory" >}})을 참조하십시오.

새 바이너리의 `authnd check`는 다시 시작하기 전에 이 세 가지를 모두 알려 줍니다.
{{< /callout >}}

```sh
authnd --config /etc/authnd      # serve
authnd check /etc/authnd         # say what would be served, without listening
```

## 가장 작은 구성 {#the-smallest-configuration}

```hcl
listen  = "127.0.0.1:3893"            # the default
base_dn = "dc=example,dc=org"         # required

reader "cn=reader,dc=example,dc=org" { password_file = "/etc/authnd/reader.pw" }

user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

group "staff" { members = ["alice"] }
```

사람은 `uid=<name>,ou=people,<base_dn>`로, 그룹은
`cn=<name>,ou=groups,<base_dn>`로 게시됩니다. 각 엔트리가 *무엇인지*는 소스가
제공한 것에 따라 정해집니다. 사람은 `account`이거나, `sn`이 있으면
`inetOrgPerson`이고, `uidNumber`, `gidNumber`, `homeDirectory`가 있어야만
`posixAccount`입니다. 모든 사람은 `uidObject`입니다. 그룹은 `gidNumber`가 있으면
`posixGroup`(`memberUid` 포함)이고, 없으면 `groupOfNames`(`member` DN 포함)이며,
비어 있기까지 하면 `organizationalRole`입니다. 사람에게 키가 있으면
`sshPublicKey`가 추가되고, [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}})가
허용하고 SID를 줄 수 있으면 `sambaNTPassword`가 추가됩니다. 모든 엔트리는 게시되기
전에 `cn=Subschema`에서 제공하는 스키마를 통과합니다.
[엔트리와 스키마]({{< relref "/authnd/entries.md" >}})를 참조하십시오. v0.10.2까지는
무엇을 가졌든 모든 사람이 `posixAccount`였고 모든 그룹이 `posixGroup`이었습니다.

`--config`(`-c`)는 파일 또는 디렉터리를 받으며 여러 번 지정할 수 있습니다.
디렉터리는 그 안의 모든 `.hcl` 파일을 이름 순으로 읽어 하나의 구성으로
병합합니다. `base_dn`이 없거나 사람이 아무도 없는 구성은 시작하지 않습니다.

## 누가 바인드할 수 있고 누가 읽을 수 있는가 {#who-may-bind-and-who-may-read}

LDAP 서버는 사람을 증명하도록 요청받으므로, 거부가 곧 설계입니다. 다음은
v0.10.0 릴리스 바이너리가 OpenLDAP의 클라이언트에 대해 낸 응답입니다.

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y wrong.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -w ''
ldap_bind: Server is unwilling to perform (53)
	additional info: an unauthenticated bind proves nothing, and this server does not accept one

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -b dc=example,dc=org '(uid=alice)'
Insufficient access (50)
Additional information: only a reader may search
```

| 요청 | 응답 | 이유 |
|---|---|---|
| 빈 이름, 빈 비밀번호 (RFC 4513 §5.1.1, 익명) | 성공 | "나는 아무도 아니다"라는 뜻이며 이는 사실이고, 클라이언트는 아무것도 알아내기 전에 이것을 보냅니다 |
| **이름**이 있고 비밀번호가 빈 경우 (§5.1.2, 비인증) | `unwillingToPerform` | 누군가를 지목하면서 아무것도 증명하지 않습니다. §5.1.2가 바로 이 코드를 요구합니다. `invalidCredentials`라고 하면 사람에게 비밀번호가 틀렸다고 알려 주는 셈입니다 |
| 틀린 비밀번호, 또는 여기에 없는 이름 | `invalidCredentials` | 둘을 구분하지 않습니다 |
| `reader`가 아닌 누군가의 검색 | `insufficientAccessRights` | 바인드는 당신이 누구인지를 증명할 뿐이며, 모든 사람을 읽도록 허용되는 것은 별개의 문제입니다 |
| `add`, `delete`, `modifyDN` | `unwillingToPerform` | 연결된 핸들러가 없습니다. 유일한 쓰기는 [사람 자신의 비밀번호]({{< relref "/authnd/passwords.md" >}})입니다 |

`reader`는 바인드 DN과 `password` 또는 `password_file`을 가진 서비스 계정입니다.
둘 다 없는 reader는 시작 시 거부됩니다(*아무것도 증명하지 않는 reader는 단계만
늘어난 익명 검색입니다*). reader가 하나도 없으면 아무도 검색할 수 없으며,
`check`가 이를 알려 줍니다.

루트 DSE는 디스커버리에 필요하므로 익명 클라이언트에게 응답합니다.

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
vendorVersion: v0.11.1
```

`1.3.6.1.4.1.4203.1.11.1`은 RFC 3062 비밀번호 변경 작업입니다.
`subschemaSubentry`는 [스키마]({{< relref "/authnd/entries.md#the-schema-it-serves" >}})를
가리키며, 이것도 익명 클라이언트에게 응답합니다.
`supportedSASLMechanisms: OAUTHBEARER`는 [`oidc` 블록]({{< relref "/authnd/tokens.md" >}})이
있을 때만 나타납니다.

## 다음에 볼 곳 {#where-to-go-next}

| | |
|---|---|
| [설치하기]({{< relref "/authnd/install.md" >}}) | 릴리스 바이너리, `authnd` 계정, systemd 유닛, 업그레이드 |
| [사람들은 어디에서 오는가]({{< relref "/authnd/people.md" >}}) | `user`와 `group` 블록, SQL 데이터베이스, 다른 LDAP 디렉터리 |
| [엔트리와 스키마]({{< relref "/authnd/entries.md" >}}) | 각 사람과 그룹이 무엇으로 게시되는지, `cn=Subschema`, 속성, 제외되거나 보류되는 것 |
| [`check`]({{< relref "/authnd/check.md" >}}) | 다시 시작하기 전에 구성을 되읽기 |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` 또는 StartTLS, 그리고 `publish_nt_hash` |
| [비밀번호 변경]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, 그리고 이전 비밀번호를 항상 묻는 이유 |
| [Kerberos 렐름]({{< relref "/authnd/kerberos.md" >}}) | keytab, 그리고 누가 티켓을 발급받을 수 있는가 |
| [두 번째 인증 요소]({{< relref "/authnd/mfa.md" >}}) | 비밀번호 끝에 붙는 일회용 코드 |
| [바인드 시의 토큰]({{< relref "/authnd/tokens.md" >}}) | SASL `OAUTHBEARER` 위의 OIDC |
| [운영하기]({{< relref "/authnd/operations.md" >}}) | 시그널, 재시작, 로그 내용, 가동 여부 확인 방법 |

{{< callout type="info" >}}
**트랜스크립트에 대하여**

모든 시작 줄, 루트 DSE, `--version` 줄은 v0.11.1 릴리스 바이너리
(`authnd-darwin-arm64`, `go version -m`: `mod github.com/go-authn/authnd v0.11.1`,
`vcs.modified=false`)가 출력한 것이며, 시작 줄과 같은 트랜스크립트에 보이는 다른
모든 명령도 마찬가지입니다. v0.11.1은 그 줄 외에는 아무것도 바꾸지 않습니다.
모든 `check` 표, `ldapsearch`로 되읽은 엔트리, `cn=Subschema`, `samba` 거부는
v0.11.0 릴리스 바이너리(`mod github.com/go-authn/authnd v0.11.0`,
`vcs.modified=false`)가 출력한 것입니다. 이 문서의 구성 거부도 마찬가지이며,
v0.11.0은 이를 v0.10.0과 바이트 단위로 동일하게 출력했습니다. 그 밖의 바인드,
`kinit`, 비밀번호 변경, 토큰 교환은 v0.10.0 릴리스 바이너리가 출력한 것이며,
v0.11.0과 v0.11.1의 릴리스 노트 어디에도 이들을 바꾸는 내용이 없으므로 다시
실행하지 않았습니다. 모두 macOS에 포함된 OpenLDAP 및 Heimdal 클라이언트로,
127.0.0.1의 비특권 포트에서 `/tmp` 아래의 임시 디렉터리 안에서 요청했습니다.
그래서 그 뒤의 구성이 `etc/authnd/passwords/alice.pw` 같은 상대 경로로 파일을
지정하고, 비밀번호 파일의 이름이 `alice.pwin` 같은 것입니다. 예제의
`/etc/authnd` 경로는 설치된 서버가 사용하는 경로입니다.
{{< /callout >}}
