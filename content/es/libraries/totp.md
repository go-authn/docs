---
title: "totp — un código, una vez, y no un millón de intentos"
linkTitle: "totp"
weight: 20
description: "go-authn/totp comprueba códigos de un solo uso RFC 6238, rechaza un código ya usado, limita los intentos por secreto, y ofrece el resultado como factor de mfa."
tags: [bibliotecas, totp, factores]
---

**¿Es correcto este código de seis cifras, y se ha usado antes?** Contraseñas de
un solo uso basadas en el tiempo (RFC 6238); un `Verifier` que recuerda lo que un
servidor debe recordar, los códigos ya usados y los erróneos; y un factor que una
política de [mfa]({{< relref "/libraries/mfa.md" >}}) puede pedir.

```sh
go get github.com/go-authn/totp@v0.4.1
```

Su única dependencia es `go-authn/mfa`.

Los valores por defecto son los que da por hechos cualquier teléfono: seis cifras,
cada 30 segundos, HMAC-SHA1, un paso de tolerancia a cada lado. `Options` cambia
`Digits`, `Period`, `Algorithm` (`SHA1`, `SHA256`, `SHA512`) y `Window`.

## Ejemplo {#example}

```go
package main

import (
	"fmt"
	"time"

	"github.com/go-authn/totp"
)

func main() {
	secret, err := totp.ParseSecret("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
	if err != nil {
		panic(err)
	}
	now := time.Date(2026, 10, 10, 12, 0, 0, 0, time.UTC)
	o := totp.Options{Now: func() time.Time { return now }}

	code, _ := totp.At(secret, now, o) // what the phone shows
	fmt.Println(code)

	v := &totp.Verifier{Options: o}
	fmt.Println(v.Verify("dora", secret, []byte(code))) // accepted
	fmt.Println(v.Verify("dora", secret, []byte(code))) // the same code again
	fmt.Println(v.Verify("Dora", secret, []byte(code))) // another spelling, same secret

	// A secret shorter than 128 bits makes no code.
	short, _ := totp.ParseSecret("JBSWY3DPEHPK3PXP")
	_, err = totp.At(short, now, o)
	fmt.Println(err)
}
```

```
395621
<nil>
totp: that code has already been used
totp: that code has already been used
totp: a secret of 80 bits; RFC 4226 requires at least 128
```

En una política, el código se convierte en un factor de tipo `Possession`, junto a
lo que compruebe la contraseña:

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/mfa"
	"github.com/go-authn/totp"
)

// knows stands in for whatever checks the password.
type knows struct{}

func (knows) Name() string                 { return "your password" }
func (knows) Kind() mfa.Kind               { return mfa.Knowledge }
func (knows) Verify(context.Context) error { return nil }

