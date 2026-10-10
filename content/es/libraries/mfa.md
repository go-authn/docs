---
title: "mfa — suficientes factores, y cuáles"
linkTitle: "mfa"
weight: 10
description: "go-authn/mfa decide si respondieron suficientes factores, de suficientes clases distintas, y dice cuáles lo hicieron, sin ningún dispositivo y sin criptografía."
tags: [libraries, mfa, factors]
---

**¿Respondieron suficientes factores, de suficientes clases, y cuáles?** Aquí nada
llega a un dispositivo, y no hay criptografía: un `Factor` es cualquier cosa a la que
se pueda preguntar *¿está esta persona aquí, ahora?*, y este paquete decide qué suman
las respuestas.

```sh
go get github.com/go-authn/mfa@v0.5.0
```

No importa nada fuera de la biblioteca estándar.

## Dos de lo mismo son un solo factor {#two-of-the-same-thing-is-one-factor}

Una frase de contraseña y un código de recuperación son ambos cosas que la persona
*sabe*: quien averiguó una ha averiguado por lo general la otra en el mismo sitio. Así
que un factor dice qué prueba —`Knowledge`, `Possession` o `Inherence`— y la política
que significa lo que normalmente se entiende por *doble factor* es
`Policy{Count: 2, DistinctKinds: true}`. También se ofrece `Policy{Count: 2}` sola,
para quien llama y quiere a propósito dos claves de la misma clase; es una petición
distinta y se escribe de forma distinta.

Un factor cuyo `Kind()` es `Unknown` cuenta para el número satisfecho, nunca para las
clases: no se puede demostrar que difiera de nada.

## Ejemplo {#example}

```go
package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/go-authn/mfa"
)

// factor is the smallest mfa.Factor: a name, a kind, and an answer.
type factor struct {
	name string
	kind mfa.Kind
	err  error
}

func (f factor) Name() string                 { return f.name }
func (f factor) Kind() mfa.Kind               { return f.kind }
func (f factor) Verify(context.Context) error { return f.err }

func main() {
	ctx := context.Background()
	twoFactor := mfa.Policy{Count: 2, DistinctKinds: true}

	// Two things the person knows are one kind of proof.
	_, err := mfa.Verify(ctx, twoFactor,
		factor{"your passphrase", mfa.Knowledge, nil},
		factor{"a recovery code", mfa.Knowledge, nil},
	)
	fmt.Println(err)

	// A key that is not plugged in has not refused anybody.
	r, err := mfa.Verify(ctx, twoFactor,
		factor{"your passphrase", mfa.Knowledge, nil},
		factor{"your security key", mfa.Possession, mfa.Unavailable(errors.New("no key attached"))},
	)
	fmt.Println(err)
	fmt.Println(r.Answers[1].Unavailable())

	// The zero Policy is refused, not guessed at.
	_, err = mfa.Verify(ctx, mfa.Policy{}, factor{"your passphrase", mfa.Knowledge, nil})
	fmt.Println(err)
}
```

```
mfa: 2 factor(s) answered but only 1 kind(s) among them (knowledge); two of the same kind are not two factors
mfa: 2 factor(s) needed, 1 answered: your security key (possession): not available
true
mfa: a policy that requires 0 factors accepts anyone
```

Los factores reales están en otra parte: [totp]({{< relref "/libraries/totp.md" >}})
para un código de un teléfono, [keyfactor]({{< relref "/libraries/keyfactor.md" >}})
para una llave de seguridad.

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

`Verify` rechaza antes de preguntar a nadie:

| | por qué |
|---|---|
| una `Policy` cuyo `Count` es menor que uno | *a policy that requires 0 factors accepts anyone*. No hay política por defecto: cuánta prueba basta le corresponde a quien protege la cosa |
| menos factores ofrecidos que `Count` | la política no se puede cumplir, respondan lo que respondan |
| un factor cuyo `Kind()` está fuera de la enumeración | contado como una clase distinta, `Kind(42)` junto a una frase de contraseña pasaría por doble factor |
| **el mismo factor dos veces** | una frase de contraseña pasada dos veces satisfacía `Count: 2`. «El mismo» es el mismo tipo con los mismos valores, funciones incluidas: una función es la misma función cuando ejecuta el mismo código |

Y mantiene separadas tres cosas mientras pregunta:

- **No poder preguntar no es un rechazo.** Un factor que devuelve `ErrUnavailable`
  —envuelto por `mfa.Unavailable(err)`, que conserva el motivo— se notifica como tal
  (`Answer.Unavailable()`), y nunca pone fin a un intento, ni siquiera con
  `StopOnFirstFailure`.
- **Por defecto se pregunta a todos los factores**, de modo que a una persona se le
  puede decir *su llave respondió, su huella dactilar no* en un solo intento.
  `StopOnFirstFailure` está ahí cuando se quiere parar antes.
- **Un factor al que no se llegó no tiene entrada** en `Result.Answers`: notificarlo
  como fallido mandaría a alguien a buscar algo que no existe.

El `Result` se devuelve tanto si se cumplió la política como si no, con el error
nombrando lo que faltó en palabras con las que una persona puede actuar.

## Contra qué se comprueba {#what-it-is-checked-against}

Ningún juez externo: el módulo no contiene ningún protocolo con el que discrepar. Su
CI exige una **cobertura de sentencias del 100 %** en Linux, macOS y Windows, ejecuta
el detector de carreras, y ejecuta las pruebas en amd64, arm64, riscv64, loong64,
ppc64le, s390x, 386 y arm.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/mfa@v0.5.0](https://pkg.go.dev/github.com/go-authn/mfa@v0.5.0)
