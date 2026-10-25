---
title: "비밀번호가 아닌 필드에 담긴 바인드 시의 토큰"
linkTitle: "토큰 (OIDC)"
weight: 75
description: "oidc 블록: SASL OAUTHBEARER 바인드에 담긴 OpenID Connect 토큰, 그것이 몇 개의 인증 요소로 집계되는지, 그리고 무엇이 거부되는지."
tags: [authnd, oidc, oauthbearer, sasl]
---

[go-authn/oidc]({{< relref "/libraries/_index.md" >}})는 토큰을 신원으로 검증합니다.
토큰을 LDAP 서버에 전달하는 가장 뻔한 방법은 비밀번호 필드이며, 한 번은 동작하다가
멈춥니다. 비밀번호 필드는 [`mfa` 블록]({{< relref "/authnd/mfa.md" >}})이 끝에서 코드를
떼어 내는 곳이고, 토큰은 둘 다가 될 수 없기 때문입니다.

그래서 토큰은 프로토콜이 자리를 마련해 둔 곳으로 갑니다. **SASL** 바인드의
자격 증명은 메커니즘 고유의 형태를 가진 옥텟 문자열이며, RFC 7628의
`OAUTHBEARER` 형태는 GS2 헤더 다음에 키/값 쌍이 오고 그중 하나가
`auth=Bearer <token>`입니다.

```
n,,^Aauth=Bearer eyJ…^A^A
```

비밀번호 필드는 건드리지 않습니다. 한 리스너에서 동시에, 어떤 사람은 끝에 코드가
붙은 비밀번호를 입력하고 다른 사람은 토큰을 보낼 수 있습니다.

```hcl
oidc {
  issuer   = "https://login.example.org/realms/staff"   # the "iss" a token must carry, and where discovery starts
  audience = "ldap"                                     # this server's client id at the provider

  # username_claim = "preferred_username"   which claim names the person here
  # jwks_url       = "…"                    skips discovery, for a provider that does not publish it
  # allow_plaintext = true                  only when TLS is terminated in front of this process
}
```

`issuer`와 `audience`는 필수입니다. `username_claim`이 없으면 이름은
`preferred_username`이고, 그다음 `email_verified`가 true일 때의 `email`, 그다음
`sub`입니다. 이 블록이 있으면 루트 DSE가 메커니즘을 알립니다.

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' supportedSASLMechanisms
dn:
supportedSASLMechanisms: OAUTHBEARER
```

블록이 없으면 모든 SASL 바인드에 `authMethodNotSupported`로 응답합니다 — *이
방식이 아님*이며, 이는 클라이언트를 *잘못된 비밀번호*와는 다른 곳으로 보냅니다.

## 디스커버리는 시작할 때 일어납니다 {#discovery-happens-at-startup}

공급자의 디스커버리 문서와 키는 서버가 시작할 때와 `check`가 실행될 때 읽습니다.
접근할 수 없는 공급자는 나중에 모든 바인드를 거부하는 대신, 누군가 지켜보고 있는
시점에 서버를 멈춥니다.

```
$ authnd check cases/oidc.hcl
authnd: oidc "https://127.0.0.1:1/realms/staff": oidc: reading https://127.0.0.1:1/realms/staff/.well-known/openid-configuration: Get "https://127.0.0.1:1/realms/staff/.well-known/openid-configuration": dial tcp 127.0.0.1:1: connect: connection refused
```

`https`가 아닌 발급자는 루프백을 제외하고 거부됩니다.

```
$ authnd check cases/oidc-http.hcl
authnd: oidc "http://login.example.org/realms/staff": oidc: http://login.example.org/realms/staff is not https: the key set decides every signature, and over cleartext so does anybody on the way
```

## 토큰은 몇 개의 인증 요소인가? {#how-many-factors-is-a-token}

**발급자가 확인했다고 말하는 것이며, 그 이상은 아닙니다.** 토큰은 RFC 8176의
`amr`, 즉 공급자가 사용한 방법을 담습니다. 이것이 유일한 증거이므로 `mfa` 정책이
**종류별로** 집계하는 대상입니다.

| `amr` 방법 | 종류 |
|---|---|
| `pwd`, `pin`, `kba`, `mca` | 지식 |
| `otp`, `hwk`, `swk`, `sms`, `tel`, `sc`, `pop`, `user`, `wia`, `mfa` | 소유 |
| `fpt`, `face`, `iris`, `retina`, `vbm`, `geo` | 고유 특성 |
| 그 밖의 모든 것 | 알 수 없음, `distinct_kinds`를 절대 충족하지 않음 |
| `amr`이 아예 없음 | 인증 요소 하나, 소유 — 토큰 자체 |

같은 종류의 방법 두 개는 인증 요소 하나입니다. 그렇지 않으면 이 서버가 아무도
수행하지 않은 두 번째 인증 요소를 지어내는 셈이 됩니다. 그리고 *누구인지*에 대해
발급자를 믿는 서버에게는 *어떻게* 확인했는지에 대해 믿지 않을 별도의 근거가
없습니다.

`mfa` 블록이 있으면 `check`가 이를 알려 줍니다.

```
$ authnd check sasl
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS        WITH
alice  the configuration file  a password                             account, uidObject  uid
tess   the configuration file  a password and a one-time-code secret  account, uidObject  uid

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
tess has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject

