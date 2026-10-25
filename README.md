# docs

[![docs](https://github.com/go-authn/docs/actions/workflows/docs.yml/badge.svg)](https://github.com/go-authn/docs/actions/workflows/docs.yml)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-0A6E96?style=flat-square)](LICENSE)

**The go-authn documentation site**, published at
<https://go-authn.github.io/docs/>.

A [Hugo](https://gohugo.io/) site with the [tannevaled/hextra](https://github.com/tannevaled/hextra)
fork of the [Hextra](https://github.com/imfing/hextra) theme, built exactly like
[go-fileshare's documentation](https://github.com/go-fileshare/docs), with
go-authn's branding. The content is derived from the programs and libraries of
[go-authn](https://github.com/go-authn) and checked against their code: a
command's output on a page is what that release printed, and an example
compiles against the version its page names.

## Versions

go-fileshare's documentation is versioned by fileshare's minor version. go-authn
is not one program, so this site has a version of its own:

| Source | Published under |
| --- | --- |
| branch `main`, with `params.authn.version: v0.1.0` in `hugo.yaml` | `https://go-authn.github.io/docs/0.1/` |
| the newest version | also `https://go-authn.github.io/docs/latest/` |

`params.authn.programs` in `hugo.yaml` names the releases the pages describe
(authnd, authn-bridge, authn-revokd, sshcert), and the
[status page](content/en/status.md) lists them with the libraries'.

**A new minor version of any of those programs is a new minor version here**:
`v0.1.x` → `v0.2.0`, published under `0.2` beside `0.1`, and `latest` moves to
it. A patch release of a program updates the pages of the current version.
`https://go-authn.github.io/docs/` redirects to `latest/`. Each push to `main`
replaces the directory of the version it describes, and nothing else.

The version selector in the navbar lists every version from
`docs/versions.json` and opens the same page in the version chosen; if it is
not there, the same page in English, else that version's home.

## Languages

English is the default and sits at the root of each version
(`/docs/<version>/authnd/kerberos/`). Other languages go under their code
(`/docs/<version>/fr/authnd/kerberos/`), as on go-fileshare's site.

To add a language `<lang>`:

1. `content/<lang>/`: a translation of every page, with the same file names
   (that is how a page and its translation are paired). A translated heading
   keeps the English one's anchor as an explicit id, so the relrefs resolve in
   every language and links into a page keep their fragment.
2. `i18n/<lang>.yaml`: the site's own strings (copyright, version). French,
   Spanish, German, Simplified Chinese (`zh-cn`), Korean (`ko`) and Japanese
   (`ja`) are already there. Their search works with the theme's own FlexSearch
   tokenizer (one token per ideograph, kana or hangul syllable);
   `hasCJKLanguage: true` in `hugo.yaml` is for Hugo's word counts.
3. A `languages.<lang>` entry in `hugo.yaml`: label, `contentDir`, weight,
   `params.flag`, the translated `params.description`, and a `dateFormat`.
4. Its flag in `static/images/flags/`, from
   [lipis/flag-icons](https://github.com/lipis/flag-icons) (4x3, MIT).

Declare a language only with its content: a declared language without pages
is an empty entry in the switch.

## Layout

| Path | What |
| --- | --- |
| `content/en/` | the pages; `_index.md` is a section's own page, `weight` orders the sidebar |
| `i18n/<lang>.yaml` | the site's strings, beside the theme's |
| `static/images/flags/` | the language switch's flags (lipis/flag-icons, MIT) |
| `hugo.yaml` | `baseURL`, the documentation version and the releases it describes, the languages, the navbar (version › theme › search › GitHub), the brand mounts |
| `layouts/_partials/custom/version-select.html` | the version selector (reads `versions.json`) |
| `layouts/_partials/favicons.html` | the brand's favicons |
| `assets/css/custom.css` | the brand cyan as Hextra's primary colour, and the table headers |
| `themes/hextra` | submodule: [tannevaled/hextra](https://github.com/tannevaled/hextra), at the commit go-fileshare/docs uses (tag v0.16.0) |
| `branding` | submodule: [go-authn/brand](https://github.com/go-authn/brand), pinned to a release tag (the mark, its PNGs and ICO, and their LICENSE) |
| `scripts/publish-version.sh` | puts one build into a `gh-pages` checkout and rewrites `versions.json`, `latest` and the root redirect |

## Writing a page

Each page starts with a title, a one-sentence description, and tags:

```yaml
---
title: "A Kerberos realm"
linkTitle: "Kerberos"
weight: 50
description: "…"
tags: [authnd, kerberos]
---
```

Link to other pages with `{{< relref "/authnd/kerberos.md" >}}`: a broken
reference, or an anchor that does not exist, fails the build. A heading's
anchor is a URL other sites link to: when a heading's words change, keep the
old anchor with an explicit `{#id}`. A warning or a note is a
`{{< callout type="warning" >}}` (`error` for danger, `info` for a note), its
title in bold on the first line.

**A transcript is pasted, never written**: run the release the page describes
and copy what it printed. A hand-written transcript is how the landing page
came to show a startup line authnd never printed and a `check --kerberos` flag
that does not exist.

The page history at the foot of each page (created, modified, by whom) comes
from git: `themes/hextra/scripts/page-history.sh` writes
`data/pagehistory.json` before the build.

## Working locally

```sh
git clone --recurse-submodules https://github.com/go-authn/docs.git
cd docs
mkdir -p data && sh themes/hextra/scripts/page-history.sh > data/pagehistory.json
hugo server --baseURL http://localhost:1313/docs/0.1/
```

then open <http://localhost:1313/docs/0.1/>. Without a `versions.json` the
selector shows only the current version. Hugo 0.146 or later (CI uses the
version pinned in the workflow); no Python, no Node.

To upgrade the theme: `git -C themes/hextra checkout <tag>` (a tag of the
fork), commit the submodule, and run the production build of the workflow:
the fork's features are opt-in and its own CI does not build them, so this
site's `--panicOnWarning` build is their test.

## Publication

`.github/workflows/docs.yml`:

| Job | When | What |
| --- | --- | --- |
| `build` | pull requests, `main` | builds with `--baseURL …/docs/<version>/`, checks internal links and anchors (lychee, offline), uploads the site |
| `links` | pull requests, `main` | fetches every external URL the pages name |
| `deploy` | `main` | `scripts/publish-version.sh` into `gh-pages`, then a commit and a push; one deploy at a time |

GitHub Pages serves the `gh-pages` branch.

## Licence

BSD-3-Clause.
