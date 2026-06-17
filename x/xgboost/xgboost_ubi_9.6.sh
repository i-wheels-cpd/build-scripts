#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : xgboost
# Version       : 3.2.0
# Source repo   : https://github.com/dmlc/xgboost
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

# Variables
PACKAGE_NAME=xgboost
PACKAGE_VERSION=${1:-v3.2.0}
PACKAGE_URL=https://github.com/dmlc/xgboost
PACKAGE_DIR=xgboost/python-package
OUTPUT_FOLDER="$(pwd)/output"
SCRIPT_DIR=$(pwd)

echo "PACKAGE_NAME: $PACKAGE_NAME"
echo "PACKAGE_VERSION: $PACKAGE_VERSION"
echo "PACKAGE_URL: $PACKAGE_URL"
echo "OUTPUT_FOLDER: $OUTPUT_FOLDER"

yum install -y git make cmake wget python3.12 python3.12-devel python3.12-pip pkgconfig g++ gcc-c++ gcc-gfortran graphviz

#clone and install openblas from source

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

#Build OpenBLAS
make -j8 ${build_opts[@]} \
     HOST=${HOST} CROSS_SUFFIX="${HOST}-" \
     CFLAGS="${CF}" FFLAGS="${FFLAGS}"

CFLAGS="${CF}" FFLAGS="${FFLAGS}" \
    make install PREFIX="${PREFIX}" ${build_opts[@]}

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib64:/usr/local/lib
cd ..

echo "--------------------openblas installed-------------------------------"

echo "Building SciPy..."
cd $CURRENT_DIR

# Install Python dependencies
pip install numpy==2.2.6 cython meson-python ninja joblib threadpoolctl patchelf pytest

# Build and install SciPy from source to use custom OpenBLAS
SCIPY_VERSION="v1.17.1"
SCIPY_URL="https://github.com/scipy/scipy"
cd $CURRENT_DIR

git clone $SCIPY_URL
cd scipy
git checkout $SCIPY_VERSION
git submodule update --init

# Set environment variables for SciPy to find custom OpenBLAS
export OpenBLAS_HOME="/usr/local"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:${PKG_CONFIG_PATH}"

# Install additional SciPy build dependencies
pip install beniget==0.4.2.post1 Cython>=3.1.2 gast==0.6.0 meson==1.6.0 meson-python==0.17.1 packaging pybind11 pyproject-metadata pythran==0.17.0 setuptools==75.3.0 pooch build wheel

# Build wheel and store it in dist/
mkdir -p dist

python -m pip wheel \
    -v . \
    --no-build-isolation \
    --no-deps \
    -w dist

# Find the generated wheel
SCIPY_WHEEL=$(ls dist/scipy-*.whl | head -1)

echo "Installing wheel: ${SCIPY_WHEEL}"

# Install the already-built wheel
if ! pip install "${SCIPY_WHEEL}" --no-deps; then
    echo "Failed to install SciPy wheel"
    exit 1
fi

echo "--------------------scipy installed-------------------------------"

cd $CURRENT_DIR

echo "Building scikit-learn..."
# clone source repository
SKLEARN_VERSION="1.8.0"
SKLEARN_URL="https://github.com/scikit-learn/scikit-learn.git"
git clone -b $SKLEARN_VERSION $SKLEARN_URL
cd scikit-learn
git submodule update --init

i#build wheel
python3.12 -m pip wheel -vv --no-build-isolation --no-deps .

# Install scikit-learn
if ! pip install --editable . --no-build-isolation --no-deps; then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

# test using pytest - set below flag as suggested in GitHub forums to resolve ImportPathMismatchError

export PY_IGNORE_IMPORTMISMATCH=1
if ! pytest sklearn/tests/test_random_projection.py; then
    echo "--------------------$PACKAGE_NAME:Install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:Install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Pass |  Both_Install_and_Test_Success"
    exit 0
fi

