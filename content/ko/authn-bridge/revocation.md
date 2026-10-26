---
title: "무엇을 폐기하는지, 그리고 서버가 그것을 알게 되는 방법"
linkTitle: "폐기"
weight: 60
description: "폐기한 인증서에 대해 authn-bridge가 게시하는 서명되고 날짜가 기입된 KRL과 CRL, 그리고 어떤 목록도 지명할 수 없는 것에 도달하는 Shared Signals 송신기."
tags: [authn-bridge, 폐기, krl, crl, 공유 시그널]
---

사람이나 기관을 비활성화하면([관리 API]({{< relref "/authn-bridge/admin.md" >}})) 공급자로
되돌아오는 모든 것이 끝납니다. 리프레시 토큰, `/userinfo`, 새 인증서, 애플리케이션
비밀번호. 이미 전달된 것은 다른 곳에서 키를 기준으로 확인되며, 세 가지 메커니즘이
거기에 도달합니다.

| 자격 증명 | 회수하는 방법 |
|---|---|
| 이 CA가 서명한 SSH 인증서 | **KRL**, `GET /ssh/krl`, 서명은 `/ssh/krl.sig` |
| X.509 클라이언트 인증서 | **CRL**, `GET /x509/crl` |
| 액세스 토큰, opkssh 인증서, 서버가 단독으로 검증하는 모든 것 | **Shared Signals** `session-revoked` 이벤트 |

폐기는 영구적입니다. 사람을 다시 활성화해도 그들의 인증서가 돌아오지 않으며, 새
인증서를 받습니다. 폐기를 빼낼 수 있는 목록은 관리 API에 도달하는 누군가가 편집할 수
있는 목록입니다.

## 목록 {#the-lists}

둘 다 go-authn/revocation의 프로토콜이 말하는 대로 발급되므로, 무엇을 통해서든
(미러, 일반 HTTP, 파일) 이동해도 읽는 사람이 확인할 수 있습니다.

| | KRL | CRL |
|---|---|---|
| 형식 | OpenSSH `PROTOCOL.krl`, go-authn/krl이 기록: `sshd`의 `RevokedKeys`와 `ssh-keygen -Q`가 읽는 것 | DER, RFC 5280 |
| 서명 | SSH CA 키의 분리된 SSHSIG, 네임스페이스 `krl@go-authn.github.io` | 인증서에 서명하는 CA |
| 유효 기한 | `expires@go-authn.github.io` 확장 (sshd는 무시) | `nextUpdate` |
| 순서 | `krl_version`, 그다음 생성 날짜 | CRL Number, 그다음 `thisUpdate` |

각 목록은 발급된 지 **한 시간** 뒤에 유효하지 않게 된다고 밝힙니다. 목록은 그
절반에 도달하거나 무언가 폐기될 때까지 그대로 보관되고 제공되며, 그다음 요청이 새
발급을 받습니다. 발급은 시계가 거꾸로 가더라도 그것이 대체하는 발급보다 이른 날짜가
되지 않습니다. 읽는 쪽은 같은 버전의 더 이른 발급을 롤백으로 거부하기 때문입니다.
CRL Number는 발급마다 증가합니다.

아무것도 폐기되지 않은 테스트 공급자의 KRL:

```
$ curl -s -D - -o var/bridge.krl http://127.0.0.1:28473/ssh/krl
HTTP/1.1 200 OK
Cache-Control: max-age=60
Content-Type: application/octet-stream
Etag: "c543d4dd9acedf716b34ea3af912a62f"
Date: Mon, 26 Oct 2026 11:21:59 GMT
Content-Length: 130

$ ssh-keygen -Q -l -f var/bridge.krl
# KRL version 0
# Generated at 20261026T122159
# Comment: go-authn/bridge http://127.0.0.1:28473
```

**ETag는 내용의 것입니다.** 읽는 쪽은 `If-None-Match`로 폴링하며, 보유한 발급이
여전히 제공되는 것인 동안 `304`를 받습니다. 내용은 최소 30분마다 바뀌므로 폴링하는
읽는 쪽은 만료 이후에도 사본을 유지하는 일이 없습니다.

```
$ curl -s -o /dev/null -H 'If-None-Match: "d2ab8a48f397a1f55bf3e8e513a4dea9"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl
304
```

**서명은 목록의 ETag에 대한 `If-Match`로 가져옵니다.** 그 사이에 다시 발급된 목록은
일치하지 않는 서명이 아니라 `412`로 응답합니다.

```
$ curl -s -o var/bridge.krl.sig -H 'If-Match: "d2ab8a48f397a1f55bf3e8e513a4dea9"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
200
$ curl -s -o /dev/null -H 'If-Match: "stale"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
412
```

`ssh-keygen`은 서명을 확인하며, 다른 네임스페이스의 서명은 거부합니다.

