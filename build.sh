#!/bin/env sh

echo
set -eu
sh -n tarb.sh

TMPDIR=build
BIN_LINE=$(awk '/^#binaries.tgz.base64/ { print NR + 1; exit 0; }' tarb.sh)
offline=false

[ .${1-} != .o ] || {
  shift
  offline=true
}

ver="$(head -n1 CHANGELOG)"
echo "$ver" | cut -d ' ' -f 2 > build/VERSION
sed -i"" "/^VERSION=/s/=.*/=\"$ver\"/" tarb.sh

mkdir -p $TMPDIR
[ -n "${1-}" ] || set -- arm arm64 x86 x64

for i in $*; do
  echo tarb-$i
  rm -rf $TMPDIR/$i 2>/dev/null || :
  mkdir -p $TMPDIR/$i
  $offline || {
    echo
    cd bin
    for j in $(grep -E "[_-]${i#x}-|[_-]$i-|-$i$" LINKS); do
      mv -f ${j##/} $TMPDIR/$i/ 2>/dev/null || :
      wget -N $j || { sleep 5; wget -N $j; } || mv -f $TMPDIR/$i/${j##/} ./ 2>/dev/null || :
    done
    cd ..
    echo
  }
  for b in $(echo bin/* | xargs -n1 | grep -E "[_-]${i#x}-|[_-]$i-|-$i$"); do
    c=${b##*/}
    c=${c%%-*}
    ln -f $b $TMPDIR/$i/$c 2>/dev/null || cp -f $b $TMPDIR/$i/$c
  done
  sed "s/BINLINENO/$BIN_LINE/" tarb.sh > $TMPDIR/tarb-$i
  tar -cf - -C $TMPDIR/$i . | gzip -9 | base64 >> $TMPDIR/tarb-$i
  sed -i"" "/^ABI=/s/=.*/=$i/" $TMPDIR/tarb-$i
  rm -rf $TMPDIR/$i
  echo
done

exit