echo "--------------------scikit-learn installed-------------------------------"
echo "Building xgboost..."

cd ${SCRIPT_DIR}

pip3.12 install numpy==2.2.6 packaging pathspec pluggy trove-classifiers wheel build hatchling joblib threadpoolctl
pip3.12 install pytest hypothesis pandas matplotlib pyarrow dask modin shap  pyspark modin[ray] modin[dask] modin[unidist] graphviz

# Clone the repository
echo "Cloning the repository..."
mkdir -p output
#git clone $PACKAGE_URL
cd $PACKAGE_NAME/
git checkout $PACKAGE_VERSION
git submodule update --init
export SRC_DIR=$(pwd)
echo "SRC_DIR: $SRC_DIR"

#build xgboost cpp artifacts
cd ${SCRIPT_DIR} && mkdir output && OUTPUT_FOLDER=$(pwd)
cd ${SRC_DIR}
mkdir -p build
cd build
cmake -DCMAKE_INSTALL_PREFIX=${OUTPUT_FOLDER} ..
make -j$(nproc)
LIBDIR=${OUTPUT_FOLDER}/lib
INCDIR=${OUTPUT_FOLDER}/include
BINDIR=${OUTPUT_FOLDER}/bin
SODIR=${LIBDIR}
XGBOOSTDSO=libxgboost.so
EXEEXT=
mkdir -p ${LIBDIR} ${INCDIR}/xgboost ${BINDIR} || true
cp ${SRC_DIR}/lib/${XGBOOSTDSO} ${SODIR}
cp -Rf ${SRC_DIR}/include/xgboost ${INCDIR}/
cp -f ${SRC_DIR}/src/c_api/*.h ${INCDIR}/xgboost/
cd ../../

# Build xgboost python artifacts and wheel

echo "Building xgboost Python artifacts and wheel..."
pushd ${SRC_DIR}/python-package
sed -i '/nvidia-nccl-cu12/d' pyproject.toml
python -m pip wheel -w ${OUTPUT_FOLDER} -v . --no-build-isolation --no-deps
popd

# Remove the nvidia-nccl-cu12 dependency in pyproject.toml (not required for Power)
#echo "Removing nvidia-nccl-cu12 dependency from pyproject.toml..."
#sed -i '/nvidia-nccl-cu12/d' pyproject.toml

# install package
if ! (pip3.12 install ${OUTPUT_FOLDER}/xgboost-*.whl  --no-deps); then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail | Install_Fails"
    exit 1
fi
echo "Build and installation completed successfully."

cd $SCRIPT_DIR
cd $PACKAGE_NAME
echo "Current directory: $(pwd)"

#skipping tests related to gpu and other server setups
if ! pytest tests/ --ignore=tests/ci_build/test_r_package.py --ignore=tests/python/test_cli.py --ignore=tests/python/test_demos.py --ignore=tests/python/test_openmp.py --ignore=tests/python/test_tracker.py --ignore=tests/python-gpu/ --ignore=tests/test_distributed/test_gpu_with_dask --ignore=tests/test_distributed/test_with_dask/test_demos.py --ignore=tests/test_distributed/test_with_dask/test_with_dask.py --ignore=tests/test_distributed/test_with_spark --ignore=tests/test_distributed/test_gpu_with_spark --ignore=tests/test_distributed/test_federated/test_federated.py --ignore=tests/test_distributed/test_gpu_federated/test_gpu_federated.py --ignore=tests/python-sycl --ignore=tests/test_distributed/test_with_dask/test_external_memory.py --ignore=tests/cross-platform --disable-warnings  -p no:xfail; then
    echo " ------------------------ $PACKAGE_NAME:install_success_but_test_fails ------------------------ "
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Pass | Install_success_but_test_Fails"
    exit 2
else
    echo " ------------------------ $PACKAGE_NAME:install_&_test_both_success ------------------------ "
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Fail | Both_Install_and_Test_Success"
    exit 0
fi
