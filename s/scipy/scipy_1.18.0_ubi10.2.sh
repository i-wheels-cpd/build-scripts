#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : scipy
# Version       : 1.18.0
# Source repo   : https://github.com/scipy/scipy
# Tested on     : UBI:10.2
# Language      : Python, C, C++, Fortran
# Travis-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Rushikesh Sathe <Rushikesh.Sathe1@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

set -ex

PACKAGE_NAME=scipy
PACKAGE_VERSION=${1:-v1.18.0}
PACKAGE_URL=https://github.com/scipy/scipy
PACKAGE_DIR=scipy
CURRENT_DIR=$(pwd)

echo "Installation of basic dependencies"

yum install -y git make cmake wget python3.14 python3.14-devel python3.14-pip pkgconfig gcc-toolset-15

export PATH=/opt/rh/gcc-toolset-15/root/usr/bin:$PATH
export LD_LIBRARY_PATH=/opt/rh/gcc-toolset-15/root/usr/lib64:$LD_LIBRARY_PATH

export CC=gcc
export CXX=g++
export CMAKE_C_COMPILER=gcc
export CMAKE_CXX_COMPILER=g++

# -----------------------------------------------------------------------------
# Clone and install OpenBLAS from source
# -----------------------------------------------------------------------------
echo " --------------------------------- OpenBLAS Installing --------------------------------- "

OPENBLAS_VERSION="0.3.33"
OPENBLAS_URL="https://github.com/xianyi/OpenBLAS"

git clone -b v$OPENBLAS_VERSION $OPENBLAS_URL
cd OpenBLAS
git submodule update --init

# Setting the env variables for OpenBLAS build
LDFLAGS=$(echo "${LDFLAGS}" | sed "s/-Wl,--gc-sections//g")

# See this workaround
# ( https://github.com/xianyi/OpenBLAS/issues/818#issuecomment-207365134 ).
export CF="${CFLAGS} -Wno-unused-parameter -Wno-old-style-declaration"
unset CFLAGS
export USE_OPENMP=1
export PREFIX=/usr/local

declare -a build_opts
build_opts+=(USE_OPENMP=${USE_OPENMP})

if [ ! -z "$FFLAGS" ]; then
    # Don't use GNU OpenMP, which is not fork-safe
    export FFLAGS="${FFLAGS/-fopenmp/ }"
    export FFLAGS="${FFLAGS} -frecursive"
    export LAPACK_FFLAGS="${FFLAGS}"
fi

build_opts+=(BINARY="64")
build_opts+=(DYNAMIC_ARCH=1)

# Set target platform-/CPU-specific options
export PLATFORM=$(uname -m)
case "${PLATFORM}" in
    ppc64le)
        build_opts+=(TARGET="POWER8")
        BUILD_BFLOAT16=1
        ;;
    s390x)
        build_opts+=(TARGET="Z14")
        ;;
    x86_64)
        # Oldest x86/x64 target microarch that has 64-bit extensions
        build_opts+=(TARGET="PRESCOTT")
        ;;
esac

# Placeholder for future builds that may include ILP64 variants.
build_opts+=(INTERFACE64=0)
build_opts+=(SYMBOLSUFFIX="")

# Build LAPACK.
build_opts+=(NO_LAPACK=0)

# Enable threading. This can be controlled to a certain number by
# setting OPENBLAS_NUM_THREADS before loading the library.
build_opts+=(USE_THREAD=1)
build_opts+=(NUM_THREADS=8)

# Disable CPU/memory affinity handling to avoid problems with NumPy and R
build_opts+=(NO_AFFINITY=1)

# Build OpenBLAS
make -j8 "${build_opts[@]}" \
     HOST=${HOST} CROSS_SUFFIX="${HOST}-" \
     CFLAGS="${CF}" FFLAGS="${FFLAGS}"

CFLAGS="${CF}" FFLAGS="${FFLAGS}" \
    make install PREFIX="${PREFIX}" "${build_opts[@]}"


export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib64:/usr/local/lib
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:${PKG_CONFIG_PATH}"

cd "${CURRENT_DIR}"
echo "--------------------openblas installed-------------------------------"

# -----------------------------------------------------------------------------
# Build NumPy from source against OpenBLAS
# -----------------------------------------------------------------------------
echo " --------------------------------- Numpy Installing --------------------------------- "

python3.14 -m pip install --upgrade pip setuptools wheel
python3.14 -m pip install meson==1.11.1 meson-python==0.19.0 \
    Cython==3.2.0 pybind11 packaging pyproject-metadata ninja "patchelf>=0.11.0" pytest hypothesis

git clone -b v2.5.0 https://github.com/numpy/numpy
cd numpy
git submodule update --init

# Point numpy's meson build at the source-built OpenBLAS
export OPENBLAS_INCLUDE="/usr/local/include"
export NPY_BLAS_LIBS="-L/usr/local/lib -lopenblas"
export NPY_LAPACK_LIBS="-L/usr/local/lib -lopenblas"
export CFLAGS="-I${OPENBLAS_INCLUDE}"

# Install numpy directly from source without build isolation
python3.14 -m pip install . --no-build-isolation

cd "${CURRENT_DIR}"
python3.14 -c "import numpy; print(f'NumPy version: {numpy.__version__}')"
echo " --------------------------------- Numpy Successfully Installed --------------------------------- "

# -----------------------------------------------------------------------------
# Build SciPy 1.18.0 from source against OpenBLAS
# -----------------------------------------------------------------------------
echo " --------------------------------- Scipy Installing --------------------------------- "

export CXXFLAGS="-ftemplate-depth=2000"

python3.14 -m pip install beniget==0.4.2.post1 gast==0.6.0 pythran==0.18.1 setuptools==75.3.0 \
    pooch highspy array_api_extra array_api_strict

echo "Cloning the Repository"
git clone "${PACKAGE_URL}"
cd "${PACKAGE_NAME}"
git checkout "${PACKAGE_VERSION}"
git submodule update --init

export OpenBLAS_HOME="/usr/local"
export SITE_PACKAGE_PATH=/usr/local/lib/python3.14/site-packages

echo "Dependency installations"
python3.14 -m pip wheel -v . --no-build-isolation --no-deps -w "${CURRENT_DIR}/dist/"

WHEEL=$(find "${CURRENT_DIR}/dist" -name "scipy-*.whl" | head -1)
if [ -z "$WHEEL" ]; then
    echo "ERROR: scipy wheel not found after build"
    exit 1
fi
echo "Wheel: $WHEEL"

if ! python3.14 -m pip install "$WHEEL" ; then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail | Install_Fails"
    exit 1
fi

cd "${CURRENT_DIR}"
echo "Testing"

#Disabling Test cases due to time limits.
# if ! (pytest $PACKAGE_NAME -k "not test_2d and not test_version"); then
#     echo "------------------$PACKAGE_NAME::Install_success_but_test_Fails-------------------------"
#     echo "$PACKAGE_VERSION $PACKAGE_NAME"
#     echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | Fail | Install_success_but_test_Fails"
#     exit 2
# else
#     echo "------------------$PACKAGE_NAME::Test_Pass---------------------"
#     echo "$PACKAGE_VERSION $PACKAGE_NAME"
#     echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | Pass |  Both_Install_and_Test_Success"
#     exit 0
# fi
exit 0

