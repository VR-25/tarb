#!/system/bin/sh
# Tarb, a backup solution for Android
# VR-25 @ GitHub
# GPLv3+


allow_apk_sideload() {
  settings put secure install_non_market_apps $1
  settings put global verifier_verify_adb_installs $2
  settings put global package_verifier_enable $2
}


app() {
  local i=
  mkdir -p $BKP_DIR/$1/${3:-apk}
  : > $TMP
  for i in $2/*.${3:-apk}; do
    [ -f $i ] || return 0
    cp_uf $i $BKP_DIR/$1/${3:-apk}/${i##*/}
    echo ${i##*/} >> $TMP
  done
  for i in $BKP_DIR/$1/${3:-apk}/*.${3:-apk}; do
    grep -q ${i##*/} $TMP || rm -f $i
  done
}


app_r() {
  local apk=
  local session=
  [ -d $BKP_DIR/$1/apk ] && echo "  app" || return 0
  session=$(su -c pm install-create -r -t -i com.android.vending </dev/null | grep -Eo '[0-9]+')
  for apk in $BKP_DIR/$1/apk/*.apk; do
    [ -f $apk ] || return 0
    cat $apk | pm install-write -S $(stat -c %s $apk) $session ${apk##*/} - || {
      pm install-abandon $session </dev/null
      return 0
    }
  done
  pm install-commit $session </dev/null
}


backup() {
  if flag c; then
    shift
    cust $*
  else
    lspkg "$@" > $_LINES
    bkp
    rmdir $BKP_DIR/*/* 2>/dev/null || :
  fi
}


bkp() {

  local line=

  while IFS= read line; do

    [ -n "$line" ] || continue
    echo ${line% *}
    mkdir -p $BKP_DIR/${line% *}

    ! match ${line#* } "/*" && touch $BKP_DIR/${line% *}/.system \
      || rm $BKP_DIR/${line% *}/.system 2>/dev/null || :

    reset_pass

    ! flag a || app $line
    ! flag d || data $line
    ! flag e || ext $line

    ! flag d || {
      ! pgrep -f zygote >/dev/null || {
        echo "  runtime_perms"
        /system/bin/dumpsys package ${line% *} \
          | grep 'android.permission.*granted=true' \
          | sed -E 's/ +//; s/:.*//' > $BKP_DIR/${line% *}/runtime_perms
      }

      [ ! -f $SSAID ] || {
        grep \"${line% *}\" $SSAID > $BKP_DIR/${line% *}/ssaid \
          && echo "  ssaid" \
          || rm $BKP_DIR/${line% *}/ssaid
      } 2>/dev/null || :

    } || :

    echo
  done < $_LINES
}


