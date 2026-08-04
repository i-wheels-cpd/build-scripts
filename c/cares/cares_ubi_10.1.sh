#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : c-ares
# Version       : cares-1_19_1
# Source repo   : https://github.com/c-ares/c-ares
# Tested on     : UBI 10.1
# Language      : Python, Cython, C++
# Ci-Check  : True
# Script License: Apache License 2.0
# Maintainer    : Arcahna Shinde <Archana.Shinde2@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# -----------------------------------------------------------------------------
set -ex

PACKAGE=c-ares
PACKAGE_VERSION=cares-1_19_1
PACKAGE_URL=https://github.com/c-ares/c-ares
WORK_DIR=$(pwd)
SCRIPT_DIR=../c/cares

#prerequisite
pip install ninja setuptools

# Clone cares source repository
echo "Cloning the repository..."
if [ ! -d "$PACKAGE" ]; then
    git clone -b $PACKAGE_VERSION $PACKAGE_URL
fi
cd c-ares

target_platform=$(uname)-$(uname -m)
AR=$(which ar)
PKG_NAME=c-ares

mkdir -p prefix
export PREFIX=$(pwd)/prefix

echo "Building ${PKG_NAME}."
# Isolate the build.
mkdir -p build && cd build

if [[ "$PKG_NAME" == *static ]]; then
  CARES_STATIC=ON
  CARES_SHARED=OFF
else
  CARES_STATIC=OFF
  CARES_SHARED=ON
fi

if [[ "${target_platform}" == Linux-* ]]; then
  CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_AR=${AR}"
fi

# Generate the build files.
echo "Generating the build files..."
cmake ${CMAKE_ARGS} .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DCARES_STATIC=${CARES_STATIC} \
      -DCARES_SHARED=${CARES_SHARED} \
      -DCARES_INSTALL=ON \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -GNinja
      #${SRC_DIR}

ninja || exit 1
ninja install || exit 1

cd $WORK_DIR
mkdir -p local/cares

cp -r c-ares/prefix/* local/cares
cp -r $SCRIPT_DIR/pyproject.toml .

python -m pip wheel -w $WORK_DIR -vv --no-build-isolation --no-deps .

# Install locally built wheel for validation

WHEEL=$(find "$WORK_DIR" -maxdepth 1 -name "*.whl" | head -1)

if ! pip install "${WHEEL}" --no-deps; then
    echo "------------------${PACKAGE}:Install_fails-------------------------------------"
    echo "${PACKAGE} | ${PACKAGE_URL} | ${PACKAGE_VERSION} | GitHub | Fail | Install_Fails"
    exit 1
fi
SITE_PACKAGE_PATH=$(python -m pip show c-ares | awk -F': ' '/^Location:/ {print $2}')

test -f ${SITE_PACKAGE_PATH}/cares/include/ares.h || { echo "ERROR: ares.h not exists." ; exit 1; }
test -f ${SITE_PACKAGE_PATH}/cares/lib/libcares.so || { echo "ERROR: libcares.so not exists." ; exit 1; }
test ! -f ${SITE_PACKAGE_PATH}/cares/lib/libcares.a || { echo "ERROR: libcares.a exists." ; exit 1; }
test ! -f ${SITE_PACKAGE_PATH}/cares/lib/libcares_static.a || { echo "ERROR: libcares_static.a exists." ; exit 1; }
