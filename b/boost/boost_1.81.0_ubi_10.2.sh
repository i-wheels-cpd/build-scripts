#!/bin/bash
# -----------------------------------------------------------------------------
#
# Package         : Boost
# Version         : v1.81.0
# Source repo     : https://github.com/boostorg/boost
# Tested on       : UBI: 10.2
# Language        : C
# Ci-Check        : True
# Script License  : Apache License, Version 2 or later
# Maintainer      : Nayana Thorat <Nayana.Thorat1@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             it may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# -----------------------------------------------------------------------------

set -ex

# Variables
PACKAGE_NAME=boostcpp
PACKAGE_VERSION=${1:-v1.81.0}
PACKAGE_URL="https://github.com/boostorg/boost"
PACKAGE_TAG=boost-1.81.0
CURRENT_DIR=$(pwd)
PACKAGE_DIR=boostcpp

echo "Installing dependencies..."
yum install -y git make cmake wget python3.14 python3.14-devel python3.14-pip pkgconfig gcc-toolset-15

git clone -b $PACKAGE_TAG $PACKAGE_URL
cd boost
git submodule update --init

#Install pre requisite wheels
python3.14 -m pip install setuptools

mkdir -p $(pwd)/local/boostcpp
export PREFIX=$(pwd)/local/boostcpp
INCLUDE_PATH="${PREFIX}/include"
LIBRARY_PATH="${PREFIX}/lib"

export PATH=/opt/rh/gcc-toolset-15/root/usr/bin:$PATH
export CC=$(which gcc)
export CXX=$(which g++)

CXXFLAGS="${CXXFLAGS} -fPIC"
TOOLSET=gcc

cat <<EOF > tools/build/example/site-config.jam
using ${TOOLSET} : : ${CXX} ;
EOF

LINKFLAGS="${LINKFLAGS} -L${LIBRARY_PATH}"

CXXFLAGS="$(echo ${CXXFLAGS} | sed 's/ -march=[^ ]*//g' | sed 's/ -mcpu=[^ ]*//g' |sed 's/ -mtune=[^ ]*//g')" \
CFLAGS="$(echo ${CFLAGS} | sed 's/ -march=[^ ]*//g' | sed 's/ -mcpu=[^ ]*//g' |sed 's/ -mtune=[^ ]*//g')" \
    CXX=${CXX_FOR_BUILD:-${CXX}} CC=${CC_FOR_BUILD:-${CC}} ./bootstrap.sh \
    --prefix="${PREFIX}" \
    --without-libraries=python \
    --with-toolset=${TOOLSET} \
    --with-icu="${PREFIX}" || (cat bootstrap.log; exit 1)

ADDRESS_MODEL=64
ARCHITECTURE=x86
ABI="sysv"
BINARY_FORMAT="elf"

export CPU_COUNT=$(nproc)

./b2 -q \
    variant=release \
    address-model="${ADDRESS_MODEL}" \
    architecture="${ARCHITECTURE}" \
    binary-format="${BINARY_FORMAT}" \
    abi="${ABI}" \
    debug-symbols=off \
    threading=multi \
    runtime-link=shared \
    link=shared \
    toolset=${TOOLSET} \
    include="${INCLUDE_PATH}" \
    cxxflags="${CXXFLAGS} -Wno-deprecated-declarations" \
    linkflags="${LINKFLAGS}" \
    --layout=system \
    -j"${CPU_COUNT}" \
    install

rm "${PREFIX}/include/boost/python.hpp"
rm -r "${PREFIX}/include/boost/python"


# Prepare package structure
#install pyproject.toml
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/b/boostcpp/pyproject.toml
sed -i s/{PACKAGE_VERSION}/$PACKAGE_VERSION/g pyproject.toml

#building wheel
python3.14 -m pip wheel -w $CURRENT_DIR -v --no-build-isolation --no-deps .
echo "------------------------Installing Python package-------------------"

if ! python3.14 -m pip install . --no-build-isolation ; then
    echo "------------------$PACKAGE_NAME:Python_Install_fails-------------------------------------"
    exit 1
fi