bkp_r() {

  local line=
  local perm=

  # ensure these packages are restored first, to prevent issues with dependent packages
  for line in com.google.android.gms trichromelibrary; do
    ! grep $line $_LINES > ${_LINES}.tmp || {
      grep -v $line $_LINES >> ${_LINES}.tmp || :
      mv -f ${_LINES}.tmp $_LINES
    }
  done

  while IFS= read line; do

    [ -n "$line" ] || continue
    echo ${line% *}
    reset_pass

    ! flag a || app_r $line
    ! flag d || data_r $line
    ! flag e || ext_r $line

    ! flag d || {

      # restore runtime perms
      [ ! -f $BKP_DIR/${line% *}/runtime_perms ] || {
        echo "  runtime_perms"
        while IFS= read perm; do
          [ -z "$perm" ] || pm grant ${line% *} $perm </dev/null >/dev/null 2>&1
        done < $BKP_DIR/${line% *}/runtime_perms
      }

      # restore ssaid
      if [ -f $SSAID ] && [ -f $BKP_DIR/${line% *}/ssaid ]; then
        echo "  ssaid"
        (set -- $(cat $BKP_DIR/${line% *}/ssaid)
        name=$(stat -c %u /mnt/expand/*/user/0/${line% *} /data/data/${line% *} 2>/dev/null || :)
        name=name=\"$name\"
        sed "/\"${line% *}\"/d; /<\/settings>/d; /^$/d" $SSAID > $TMPDIR/ssaid
        echo "$@" | sed "s/$3/$name/" >> $TMPDIR/ssaid
        echo "</settings>" >> $TMPDIR/ssaid
        cat $TMPDIR/ssaid > $SSAID)
      fi

    } || :

    echo
  done < $_LINES
}


clean() {
  local pkg=
  lspkg . > $_LINES
  for pkg in $BKP_DIR/*; do
    [ -d $pkg ] && [ ! -f $pkg/.system ] && match $pkg "*/.vr25/tarb/*" \
      && ! grep -q "^${pkg##*/} " $_LINES && echo ${pkg##*/} && rm -rf $pkg || :
  done
}


sizes_match() {
  local c1=
  local c2=
  [ ! -f $2 ] && c1=c1 || {
    c1=$(stat -c %s $1)
    c2=$(stat -c %s $2)
  }
  [ .$c1 = .$c2 ]
}


cp_uf() {
  sizes_match "$@" || {
    echo "  ${1##*/}"
    cp -f "$@"
  }
}


crypt() {
  local args="-pbkdf2 -iter 200001 -aes-256-ctr"
  if [ $1 = -e ]; then
    if $ENCRYPT; then
      crypt_pass
      TPASS="$TPASS" openssl enc -out ${2}.enc $args -pass env:TPASS
    else
      cat - > $2
    fi
  elif [ $1 = -d ]; then
    case $2 in
      *.enc) crypt_pass -d; TPASS="$TPASS" openssl enc -d -in $2 $args -pass env:TPASS;;
      *.zst) cat $2;;
    esac
  fi
}


crypt_pass() {
  local pass=
  [ -n "${TPASS-}" ] || {
    while :; do
      printf "    Password: "
      read TPASS
      [ "${1-}" = -d ] && break || {
        printf "    Confirm: "
        read pass
        [ "$pass" != "$TPASS" ] && echo "    Passwords mismatch!" || {
          match "$pass" "?*" && break || echo "    Nice try, but a null password won't work."
        }
      }
    done
    printf "    Use the same password for other backups? (Y/n) "
    read pass
    match "$pass" "*[nN]*" && samepass=false || samepass=true
    echo "TPASS=\"$TPASS\"; samepass=$samepass" > $PASSF
  } <&3 >&4
}


cust() {
  local name=
  local path=
  for path in $*; do
    [ -e $path ] || continue
    echo $path
    name=$(echo $path | sed 's|/|%|g')
    reset_pass
    _tar -cf $BKP_DIR/${name}.tar.zst $path
  done
}


cust_r() {
  local bkp=
  set -f
  set -- $(echo "$@" | sed 's|/|%|g')
  set +f
  for bkp in $*; do
    for bkp in $BKP_DIR/*$bkp*; do
      [ -f $bkp ] || continue
      echo $bkp | sed "s|%|/|g; s|$BKP_DIR/||; s/.tar.zst.*//"
      reset_pass
      _tar -xf $bkp -C /
    done
  done
}


data() {

  local path=/mnt/expand/*/user/0/$1
  [ -d $path ] || path=/data/data/$1
  echo "  data"
  pause $1
  _tar -cf $BKP_DIR/$1/data.tar.zst -C $path .

  flag D || {
    path=/mnt/expand/*/user_de/0/$1
    [ -d $path ] || path=/data/user_de/0/$1
    [ ! -d $path ] || {
      echo "  data_de"
      _tar -cf $BKP_DIR/$1/data_de.tar.zst -C $path .
    }
  }
  resume $1
}


