#!/bin/sh
# Publish one documentation build into a checkout of the gh-pages branch.
#
#   scripts/publish-version.sh <version> <built site> <gh-pages checkout>
#
# <version> is the documentation version the build describes, MAJOR.MINOR
# (0.1), from params.authn.version in hugo.yaml. The build replaces
# <gh-pages>/<version>/ and nothing else: every other version already
# published is kept as it is. Then, from the directories present:
#
#   versions.json   rewritten in mike's format ({version, title, aliases}),
#                   newest first; the version selector reads it;
#   latest          a symbolic link to the newest version (as mike made it);
#   index.html      the root, redirecting to latest/ (as mike made it).
#
# Needs jq and rsync. Commits nothing: the workflow does.
set -eu

die() { echo "publish-version.sh: $*" >&2; exit 1; }

[ $# -eq 3 ] || die "usage: $0 <version> <built site> <gh-pages checkout>"
version=$1
site=$2
pages=$3
label='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

printf '%s\n' "$version" | grep -Eq "$label" || die "version must be MAJOR.MINOR (0.22), not \"$version\""
[ -f "$site/index.html" ] || die "$site/index.html is missing: build the site first"
[ -d "$pages" ] || die "$pages is not a directory"
command -v jq >/dev/null || die "jq is required"
command -v rsync >/dev/null || die "rsync is required"

# The version's own directory, replaced whole. A real directory: if it was a
# link (an alias), the link goes, not what it pointed to.
[ -L "$pages/$version" ] && rm "$pages/$version"
mkdir -p "$pages/$version"
rsync -a --delete "$site/" "$pages/$version/"

# The versions present, newest first (0.22 before 0.4: compared as numbers).
versions=$(cd "$pages" && for d in *; do
	[ -d "$d" ] && [ ! -L "$d" ] && printf '%s\n' "$d" | grep -Eq "$label" && printf '%s\n' "$d"
done | sort -t. -k1,1nr -k2,2nr)
latest=$(printf '%s\n' "$versions" | sed -n 1p)

# versions.json: the newest carries the alias "latest".
for v in $versions; do
	if [ "$v" = "$latest" ]; then
		jq -n --arg v "$v" '{version: $v, title: $v, aliases: ["latest"]}'
	else
		jq -n --arg v "$v" '{version: $v, title: $v, aliases: []}'
	fi
done | jq -s . >"$pages/versions.json.tmp"
mv "$pages/versions.json.tmp" "$pages/versions.json"

# latest -> the newest version, and the root redirect.
rm -rf "$pages/latest"
ln -s "$latest" "$pages/latest"
cat >"$pages/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Redirecting</title>
  <noscript>
    <meta http-equiv="refresh" content="1; url=latest/" />
  </noscript>
  <script>
    window.location.replace(
      "latest/" + window.location.search + window.location.hash
    );
  </script>
</head>
<body>
  Redirecting to <a href="latest/">latest/</a>...
</body>
</html>
EOF
touch "$pages/.nojekyll"

echo "published $version; latest is $latest; versions: $(jq -r '[.[].version] | join(", ")' "$pages/versions.json")"
