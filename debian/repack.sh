#!/bin/sh
#
#   Copyright
#
#       Copyright (C) 2008-2010 Jari Aalto <jari.aalto@cante.net>
#
#   License
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program. If not, see <http://www.gnu.org/licenses/>.

set -e
set -u

DIR=""

Initialize ()
{
    # Check depends

    [ -x /bin/mktemp ] || Die "[ERROR]: mktemp (pkg: coreutils) not installed."
    [ -x /bin/bzip2  ] || Die "[ERROR]: bzip2 (pkg: bzip2) not installed."
    [ -x /bin/gzip   ] || Die "[ERROR]: gzip (pkg: gzip) not installed."
    [ -x /bin/tar    ] || Die "[ERROR]: tar (pkg: tar) not installed."
}

InitializeZip ()
{
    [ -x /usr/bin/unzip ] || Die "[ERROR]: unzip (pkg: unzip) not installed."
}

InitializeRar ()
{
    [ -x /usr/bin/unrar ] || Die "[ERROR]: unrar (pkg: unrar) not installed."
}

Help ()
{
    echo "
SYNOPSIS
  repack.sh [--upstream-source] <VER> <downloaded file> [PACKAGE]

DESCRIPTION
    Repackage upstream source. The command line arguments are
    according to to uscan(1) order. The PACKAGE argument is optional.

    Can also repack *.zip and *.rar files.

OPTIONS
    --upstream-source
	Option is ignored. It is passed from uscan(1) when debian/watch
	file is read.

EXAMPLES
    To manually repack original upstream source foo-1.1.tar.gz to
    bar-1.10.orig.tar.gz:

        repack.sh 1.10 foo-1.1.tar.gz bar

    Save this file to debian/repack.sh and add following line to debian/watch:

        version=3
        http://example.com .*package-(.+).tar.gz debian debian/repack.sh

AUTHOR
    Copyright (C) 2008-2010 Jari Aalto <jari.aalto@cante.net>

    Released under the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version."

    exit 0
}

Run ()
{
    if [ "${test+test_mode}" = "test_mode" ]; then
	echo "$@"
    else
	[ "${verbose+verbose_mode}" = "verbose_mode" ] && echo "$@" >&2
	"$@"
    fi
}

Warn ()
{
    echo "$*" >&2
}

Die ()
{
    Warn "$*"
    exit 1
}

AtExit ()
{
    if [ "$DIR" ]; then
	[ -d "$DIR" ] && rm -rf "$DIR"
    fi
}

DebianVersion ()
{
    # No version conversions yet
    echo $1
}

DebianTar ()
{
    local ver=$1
    local dver=$2
    local file=$3
    local pkg=$4

    # Convert suffixes

    file=$(echo $file | sed -e 's,.orig,,' -e 's,\(tgz\|zip\|rar\)$,tar.gz,' )

    # If version is same, use original file

    if [ "$ver" = "$dver" ]; then
	if [ "$pkg" ]; then
	    echo $file | sed "s,.*$ver,${pkg}_$ver.orig,"
	else
            echo $file
	fi
	return 0
    fi

    if [ "$pkg" ]; then
	echo $file | sed -e "s,.*$ver,${pkg}_$dver.orig,"
    else
        # replace with new version
	echo $file | sed -e "s,$ver,$dver.orig,"
    fi
}

Pkg ()
{
    local file=$1

    if [ -f debian/changelog ]; then
	dpkg-parsechangelog | awk '/^Source:/ {print $2}'
    else

	# package-1.1.tar.gz => package
	echo $file | sed "s,[-_][0-9].*,,"
    fi
}

Version ()
{
    local file=$1
    local pkg=$(Pkg $file)

    if [ ! "$pkg" ]; then
	Die "[ERROR] Internal error. 'pkg' variable not set. Run with debug (-x)"
    fi

    echo $file |
    sed -e "s,\.orig.*,," \
	-e "s,\.tar.*,," \
	-e "s,\.tgz,," \
	-e "s,\.tbz,," \
	-e "s,\.tbz2,," \
	-e "s,\.zip,," \
	-e "s,\.7z,," \
	-e "s,\.rar,," \
	-e "s,\.lzma,," \
	-e "s,\.xz,," \
        -e "s,$pkg[-_],,"
}