data_r() {

  local i=
  local ug=
  local path=/mnt/expand/*/user/0/$1
  local path_de=/mnt/expand/*/user_de/0/$1

  [ -d $path ] || path=/data/data/$1
  [ -d $path_de ] || path_de=/data/user_de/0/$1

  ug=$(stat -c %u:%g $path 2>/dev/null) || return 0
  _stop $1

  [ ! -f $BKP_DIR/$1/data.tar.zst* ] || {
    echo "  data"
    _tar -xf $BKP_DIR/$1/data.tar.zst* -C $path
    ln -s $(lspkg ${1}- | cut -d' ' -f2)/lib/* $path/lib 2>/dev/null || :
  }

  flag D || {
    [ ! -f $BKP_DIR/$1/data_de.tar.zst* ] || {
      echo "  data_de"
      _tar -xf $BKP_DIR/$1/data_de.tar.zst* -C $path_de
    }
  }

  for i in $path $(flag D || echo $path_de); do
    chown -R $ug $i
    /system/bin/restorecon -DFR $i
  done >/dev/null 2>&1 || :
}


delete() {
  local i=
  set -f
  set -- $(echo "$@" | sed 's|/|%|g; s/,/|/g')
  set +f
  ls -1 $BKP_DIR | grep -E "${*:-linuxIsAwesome}" | sed "s|^|$BKP_DIR/|" | \
    while read i; do
      [ -e $i ] || continue
      echo ${i##*/} | sed 's|%|/|g'
      rm -rf $i
    done
}


echo_run() {
  echo "${2-}$1"
  eval "$1"
}


ext() {

  pause $1

  [ ! -d /sdcard/Android/data/$1 ] || {
    echo "  data_ext"
    _tar -cf $BKP_DIR/$1/data_ext.tar.zst -C /sdcard/Android/data/$1 .
  }

  if [ -d /sdcard/Android/media/$1 ] && ! flag M; then
    echo "  media"
    _tar -cf $BKP_DIR/$1/media.tar.zst -C /sdcard/Android/media/$1 .
  fi

  if [ -d /sdcard/Android/obb/$1 ] && ! flag O; then
    app $1 /sdcard/Android/obb/$1 obb
  fi

  resume $1
}


