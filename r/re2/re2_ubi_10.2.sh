#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : re2
# Version       : 2022-04-01
# Source repo   : https://github.com/google/re2
# Tested on     : UBI 10.2
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

PACKAGE=re2
PACKAGE_VERSION=${1:-2022-04-01}
PACKAGE_URL=https://github.com/google/re2
WORK_DIR=$(pwd)

echo "Installing dependencies..."
yum install -y git make cmake wget python3.14 python3.14-devel python3.14-pip pkgconfig gcc-toolset-15
export PATH=/opt/rh/gcc-toolset-15/root/usr/bin:$PATH

#prerequisite
pip install ninja setuptools

echo "Building re2..."

cd $WORK_DIR

# Clone re2 source repository
echo "Cloning the repository..."
if [ ! -d "$PACKAGE" ]; then
    git clone -b $PACKAGE_VERSION $PACKAGE_URL
fi
cd re2
git submodule update --init

mkdir -p prefix
export PREFIX=$(pwd)/prefix

export CPU_COUNT=`nproc`

mkdir -p build-cmake
pushd build-cmake

cmake ${CMAKE_ARGS} -GNinja \
  -DCMAKE_PREFIX_PATH=$PREFIX \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DENABLE_TESTING=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  ..

ninja -v install

popd

# Also do this installation to get .pc files. This duplicates the compilation
# but gets us all necessary components without patching.
make -j "${CPU_COUNT}" prefix=${PREFIX} shared-install

cd $WORK_DIR

mkdir -p local/$PACKAGE

#install pyproject.toml
cp -r re2/prefix/* local/$PACKAGE/
wget https://raw.githubusercontent.com/i-wheels-cpd/build-scripts/refs/heads/main/r/re2/pyproject.toml
sed -i "s/{PACKAGE_VERSION}/$(echo $PACKAGE_VERSION | tr -d '-')/g" pyproject.toml

python3.14 -m pip wheel -w $WORK_DIR -vv --no-build-isolation --no-deps .

# Install locally built wheel for validation

WHEEL=$(find "${WORK_DIR}" -maxdepth 1 -name "${PACKAGE}-*.whl" | head -1)
echo "Built wheel: ${WHEEL}"

if ! pip install "${WHEEL}" --no-deps; then
    echo "------------------${PACKAGE}:Install_fails-------------------------------------"
    echo "${PACKAGE} | ${PACKAGE_URL} | ${PACKAGE_VERSION} | GitHub | Fail | Install_Fails"
    exit 1
fi
SITE_PACKAGES=$(python3.14 -m pip show re2 | awk -F': ' '/^Location:/ {print $2}')

test -f ${SITE_PACKAGES}/re2/lib/libre2.so || { echo "ERROR: libre2.so not exists." ; exit 1; }
test ! -f ${SITE_PACKAGES}/re2/lib/libre2.a || { echo "ERROR: libre2.a exists." ; exit 1; }
test -f ${SITE_PACKAGES}/re2/lib/pkgconfig/re2.pc || { echo "ERROR: re2.pc not exists." ; exit 1; }
test -f ${SITE_PACKAGES}/re2/include/re2/re2.h || { echo "ERROR: re2.h not exists." ; exit 1; }