```
$ ssh-keygen -Y verify -f allowed -I bridge -n krl@go-authn.github.io -s bridge.krl.sig < bridge.krl
Good "krl@go-authn.github.io" signature for bridge with ED25519 key SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

여기서 `allowed`는 다음 줄입니다.
`bridge namespaces="krl@go-authn.github.io" <the CA key from /ssh/config>`.

15초 뒤에 발급된 CRL:

```
$ openssl crl -inform DER -in var/bridge.crl -noout -text
Certificate Revocation List (CRL):
    Version 2 (0x1)
    Signature Algorithm: ecdsa-with-SHA256
    Issuer: CN=go-authn bridge NFS client CA
    Last Update: Oct 26 11:22:15 2026 GMT
    Next Update: Oct 26 12:22:15 2026 GMT
    CRL extensions:
        X509v3 Authority Key Identifier: 
            AE:A8:A1:10:13:A3:B3:EA:FD:73:42:E2:71:56:D2:7D:DF:AA:4D:2C
        X509v3 CRL Number: 
            1793013735127
No Revoked Certificates.
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:44:02:20:79:e1:1f:d6:ae:86:01:01:41:d3:b2:2e:7d:20:
        13:3c:12:6c:7a:ee:3e:e9:e0:6f:33:28:af:ba:26:a4:06:5c:
        02:20:4a:b3:14:47:1c:23:14:f9:96:96:f0:78:40:28:2d:bd:
        c8:f3:37:75:24:fc:56:50:ba:3d:58:95:4e:b2:d7:dc
```

인증서는 만료될 때까지 목록에 남아 있습니다. 만료된 인증서는 나열되지 않아도 어디서나
거부됩니다.

### 누가 읽는가 {#who-reads-them}

- 일반 `sshd`, 또는 nginx와 다른 TLS 서버:
  [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})가 목록을 가져와 검증되는
  것만 보관하고, 서버가 읽는 곳에 기록하며, 목록이 만료되면 sshd에 대해 실패 시
  차단합니다.
- [go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)는
  목록을 스스로 가져와 검증하며, 현재 목록이 없는 동안에는 공급자의 인증서를
  거부합니다.

## Shared Signals {#shared-signals}

액세스 토큰이나 opkssh 인증서는 사용되는 곳에서 확인되며, 어떤 목록도 이를 지명할
수 없습니다. 그래서 공급자는 OpenID Shared Signals 송신기입니다. `DisablePerson`,
`RevokePerson`, `DisableIdP` 때, 요청한 모든 수신기를 위해 CAEP
**`session-revoked`** 이벤트(이벤트 시각 이전에 이 주체에게 발급된 모든 것이
무효)를 큐에 넣습니다.

```hcl
state { ... }            # required: a queue a restart empties loses revocations
ssf {}                   # event_retention = "192h" by default

client "fileshare-ssf" { # a receiver: client credentials, scope ssf
  secret_file  = "/etc/authn-bridge/fileshare-ssf.secret"
  ssf_receiver = true
  audience     = ["fileshare"]
}
```

```
$ curl -s http://127.0.0.1:28473/.well-known/ssf-configuration | jq .
{
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "delivery_methods_supported": [
    "urn:ietf:rfc:8936"
  ],
  "configuration_endpoint": "http://127.0.0.1:28473/ssf/streams",
  "status_endpoint": "http://127.0.0.1:28473/ssf/streams/status",
  "add_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:add",
  "remove_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:remove",
  "verification_endpoint": "http://127.0.0.1:28473/ssf/streams/verify",
  "spec_version": "1_0",
  "authorization_schemes": [
    {
      "spec_urn": "urn:ietf:rfc:6749"
    }
  ]
}
```

- **폴링 전달만** (RFC 8936): 수신기가 요청하며, 여기서 밖으로 연결하는 것은
  없습니다.
- 수신기는 비밀 값이 있는 `ssf_receiver` 클라이언트의 **클라이언트 자격 증명**
  그랜트로 얻은 `ssf` 스코프의 액세스 토큰으로 인증합니다. 자신의 스트림만 볼 수
  있고, 최대 열 개입니다.
- 이벤트는 ID 토큰 키로 서명한 SET(RFC 8417)이며 `exp`도 `sub`도 없습니다. 주체는
  기본적으로 **계정**, `acct:<username>`입니다. `sub`는 클라이언트마다 하나인
  pairwise일 수 있기 때문입니다. `ssf_subject_format = "iss_sub"`로 구성된 수신기는
  대신 발급자와 공개 `sub`를 받습니다.
- 비활성화된 기관은 그곳에서 공급자가 흔적을 가진 사람마다 하나의 이벤트이며,
  주체가 **테넌트**, 즉 기관의 엔티티 ID인 이벤트가 하나 있어 스코프와 함께 공급자가
  잊어버린 사람들까지 포함합니다.
- 스트림과 전달되지 않은 이벤트는 확인응답되거나 `event_retention`이 지날 때까지
  `state` 데이터베이스에 보관됩니다. 수신기가 오류로 보고한 이벤트는 최대 열 번까지
  다시 전달됩니다.

SSF 블록은 `state` 블록이 없으면 거부됩니다.

```
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```