a bind carries a password with a 6-digit code after it, of two different kinds
or a token from http://127.0.0.1:18481, over SASL OAUTHBEARER over TLS
  a token counts for the factors its amr claim names, so one with no amr is refused by this policy
alice has no second factor here, so a password cannot satisfy this policy; a token whose amr names two kinds still can
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

alice에게는 `totp_secret`이 없으므로 코드가 붙은 비밀번호로는 결코 충분하지 않지만,
`amr`이 두 종류를 지정하는 토큰은 충분합니다. 아래의 첫 번째 바인드가 이를 보여
줍니다.

## 바인드는 어떻게 보이는가 {#what-the-binds-look-like}

여기서 발급자는 루프백의 작은 테스트 공급자이고, `oidctool`은 이 문서를 위해
작성한 테스트 클라이언트입니다. 주어진 이름에 대해, 주어진 `amr`로 토큰에 서명하고,
`OAUTHBEARER` 바인드로 보내며(다섯 번째 인수가 지정하면 `authzid`와 함께), 바인드의
결과 코드와 서버의 SASL 자격 증명을 출력합니다. 위의 구성에 대해 `ldaps://`로:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 0, serverSaslCreds 

$ ./oidctool alice '' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","kba"]' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls tess
bind result 14, serverSaslCreds {"status":"insufficient_scope","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}

$ ./oidctool zed '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 14, serverSaslCreds {"status":"invalid_token","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}
```

0은 성공, 49는 `invalidCredentials`, 14는 `saslBindInProgress`입니다.
`["pwd","kba"]` 토큰은 같은 종류의 방법 두 개를 지정하므로 한 번으로 집계됩니다.
그리고 `cert_file`과 `key_file`이 없는 같은 구성의 평문 리스너에서는:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3893 clear
bind result 13
```

13은 `confidentialityRequired`입니다. 토큰은 암호화되지 않은 연결에서는 받지
않습니다.

`ldaps://`로 거부된 네 번의 바인드에 대해 서버가 기록한 내용입니다.

```
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: the token is for "alice" and asks to act as "tess"; this server does not delegate
zed was refused: the token verified, and no source here publishes anybody by that name
```

그리고 평문 바인드에 대해서는:

```
a token was refused: OAUTHBEARER was offered over a connection that is not encrypted, and allow_plaintext is not set
```

성공한 `OAUTHBEARER` 바인드는 연결을 `uid=<name>,ou=people,<base_dn>`으로
바인드된 상태로 두며, 다른 모든 엔트리와 같은 방식으로 표기됩니다.

## 거부하는 것 {#what-it-refuses}

- **평문의 토큰.** 베어러 토큰은 다른 절반이 필요 없습니다. 전송 중에 그것을 읽은
  사람은 만료될 때까지 그 사람입니다. `allow_plaintext = true`는 이 프로세스 앞에서
  TLS를 종단하는 배포를 위한 것이며, 그러면 `check`가 *a token may cross this
  socket in the clear*라고 알려 줍니다.
- **다른 사람이 되겠다는 요청.** GS2 헤더는 `authzid`를 지정할 수 있습니다. alice용
  토큰이 tess로 행동하겠다는 요청을 담고 있으면, 둘 중 어느 쪽으로도 조용히
  취급되지 않고 거부됩니다.
- **여기 어떤 소스도 게시하지 않는 사람의 토큰.** 클라이언트는 `invalid_token`만
  듣습니다. 어떤 이름이 존재하는지는 추측 한 번에 하나씩 내줄 것이 아닙니다.
  이유는 서버의 출력에 있습니다.
- **채널 바인딩.** `p=`가 있는 GS2 헤더 — 클라이언트가 채널 바인딩을 고집함 — 는
  거부됩니다. 이 서버는 이를 하지 않으며, 아무것도 바인딩하지 않으면서 헤더를
  받아들이면 클라이언트가 채널이 확인되었다고 믿게 됩니다.
- **이 서버가 사용하지 않는 메커니즘**은 `authMethodNotSupported`로.

토큰 자체의 거부는 RFC 7628 §3.2.3을 따릅니다. `openid-configuration`을 담은 JSON
오류이며, 클라이언트가 교환을 끝내는 `^A`를 보낼 수 있도록 `saslBindInProgress`로
반환됩니다. 검증은 되었지만 `mfa` 정책을 충족하지 못하는 토큰에는 위의 두 번째와
세 번째 바인드가 보여 주듯 그냥 `invalidCredentials`로 응답합니다.

{{< callout type="info" >}}
**토큰은 비밀번호를 설정하지 않습니다**

토큰으로만 로그인해 본 사람은 그 세션으로 자신에게 첫 번째 비밀번호를 줄 수
없으며, 비밀번호가 있는 사람도 그것을 변경하려면 여전히 보내야 합니다.
[비밀번호 변경]({{< relref "/authnd/passwords.md" >}})을 참조하십시오.
{{< /callout >}}