func main() {
	ctx := context.Background()
	secret, _ := totp.ParseSecret("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
	verifier := &totp.Verifier{} // one per server, kept: it remembers used codes
	code := []byte("123456")     // what the person typed

	_, err := mfa.Verify(ctx, mfa.Policy{Count: 2, DistinctKinds: true},
		knows{},
		totp.Factor("dora", secret, code, verifier),
	)
	fmt.Println(err)
}
```

```
mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
```

Un código leído en voz alta por teléfono ya no es posesión; la clasificación es
aquello en lo que se basa `DistinctKinds`.

## Qué rechaza, y por qué {#what-it-refuses-and-why}

**Un código ya aceptado.** RFC 6238 §5.2: el verificador MUST NOT aceptar un
segundo intento de un OTP que ya tuvo éxito. El `totp.Verify` sin estado no puede
hacerlo — no guarda nada entre llamadas —, así que un servidor usa un
`*Verifier`, que rechaza con `ErrUsed` todos los pasos **hasta el último que
aceptó, incluido**: un código de hace treinta segundos sigue dentro de la ventana
por defecto.

**Un `Factor` sin `Verifier`.** `totp.Factor` con un `*Verifier` nil rechaza
todos los códigos, indicando que falta un Verifier. No se notifica como no
disponible, para que una política no pueda aprobar con los demás factores y
ocultar el error.

**Intentos, por secreto.** Un `Verifier` cuenta los códigos incorrectos por
**credencial** — el secreto, guardado solo como su SHA-256 —, no por nombre,
porque el nombre es la cadena que pase quien llama, y antes de la v0.3.0 `dora`,
`Dora` y `DORA` eran tres contadores para un mismo secreto.

| campo | por defecto | |
|---|---|---|
| `Throttle` | `DefaultThrottle` = 5 | códigos incorrectos seguidos antes de `ErrThrottled`; el código enviado entretanto no se mira, así que ni siquiera el correcto pasa |
| `Pause` | `DefaultPause` = 15 minutos | cuánto dura eso |
| `Lockout` | `DefaultLockout` = 100 | códigos incorrectos seguidos, por espaciados que estén, antes de `ErrLockedOut`, que solo levanta `Forget` (NIST SP 800-63B §5.2.2) |

Solo cuenta un código incorrecto; una reproducción, un código de longitud
incorrecta o un parámetro rechazado no acercan la pausa. Toda la comprobación se
hace bajo un mismo bloqueo, así que los intentos enviados en el mismo instante se
cuentan uno por uno. `ErrLockedOut` envuelve `ErrThrottled`, así que
`errors.Is(err, totp.ErrThrottled)` es verdadero para ambos rechazos, y
`errors.Is(err, totp.ErrLockedOut)` solo para el bloqueo.

**Parámetros que no pueden ser correctos:**

- un secreto de menos de 128 bits (`MinSecret` = 16 bytes, RFC 4226 R6), en
  `Generate`, `At`, `Verify` y `Verifier.Verify`. `ParseSecret` lo sigue leyendo:
  es un analizador;
- un período que no es un número entero de segundos, o inferior a un segundo;
- menos de 6 o más de 10 cifras (RFC 4226 §5.3);
- una ventana más ancha que `MaxWindow` = 10 pasos a cada lado. `0` significa el
  valor por defecto de un paso; `NoWindow` acepta solo el paso actual.

Se prueban todos los pasos de la ventana sin detenerse antes, y la comparación es
de tiempo constante. `ErrWrongCode` es el mismo error para «incorrecto» y para
«demasiado antiguo».

{{< callout type="warning" >}}
**El secreto es la credencial**

Quien lo tenga produce todos los códigos futuros. Ningún mensaje de error de aquí
cita un código ni un secreto, y `URI` — la cadena `otpauth://` que una aplicación
de autenticación lee de un código QR — contiene el secreto por construcción: es
para la persona que se registra, y para nadie más.
{{< /callout >}}

La memoria del `Verifier` es la de este proceso. Dos servidores detrás de un
balanceador de carga rechazan cada uno sus propias reproducciones y cuentan sus
propios intentos; un despliegue que necesite una única respuesta pone un
almacenamiento compartido detrás de la misma interfaz.

## Contra qué se comprueba {#what-it-is-checked-against}

- **pyotp**, una implementación en Python: 200 casos aleatorios con longitudes de
  secreto a partir de 16 bytes, de 6 a 10 cifras, cuatro períodos y los tres
  algoritmos (`differential_test.go`). La vía de pruebas de Linux, el detector de
  carreras y la vía de cobertura lo instalan, y allí `TOTP_REQUIRE_JUDGE` convierte
  la ausencia de pyotp en un fallo en lugar de una omisión.
- **El apéndice B del RFC 6238**, los seis instantes y los tres algoritmos, y
  **el apéndice D del RFC 4226**, contadores del 0 al 9.
- Cada número de cifras sobre 1000 pasos por algoritmo, contra el §5.3 del
  RFC 4226 recalculado con precisión arbitraria.

La vía de cobertura falla por debajo del 95 % (su norma declarada es el 100 %), y
las pruebas se ejecutan en ocho arquitecturas.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/totp@v0.4.1](https://pkg.go.dev/github.com/go-authn/totp@v0.4.1)