Cleanup ()
{
    [ "$1" ] || return 1

    local dir
    dir=$1

    find "$dir" \
	\( \
	-iname "*.exe" \
	-o -name "*.swp" \
	-o -name "DEADJOE" \
	-o -name "*.[~#]" \
	-o -name ".gitignore" \
	-o -name ".bzrignore" \
	-o -name ".svnignore" \
	-o -name ".cvsignore" \
	-o -path "*/debian/*" \
	-o -path "*/debian" \
	-o -path "*/CVS*" \
	-o -path "*/.svn*" \
	-o -path "*/.darcs*" \
	-o -path "*/.bzr*" \
	-o -path "*/.hg*" \
	-o -path "*/.git*" \
	\) \
	-print0 |
    xargs --null --no-run-if-empty rm -rf --verbose

    #	Remove executables

    find "$dir" -type f -print0 |
        xargs --null --no-run-if-empty file |
    awk -F: '$2 ~ /ELF|COFF|LSB exe/ {print $1}' |
        xargs --no-run-if-empty rm --verbose
}

Main ()
{
    if [ $# -eq 0 ]; then
        Help
    fi

    Initialize

    case "$1" in
	--help|-h)
	    Help
	    ;;
	--*)
	    shift
	    #  Ignore uscan(1) argument --upstream-version in $1
	    ;;
    esac

    VER="$1"
    FILENAME="$2"
    DIR=

    if [ ! -f "$FILENAME" ]; then
	Die "[ERROR] Arg 2. File does not exist: $FILENAME"
    fi

    FILE_DIR=$(dirname $FILENAME)
    FILE=$(basename $FILENAME)

    PKG=${3:-$(Pkg $FILE)}

    if [ ! "$PKG" ]; then
	Die "[ERROR] Internal error. PKG not set. Run with debug (-x)"
    fi

    CURVER=$(Version $FILE)

    if [ ! "$CURVER" ]; then
	Die "[ERROR] Internal error. CURVER not set. Run with debug (-x)"
    fi

    DVER=$(DebianVersion "$VER")
    DFILE=$(DebianTar "$CURVER" "$DVER" "$FILE" $PKG)

    #  Debian Developer's Reference 6.7.8.2 Repackaged upstream source

    REPACK_DIR="$PKG-$DVER.orig"

    DIR=$(mktemp -d ./tmp.repack.XXXXXX)

    if [ ! "$DIR" ]; then
	Die "[INTERNAL ERROR] mktemp(1) failed. Debug with 'sh -x PROGRAM'"
    fi

    echo "Repacking $FILENAME as $PKG-$DVER"

    #	Create an extra directory to cope with tarballs that
    #	do not have root/ directory

    UP_BASE="$DIR/unpack"
    Run mkdir "$UP_BASE"

    curdir=$(pwd)

    case "$FILENAME" in
	*.gz | *.bz2 )

	    Run tar -C "$UP_BASE" -xf "$FILENAME"
	    ;;

	*.zip)
	    InitializeZip

	    adir=$(dirname $FILENAME)
	    name=$(basename $FILENAME)

	    Run cd "$UP_BASE"
	    Run unzip "$curdir/$adir/$name" || return 1

	    cd $curdir
	    ;;

	*.rar)
	    InitializeRar

	    adir=$(dirname $FILENAME)
	    name=$(basename $FILENAME)

	    Run cd "$UP_BASE"
	    Run unrar x "$curdir/$adir/$name" || return 1

	    cd $curdir

	    ;;

	*)  Die "Unknonw file format: $FILENAME"
	    ;;
    esac

    if [ $(ls -1 "$UP_BASE" | wc -l) -eq 1 ]; then
	# Tarball does contain a root directory
	UP_BASE="$UP_BASE/$(ls -1 "$UP_BASE")"
    fi

    if [ ! "$UP_BASE" ]; then
	Die "[INTERNAL ERROR] UP_BASE not set"
    fi

    Cleanup "$UP_BASE"

    #	Repack

    Run mv "$UP_BASE" "$DIR/$REPACK_DIR"

    #	Don't use pipes. Errors are not handled well with them.

    Run tar -C "$DIR" -cf "$DIR/repacked.tar" "$REPACK_DIR"

    #   The .orig file must use gzip compression

    tar="$DIR/repacked.tar"

    case "$DFILE" in
	*.bz2)
	    DFILE=$(echo $DFILE | sed "s/.bz2/.gz/")
	    ;;
	*.gz)
	    ;;
	*.zip)
	    DFILE=$(echo $DFILE | sed "s/.zip/.gz/")
	    ;;
	*.rar)
	    DFILE=$(echo $DFILE | sed "s/.rar/.gz/")
	    ;;
	 *)
	    Die "Unknown *.suffix in $DFILE"
	    ;;
    esac

    suffix=".gz"

    Run gzip --best "$tar"

    if [ -f "$DFILE" ]; then
	echo "Warning, overwriting $DFILE"
    fi

    Run mv "$tar$suffix" "$DFILE"

    echo "Done $DFILE"
}

trap AtExit QUIT INT EXIT
Main "$@"

# End of file