ext_r() {

  local i=
  local ug=
  ug=$(stat -c %u:%g /mnt/expand/*/user/0/$1 /data/data/$1 2>/dev/null || :) || return 0
  _stop $1

  [ ! -f $BKP_DIR/$1/data_ext.tar.zst* ] || {
    echo "  data_ext"
    _tar -xf $BKP_DIR/$1/data_ext.tar.zst* -C /sdcard/Android/data/$1
  }

  if [ -f $BKP_DIR/$1/media.tar.zst* ] && ! flag M; then
    echo "  media"
    _tar -xf $BKP_DIR/$1/media.tar.zst* -C /sdcard/Android/media/$1
  fi

  if [ -d $BKP_DIR/$1/obb ] && ! flag O; then
    echo "  obb"
    mv -f /sdcard/Android/obb/$1 /sdcard/Android/obb/${1}.old 2>/dev/null
    if cp -r $BKP_DIR/$1/obb /sdcard/Android/obb/$1; then
      rm -rf /sdcard/Android/obb/${1}.old 2>/dev/null
    else
      mv -f /sdcard/Android/obb/${1}.old /sdcard/Android/obb/$1 2>/dev/null
    fi
  fi || :

  for i in /data/media/0/Android/*/$1 /mnt/expand/*/media/0/Android/*/$1; do
    chown -R $ug $i
    chmod -R 0777 $i
    /system/bin/restorecon -DFR $i
  done >/dev/null 2>&1 || :
}


flag() {
  match $FLAGS "*$1*"
}



help() {
  cat << EOF | more
Tarb, a backup solution for Android
Copyright (C) $1, $AUTHOR
License: GPLv3+
$2


$DESCRIPTION

All required binaries/executables are included: busybox for general tools, openssl for encryption, tar for archiving, and zstd for compression.

**Works in recovery mode as well.**


NOTICE

This program, along with all included binaries (busybox, openssl, tar and zstd), are free and open source software.
They are provided as-is, and come with absolutely no warranties.
One can do whatever they want with those programs, as long as they follow the terms of each license.

The binaries are provided by @osm0sis and @Zackptg5 -- credits to them, other contributors, and original authors.
Refer to the sources below for more information:

https://github.com/Magisk-Modules-Repo/busybox-ndk/
https://github.com/Zackptg5/Cross-Compiled-Binaries-Android/


Usage

  $0

  $0 -<c|o|v>

  $0 -[br][flags] ['regex,regex,...'] [+ 'regex,regex,...'] [-p=['password']] [-X 'pattern,pattern,...']

  $0 -d 'regex,regex,...'

  $0 -l ['regex,regex,...']

  $0 -ll

  $0 -x ['command...']


Options

  none   print this help text

  -b   backup or refresh backups

  -c   clean backup folder (uninstalled apps)

  -d   delete backups matching pattern...

  -l   list backups (includes install status)

  -m   install as a Magisk module and make /data/t available for recovery

  -o   run android's bg-dexopt-job to optimize app runtime performance

  -p=['password']   encrypt/decrypt backups; if the password is not provided, tarb asks for it when required; for restore, even if -p= is not provided, tarb will still ask for the password to decrypt encrypted backups; an alternative to -p=['password'] is having an environment variable TPASS='password'

  -r   restore backup

  -u   check for update

  -v   view last verbose log

  -x   run internal functions and/or custom commands (mainly for debugging)

  -X   additional, comma-separated patterns to exclude (based on tar's --exclude='pattern' option); this must always be the last option in order


Flags

  Defaults: ad (-b[#] == -bda[#], -r[#] == -rda[#])

  #   zstd compression level (default: 1)

  a   app (apks and split apks)

  c   custom (paths)

  d   data (user and user_de)

  D   exclude device encrypted data (data_de, from /data/user_de/)

  e   external data (/sdcard/Android/*/\$pkg/)

  l   list backups with additional info

  m   backup/restore Magisk data as well (/data/adb/)

  M   exclude Android/media/

  n   with -r: restore only apps that are not already installed (can be filtered with regex); with -b: backup only new and updated apps

  o   optimize apps after restore (bg-dexopt-job)

  O   exclude Android/obb/

  s   backup/restore generic system settings

  u   download and install update automatically (-uu)

  x   reverse pattern matching (exclude), for -b and -r only


Examples

  Backup

    Files/folders
      -b /data/misc

    All user and updated system apps + data
      -b .

    With compression level 10
      -b10 .

    All of the above + generic system settings + Magisk data
      -badsm10 .

    + data of regular system apps matching patterns
      -badsm10 . + bromite,etar

    Exclude device encrypted data
      -badsm10D . + bromite,etar

    Include external data; exclude Android/media/ and Android/obb/
      -badsm10DeMO . + bromite,etar

    Exclude cache and randomFile directories/files globally
      -badsm10DeMO . + bromite,etar -X '*[cC]ache*,randomFile'

    Encrypt

      -badsm10DeMO -p='strongpassword' . + bromite,etar -X '*[cC]ache*'

      Alternative to -p='strongpassword'
        TPASS='password' tarb -badsm10DeMO . + bromite,etar -X '*[cC]ache*'

  Restore

    Files/folders
      -r /data/system/storage.xml

    Matching apps with data + external data, Magisk data and system settings
      -radems faceboo,whatsa,instagr

    External data only, but without obb
      -reO somegame1,coolgame

    Bromite browser, if it's not already installed
      -rn bromite$

  List backups

    With filtering
      -l ['regex']

    Not installed
      -l N

    Installed
      -l I

    Detailed backup sizes
      -ll


Notes/tips

  Tarb copies itself to the backup directory, as needed (filename: ".tarb" (hidden)).
  Currently using $BKP_DIR/.

  It uses egrep's regular expressions syntax.
  The ^ and $ characters match the beggining and end of a line, respectively. One can use those for exact matching.
  For instance, "com.google.android.gm" matches "Gmail", "Google Play Services", and more. To match only "Gmail", one can use "com.google.android.gm$".
  Another example: MiXplorer file manager addon package names all contain "com.mixplorer." If one wants to restore the file manager without addons, they must use a pattern that matches only that (e.g., "com.mixplorer$").

  The order of flags is irrelevant.
  Regarding options, -X must always be the last, and -p= can be placed in any order, except first.

  -X uses the syntax of tar's --exclude='pattern' option -- but unlike tar, it also supports a comma-separated list of patterns.

  Only user and updated system apps are considered for backups.
  Regular system apps can only be backed up manually -- i.e., with "-b <path...>" or "-b ... + 'string'", as in the aforementioned examples.

  To ensure maximum compatibility with recovery environments, most information is gathered directly from filesystems (no front-ends used).

  Recovery mode support depends on whether the recovery can mount and decrypt the target storage devices (including adopted storage).
  System settings and app runtime permissions cannot be backed up from recovery.

  Each app is paused before data backup, and stopped prior to restore.
  For obvious reasons, this does not apply to terminal emulators.

  For compression, "zstd -1T0" is used.
  The compression level can be overridden with a flag, as in "tarb -b10 faceboo".

  AES-256 encryption is supported (openssl -pbkdf2 -iter 200001 -aes-256-ctr).

  APKs and OBB files are not compressed nor encrypted, except if backed up as regular files (e.g., "tarb -b /sdcard/Android/obb/my.game.obb").

  Some files/folders considered unnecessary (and even problematic), are excluded from backups. Refer to the source code for details.
  APK and OBB backups are not overwritten if sizes match.
  Those measures, along with compression, greatly minimize flash storage wear.

  The backup folder is /sdcard/.vr25/tarb/ by default. It's used only if .vr25/tarb/ is not found on external storage (i.e., OTG drive or sdcard).
  One can force an alternate path, by setting the environment variable BKPDIR.

  If a backup/restore fails, the old data is preserved.

  When reporting issues, one should provide as many details as possible, along with a copy of $TMPDIR/log.

  NO WARRANTIES, use at your own risk!
EOF
}



list() {
  local i=
  local size=
  local total=
  if match $1 -ll; then
    for i in $BKP_DIR/*; do
      printf "%s " ${i##*/} | sed 's|%|/|g; s/\.tar.zst.*//; s/^_//'
      du -sh $i | cut -f1
      [ -f $i ] || {
        for i in $i/*; do
          printf "  %s " ${i##*/}
          du -sh $i | cut -f1
        done
      }
      echo
    done
    size=$(du -hs $BKP_DIR | cut -f1)
    total=$(ls -1 $BKP_DIR | wc -l)
    echo "Total: $total entries, $size"
  else
    ls -1 $BKP_DIR | sed 's|%|/|g; s/\.tar.zst.*//; s/^_//' | \
      while read i; do
        match $i "[_%]*" && echo $i || {
          if test -d /data/data/$i || test -d /mnt/expand/*/user/0/$i; then
            echo I $i
          else
            echo N $i
          fi
        }
      done | sort | grep -E "${2:-.}"
  fi
}


lspkg() {

  local b=true
  local extra=
  local i=
  local j=
  local line=
  local n=true
  local r=true
  local regex=
  local x=v

  match $1 "-r*" || r=false
  match $1 "-*[nx]*" || x=
  match $1 "-*n*" || n=false
  match $1 "-b*" || b=false
  ! match $1 "-*" || shift

  # set regex
  if $n; then
    if $b; then
      lspkg . > $TMP
      regex=linuxIsAwesome
      while IFS= read line; do
        [ -n "$line" ] \
        && sizes_match ${line#* }/base.apk $BKP_DIR/${line% *}/apk/base.apk \
        && regex="$regex|${line% *}" || :
      done < $TMP
    else
      regex="$(lspkg . | sed 's/ .*//' | xargs | sed 's/ /|/g')"
    fi
  else
    extra="$(echo "$@" | sed -n '/+ /p' | sed 's/.*+ //; s/,/|/g; s/\$/ /g')"
    extra="$(ls -1 /data/data/ /data/user_de/0/ | sed 's|.*/||; s|$| linuxIsAwesome|' | sort -u  | grep -E "$extra")" 2>/dev/null || extra=
    regex="$(echo "$@" | sed 's/ + .*//; s/+ .*//; s/,/|/g; s/\$/ /g')"
  fi

  if $r; then
    ls -1d $BKP_DIR/*/ | sed 's|/$||; s|.*/|| ;/^_settings_.*/d; s/$/ linuxIsAwesome/'
  else
    for i in $({ find /data/app/ /mnt/expand/*/app/ -type f -name base.apk 2>/dev/null || :; } | sed 's|/base.apk||'); do
      j=${i##*/}
      j=${j%%-*}
      echo "$j $i"
    done
  fi | { grep -E$x "${regex:-linuxIsAwesome}" | grep -v '^vmdl.*\.tmp$'; } || :

  [ -z "$extra" ] || echo "$extra"

  if $b && [ "$regex" = . ] && [ -z "$extra" ]; then
    for i in $BKP_DIR/*/.system; do
      [ -f $i ] || continue
      i=${i%/.system}
      i=${i##*/}
      if [ -d /data/data/$i ] || [ -d /data/user/0/$i ]; then
        echo $i linuxIsAwesome
      fi
    done
  fi
}


match() {
  eval "case "${1:-\'\'}" in ${2:-\'\'}) return 0;; esac; false"
}


match_term() {
  match $1 "*terminal*|*termux*|*nhterm*"
}


optimize() {
  if pgrep -f bg-dexopt-job >/dev/null; then
    echo "Already running"
  else
    echo "Optimizing apps (may take a while)..."
    time /system/bin/cmd package bg-dexopt-job
  fi
}

pause() {
  match_term $1 || killall -STOP $1 >/dev/null 2>&1 || :
}


pm() {
  /system/bin/cmd package "$@" | sed '/Success/d'
}


reset_pass() {
  . $PASSF
  ${samepass:-true} || { TPASS=; : > $PASSF; }
}


restore() {
  local one=
  local regex=
  if flag c; then
    shift
    cust_r "$@"
  else
    if flag n; then
      one=$1
      shift
      regex="$(echo "$@" | sed 's/,/|/g')"
      lspkg $one | grep -E "${regex:-.}" > $_LINES
    else
      lspkg "$@" > $_LINES
    fi
    ! flag a || allow_apk_sideload 1 0
    bkp_r
    ! flag a || allow_apk_sideload 0 1
  fi
}


resume() {
  match_term $1 || killall -CONT $1 >/dev/null 2>&1 || :
}


settings() {
  /system/bin/settings "$@"
}


_settings() {

  local flag=
  local namespace=
  local path=

  for flag in --base --lineage --cm; do
    path=$BKP_DIR/_settings_${flag#--}
    flag=${flag%--base}
    rm -rf $path 2>/dev/null || :
    mkdir -p $path
    for namespace in global secure system; do
      settings list $flag $namespace | tee $path/$namespace > /dev/null \
        && echo settings ${flag#--} $namespace \
        || rm $path/$namespace
    done
    rmdir $path || touch $path/.system
  done 2>/dev/null || :

  sed -i /inputmethod/d $BKP_DIR/_settings_base/secure
}


_settings_r() {

  local flag=
  local key=
  local line=
  local namespace=
  local path=
  local value=

  for path in $BKP_DIR/_settings_*; do
    flag=--${path##*_}
    flag=${flag#--base}
    for namespace in $path/*; do
      namespace=${namespace##*/}
      settings list $flag $namespace | tee $TMP >/dev/null || continue
      echo settings ${flag#--} $namespace
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        key="${line%%=*}"
        value="$(grep "^$key=" $path/$namespace)" && value="${value#*=}" || continue
        settings put $flag $namespace "$key" "$value" </dev/null
      done < $TMP
    done 2>/dev/null || :
  done
}


_stop() {
  match_term $1 || killall $1 >/dev/null 2>&1 || :
}


_tar() {

  local f=$2
  local fmv=$(echo $f*)
  local pkg=${2%/*}/

  set -- $(echo "$@" | sed "s| $2 | - |")
  : > $TMPDIR/tar_log
  . $PASSF

  if match $1 "-c*"; then
    mv -f $fmv ${fmv}.old 2>/dev/null || :
    { tar --acls --xattrs -X $X -p "$@" 2>$TMPDIR/tar_log | zstd -${COMP_LEVEL}cT0 | crypt -e $f; } \
      && { rm ${fmv}.old 2>/dev/null || :; } \
      || mv -f ${fmv}.old $fmv 2>/dev/null || :
  else
    if flag c; then
      crypt -d $f | zstd -cdkT0 | tar --acls --xattrs -X $X -p "$@" 2>$TMPDIR/tar_log
    else
      mv -f $4 ${4}.old 2>/dev/null || :
      mkdir -p $4
      { crypt -d $f | zstd -cdkT0 | tar --acls --xattrs -X $X -p "$@" 2>$TMPDIR/tar_log; } \
        && { rm -rf ${4}.old 2>/dev/null || :; } \
        || mv -f ${4}.old $4 2>/dev/null || :
    fi
  fi
  grep -Eiv 'leading|not available|Warning' $TMPDIR/tar_log 2>/dev/null || :
}


update() {

  local ans=
  local path=

  printf "Checking for update..."
  [ 0$(_wget VERSION 2>/dev/null) -gt 0${VERSION#* } ] || {
    printf "\nNo update available\n"
    return 0
  }

  printf "\n\n"
  _wget CHANGELOG 2>/dev/null
  echo

  [ .${1-} = .-uu ] || {
    printf "Download and upgrade now? (Y/n) "
    read -n 1 ans
    ! match "$ans" "[nN]" && echo || { echo; return 0; }
  }

  _wget tarb-$ABI $TMPDIR/update
  path=$(realpath $0)
  printf "\nUpgrading...\n"

  case $path in
    /data/adb/modules/*) echo_run "sh $TMPDIR/update -x set -- -m >/dev/null" "  ";;
    *) echo_run "cat $TMPDIR/update > $path" "  ";;
  esac

  echo_run "rm $TMPDIR/update" "  "
  echo Done
}


_wget() {
  [ ! -f ${2:-//} ] || rm $2
  PATH=${PATH#*:} $BIN_DIR/wget -O ${2:--} --no-check-certificate \
    $([ $1 = CHANGELOG ] \
      && echo https://raw.githubusercontent.com/vr-25/tarb/main/CHANGELOG \
      || echo https://github.com/vr-25/tarb/releases/latest/download/$1)
}


echo

ABI=
SSAID=/data/system/users/0/settings_ssaid.xml
BKP_DIR=.vr25/tarb
export TMPDIR=/dev/$BKP_DIR
BKP_DIR="${BKPDIR:-/usb-otg/$BKP_DIR /external_sd/$BKP_DIR /mnt/media_rw/*/$BKP_DIR /sdcard/$BKP_DIR}"
BIN_DIR=$TMPDIR/bin
BIN_LINE=BINLINENO
TMP=$TMPDIR/TMP
_LINES=$TMPDIR/LINES
X=$TMPDIR/X
CUST_EXEC=/data/adb/vr25/bin
PASSF=$TMPDIR/.pass

AUTHOR="VR-25 @ GitHub"
COPYRIGHT_YEAR=2022
DESCRIPTION="Backup/restore apps and respective data, SSAIDs, runtime permissions, system settings, Magisk modules, and more."
VERSION="v2022.may.9 202205090"

[ -z "${LINENO-}" ] || export PS4='$LINENO: '
mkdir -p ${BKP_DIR##* } $BIN_DIR

export PATH=$BIN_DIR:$PATH

BKP_DIR=$(ls -1d $BKP_DIR 2>/dev/null | head -n1)

trap 'e=$?; cd /; echo; exit $e' EXIT
#set -euo pipefail 2>/dev/null || :
set -eu


# prepare binaries
[ -x $BIN_DIR/openssl ] || {
  tail -n +$BIN_LINE "$0" | base64 -d | gzip -dc | tar -xf - -C $BIN_DIR/
  chmod -R 0700 $BIN_DIR
  busybox --install -s $BIN_DIR/
}


# verbose and debugging
if [ "${1-}" = -x ]; then
  shift
  eval "$@"
else
  [ .${1-} = .-v ] || set -x >$TMPDIR/log 2>&1
fi


! match "${1-}" "-[br]*" || {

  exec 3<&0 4>&1
  FLAGS=${1#-?}

  # zstd compression level
  COMP_LEVEL=1
  ! match $FLAGS "*[0-9]*" || {
    COMP_LEVEL=$(echo $FLAGS | grep -Eo '[0-9]+')
    FLAGS=$(echo $FLAGS | sed -E 's/[0-9]+//')
  }

  ! match "$FLAGS" "*[nx]*" || FLAGS=ad$FLAGS
  ! match "${2-}" "*/*" || FLAGS=c$FLAGS
  [ -n "$FLAGS" ] || FLAGS=ad

  # encryption
  : > $PASSF
  ENCRYPT=false
  [ -n "${TPASS-}" ] && ENCRYPT=true || {
    params="$@"
    shift
    [ -z "$params" ] || {
      while [ -n "$*" ]; do
        ! match "$1" "-p=*" || {
          ENCRYPT=true
          TPASS="${1#-p=}"
          break
        }
        shift
      done
    }
    set -f
    set -- $(echo "$params" | sed "s/ -p=${TPASS-}//")
    set +f
    unset params
  }

  # exclusion list
#   echo "
# *.[aA]ds.*
# *.[tT]rash
# *.dex
# *.log
# *.temp
# *.tmp
# *[cC]ache*
# *[fF]irebase*
# *[lL]ogs*
# *[tT]humbnail*
# *[tT]humbs
# *[tT]rash
# *crash*report*
# *error*report*
# *lytic*
# .[ov]dex
# .art
# .dex
# .oat
# [lL]og
# [lL]og[fF]ile
# [lL]ogs
# [tT]emp
# [tT]mp
# app_optimized
# app_tmp
# dex
# error
# oat
# ./lib
# adb/magisk
# adb/magisk.db
# com.google.android.gms.appid.xml
# files/home/shift
# files/home/storage
# no_backup
# " > $X

echo "./lib
adb/magisk
adb/magisk.db
com.google.android.gms.appid.xml
com.termux/files/home/shift
com.termux/files/home/storage
no_backup" > $X

  # if flag "c*|*m"; then
  #   sed -Ei '/(art|dex|oat|lib)$/d' $X
  # fi

  # custom exclusion list
  exclude=$(echo "$@" | grep ' \-X ..' | sed 's/.*-X //; s/,/\n/g') 2>/dev/null || :
  [ -z "$exclude" ] || {
    echo "$exclude" >> $X
    set -f
    set -- $(echo "$@" | sed 's/ -X.*//')
    set +f
  }
  unset exclude

  # self backup
  rm -rf $BKP_DIR/.bin 2>/dev/null || : ###
  mkdir -p $BKP_DIR
  cp_uf $0 $BKP_DIR/.tarb >/dev/null
}


case "${1-}" in

  -b*)
    backup "$@"
    ! flag s || { _settings; echo; }
    ! flag m || cust /data/adb
  ;;

  -c) clean;;

  -d) shift; delete "$@";;

  -l*) list "$@";;

  -m)
    rm -rf /data/adb/modules/tarb 2>/dev/null || : ###
    dir=/data/adb/modules/vr25.tarb
    mkdir -p $dir/system/bin
    cp -f $0 $dir/tarb
    chmod 0755 $dir/tarb
    for i in $dir/system/bin/ /sbin/; do
      ln -sf $dir/tarb $i 2>/dev/null || :
    done
    rm /data/t 2>/dev/null || : ###
    echo "#!/sbin/sh" > /data/t
    sed 1d $dir/tarb >> /data/t
    chmod 0755 /data/t
    cat << EOF > $dir/module.prop
author=$AUTHOR
description=$DESCRIPTION
id=vr25.tarb
name=Tarb
version=${VERSION% *}
versionCode=${VERSION#* }
EOF
  ;;

  -o) optimize;;

  -r*)
    restore "$@"
    ! flag s || { _settings_r; echo; }
    ! flag m || { cust_r /data/adb; echo; }
    ! flag o || optimize
  ;;

  -s) _settings;;

  -t) _settings_r;;

  -u*) update "$@";;

  -v) less $TMPDIR/log;;

  *) help $COPYRIGHT_YEAR "$VERSION";;

esac

exit

#binaries.tgz.base64
