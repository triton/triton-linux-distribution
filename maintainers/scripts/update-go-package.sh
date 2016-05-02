#!/usr/bin/env bash
set -e -o pipefail

if [ "0" -eq "$#" ]; then
  echo "Takes at least one argument, the list of packages to update." >&2
  exit 1
fi

# Setup the temporary storage area
TMPDIR=""
cleanup() {
  CODE="$?"
  echo "Cleaning up..." >&2
  if [ -n "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
  exit "$?"
}
trap cleanup EXIT ERR INT QUIT PIPE TERM
TMPDIR="$(mktemp -d)"

# Include the concurrent library
cd "$(readlink -f "$0" | xargs dirname)"
source concurrent.lib.sh
CONCURRENT_LOG_DIR="$TMPDIR/logs"

# Find the top git level
while ! [ -d "pkgs/top-level" ]; do
  cd ..
done
TOP_LEVEL="$(pwd)"

# Build all of the packages needed to run this script
echo "Building script dependencies..." >&2
exp='let pkgs = import ./. { };
in pkgs.buildEnv {
  name = "goUpdater";
  paths = with pkgs; [
    coreutils
    brotli
    gawk
    gnused
    gnugrep
    gnutar
    git
    nix
    ncurses
    util-linux_full
    curl
    findutils
  ];
}'
if ! nix-build --out-link $TMPDIR/nix-env -E "$exp"; then
  echo "Failed to build dependencies of this script" >&2
  exit 1
fi
export PATH="$(readlink -f "$TMPDIR/nix-env")/bin"

echo "Finding packages and all dependencies..." >&2
pkglist='[ '
for arg in "$@"; do
  pkglist+="\"$arg\" "
done
pkglist+=']'

nix-build --out-link $TMPDIR/nix-list --arg pkgList "$pkglist" -E '
  { pkgList }:
  let
    pkgs = (import ./. { });
    allBuildInputs = pkg: pkg.buildInputs
      ++ pkg.nativeBuildInputs
      ++ pkg.propagatedBuildInputs
      ++ pkg.propagatedNativeBuildInputs;
    listPkgAndDeps = pkg:
      if pkg ? goPackagePath then
        pkgs.lib.foldl
          (attr: dep: attr // listPkgAndDeps dep)
          { "${pkg.autoUpdatePath or pkg.goPackagePath}" = {
            inherit (pkg) rev;
            date = pkg.date or "nodate";
            autoUpdate = pkg.meta.autoUpdate or true;
            names = let
              names = pkgs.lib.attrNames (pkgs.lib.filterAttrs
              (n: d: d ? goPackagePath && d.goPackagePath == pkg.goPackagePath) pkgs.goPackages);
            in if pkgs.lib.length names > 0 then names else
              throw "Found no name for: ${pkg.goPackagePath}";
          }; }
          (allBuildInputs pkg)
      else { };
    combinedList = pkgs.lib.foldl
      (attr: n: attr // listPkgAndDeps pkgs.goPackages.${n})
      { }
      pkgList;
    pkgOutput = pkgs.lib.mapAttrsToList
      (n: d: "${n} ${d.rev} ${d.date} ${pkgs.lib.concatStringsSep "," d.names}\n")
      (pkgs.lib.filterAttrs (n: d: d.autoUpdate) combinedList);
  in
    pkgs.writeText "current-go-package-list" pkgOutput
'
cp $TMPDIR/nix-list $TMPDIR/list
rm $TMPDIR/nix-list


echo "Finding package repos..." >&2
build_redirect() {
  if echo "$1" | grep -q '\(github.com\|bitbucket.org\)'; then
    echo "$1" | sed 's,^[^h],https://\0,g'
    return 0
  fi

  local OUTPUT
  OUTPUT="$(curl -d "go-get=1" "$1")"
  echo "$OUTPUT" >&2
  local IMPORT
  IMPORT="$(echo "$OUTPUT" | grep 'go-import' || true)"
  if [ -n "$IMPORT" ]; then
    if echo "$IMPORT" | grep -q 'git'; then
      echo "$IMPORT" | awk '
        {
          match($0, /content="([^"]*)"/, array);
          split(array[1], import, " ");
          print import[3];
        }'
      return 0
    fi
    local REDIRECT
    REDIRECT="$(echo "$OUTPUT" | awk '{ if (/go-source/) { print $4 } }')"
    echo "$REDIRECT" >&2
    build_redirect "$REDIRECT"
  else
    echo "This site is unrecognized: $1" >&2
    exit 1
  fi
}
build_redirect_list() {
  local REDIRECT
  REDIRECT="$(build_redirect "$1")"
  exec 3<>"$TMPDIR/list.lock"
  flock -x 3
  sed -i "s,^[ \t]*$1 ,$1 $REDIRECT ,g" "$TMPDIR/list"
  exec 3>&-
}
ARGS=($(awk '{ print "- " $1 " build_redirect_list " $1; }' $TMPDIR/list))
concurrent "${ARGS[@]}"

echo "Fetching package revisions..." >&2

while read line; do
  pkg="$(echo "$line" | awk '{print $1}')"
  url="$(echo "$line" | awk '{print $2}')"

  mkdir -p "$TMPDIR/$pkg"
  cd "$TMPDIR/$pkg"
  git init >/dev/null
  git remote add origin "$url"

done < $TMPDIR/list

fetch_git() {
  cd $TMPDIR/$1
  git fetch --tags
}
ARGS=($(awk '{ print "- " $1 " fetch_git " $1; }' $TMPDIR/list))
concurrent "${ARGS[@]}"

hasUpdates=0
while read line; do
  pkg="$(echo "$line" | awk '{print $1}')"
  rev="$(echo "$line" | awk '{print $3}')"
  date="$(echo "$line" | awk '{print $4}')"
  names="$(echo "$line" | awk '{print $5}')"

  cd $TMPDIR/$pkg

  VERSION="$(git tag --sort "v:refname" | grep '\([0-9]\+\.\)\+[0-9]\+$' | grep -v "\(dev\|alpha\|beta\|rc\)" | tail -n 1 || true)"
  HEAD_DATE="$(git log origin/master -n 1 --date=short | awk '{ if (/Date/) { print $2 } }')"
  REV="$(git rev-parse origin/master)"
  DATE="$HEAD_DATE"
  if [ -n "$VERSION" ]; then
    VERSION_DATE="$(git log "$VERSION" -n 1 --date=short | awk '{ if (/Date/) { print $2 } }')"
    # Make sure we have had a release in the past 6 months
    if [ "$(expr $(date -d "$HEAD_DATE" +'%s') - $(date -d "$VERSION_DATE" +'%s'))" -lt "15000000" ]; then
      REV="$VERSION"
      DATE="$VERSION_DATE"
    fi
  fi

  if [ "$rev" != "$REV" ]; then
    hasUpdates=1
    echo -e "$pkg:\n  $date $rev\n  $DATE $REV" >&2
    if [ "$REV" = "$VERSION" ]; then
      DATE="nodate"
    fi
    echo "$pkg $REV $DATE $names" >> $TMPDIR/updates
  fi
done < $TMPDIR/list

if [ "$hasUpdates" -eq "0" ]; then
  echo "Up to date" >&2
  exit 0
fi

echo "Do these versions look reasonable? [y/N]" >&2
read answer
if [ "y" != "$answer" ] && [ "yes" != "$answer" ]; then
  exit 1
fi


echo "Generating package hashes..." >&2
generate_hash() {
  pkg="$1"
  rev="$2"
  date="$3"

  if [ "${#rev}" -eq "40" ]; then
    name="$(echo "$pkg" | awk -F/ '{ print $NF }')-$date"
  else
    name="$(echo "$pkg" | awk -F/ '{ print $NF }')-$rev"
  fi
  tmp="$TMPDIR/tars/$pkg"
  mkdir -p "$tmp"

  cd "$TMPDIR/$pkg"
  export TZ="UTC"
  git archive --format=tar --prefix="$name/" "$rev" | tar -xC "$tmp"
  
  mtime=$(find "$tmp/$name" -type f -print0 | xargs -0 -r stat -c '%Y' | sort -n | tail -n 1)
  echo -n "Clamping to date: " >&2
  date -d "@$mtime" --utc >&2

  cd "$tmp"
  tar --sort=name --owner=0 --group=0 --numeric-owner \
    --mode=go=rX,u+rw,a-s \
    --clamp-mtime --mtime=@$mtime \
    -c "$name" | brotli --quality 6 --output "$tmp/$name.tar.br"

  HASH="$(nix-prefetch-url "file://$tmp/$name.tar.br" 2>/dev/null)"
  rm -r "$tmp"
  rm -r "$TMPDIR/$pkg"

  exec 3<>"$TMPDIR/updates.lock"
  flock -x 3
  sed -i "s,^$pkg [^ ]*,\0 $HASH,g" "$TMPDIR/updates"
  exec 3>&-
}
ARGS=($(awk '{ print "- " $1 " generate_hash " $1 " " $2 " " $3; }' $TMPDIR/updates))
concurrent "${ARGS[@]}"

export TMPDIR
awk '
BEGIN {
  updateFile=ENVIRON["TMPDIR"] "/updates";
  while((getline line < updateFile) > 0) {
    split(line, splitLine);
    split(splitLine[5], names, ",");
    for (i in names) {
      exists[names[i]] = 1;
      revs[names[i]] = splitLine[2];
      hashes[names[i]] = splitLine[3];
      dates[names[i]] = splitLine[4];
    }
  }
  close(updateFile);
  currentPkg = "";
}
{
  # Find a package opening stmt
  if (/^  [^ ]*[ ]*=/) {
    currentPkg = $1;
    shouldSetDate = dates[$1] != "nodate" && /(buildFromGitHub|buildFromGoogle)/;
    shouldSetRev = 1;
    shouldSetHash = 1;
  }

  # Find the closing stmt and add any unadded fields
  if (/^  };/ && currentPkg != "") {
    if (exists[currentPkg]) {
      if (shouldSetDate) {
        print "    date = \"" dates[currentPkg] "\";";
      }
      if (shouldSetRev) {
        print "    rev = \"" revs[currentPkg] "\";";
      }
      if (shouldSetHash) {
        print "    sha256 = \"" hashes[currentPkg] "\";";
      }
    }
    currentPkg = "";
  }

  if (/^    [ ]*date[ ]*=[ ]*/ && exists[currentPkg]) {
    if (shouldSetDate) {
      print "    date = \"" dates[currentPkg] "\";";
    }
    shouldSetDate = 0;
  } else if (/^    [ ]*rev[ ]*=[ ]*/ && exists[currentPkg]) {
    if (shouldSetRev) {
      print "    rev = \"" revs[currentPkg] "\";";
    }
    shouldSetRev = 0;
  } else if (/^    [ ]*sha256[ ]*=[ ]*/ && exists[currentPkg]) {
    if (shouldSetHash) {
      print "    sha256 = \"" hashes[currentPkg] "\";";
    }
    shouldSetHash = 0;
  } else {
    if (/^    [ ]*inherit.*rev/) {
      shouldSetRev = 0;
    }
    if (/^    [ ]*inherit.*date/) {
      shouldSetDate = 0;
    }
    if (/^    [ ]*inherit.*sha256/) {
      shouldSetHash = 0;
    }
    if (/^    [ ]*inherit.*src/) {
      shouldSetRev = 0;
      shouldSetHash = 0;
    }
    print $0;
  }
}
' $TOP_LEVEL/pkgs/top-level/go-packages.nix >$TMPDIR/go-packages.nix
mv "$TMPDIR/go-packages.nix" "$TOP_LEVEL/pkgs/top-level/go-packages.nix"
