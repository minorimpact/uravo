#!/bin/bash

set -x

LIVE_DIR="/usr/share/perl5/vendor_perl";
RELEASE_DIR="/data/repo";

while getopts "hn?" cliopts
do
    case "$cliopts" in
    h)  echo $USAGE;
        exit 1;;
    n) REPO="norepo";;
    \?) echo $USAGE;
        exit 1;;
    esac
done

BASENAME=$(basename $0)
USAGE="Usage: $(basename $0) [-h?]"
_DIRNAME=$(dirname $0)
if [ -d $_DIRNAME ]; then
    cd $_DIRNAME
    DIRNAME=$PWD
    cd $OLDPWD
fi
NAME=`/bin/grep Name $DIRNAME/*.spec | /bin/cut -d' ' -f2`;
VERSION=`/bin/grep Version $DIRNAME/$NAME.spec | /bin/cut -d' ' -f2`;
RELEASE=`/bin/grep Release $DIRNAME/$NAME.spec | /bin/cut -d' ' -f2`;
if [ "$VERSION" = '' -o "$RELEASE" = '' ];
then
    echo "Cannot determine version or release number."
    exit 1
fi

PACKAGE_NAME="$NAME-$VERSION"
BUILD_DIR="/tmp"
BASE_DIR="$BUILD_DIR/$PACKAGE_NAME"
ROOT_DIR="$BASE_DIR/$LIVE_DIR"
SOURCE_DIR="$HOME/rpmbuild/SOURCES"

[ -f $SOURCE_DIR/$PACKAGE_NAME.tar.gz ] && rm -f $SOURCE_DIR/$PACKAGE_NAME.tar.gz
[ -d $ROOT_DIR ] && rm -rf $ROOT_DIR
mkdir -p $ROOT_DIR

cp -a $DIRNAME/../* $ROOT_DIR

cd $BUILD_DIR
tar -c -v -z --exclude='.git' --exclude='build' -f ${PACKAGE_NAME}.tar.gz $PACKAGE_NAME/
cp ${PACKAGE_NAME}.tar.gz $SOURCE_DIR/

rm -rf $BASE_DIR
rpmbuild -ba $DIRNAME/$NAME.spec

if [ "$REPO" != "norepo" ];
then
    cd $HOME
    RPM="$PACKAGE_NAME-$RELEASE.noarch.rpm"
    cp rpmbuild/RPMS/noarch/$RPM $RELEASE_DIR/
    createrepo -s sha $RELEASE_DIR
    rm -f $RELEASE_DIR/$NAME-latest.noarch.rpm
    ln -s $RELEASE_DIR/$RPM $RELEASE_DIR/$NAME-latest.noarch.rpm
fi


