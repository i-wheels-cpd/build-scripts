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

# Package configuration
PACKAGE_NAME=xgboost
PACKAGE_VERSION=${1:-v3.2.0}
PACKAGE_URL=https://github.com/dmlc/xgboost
PACKAGE_DIR=xgboost/python-package

# Output directory for generated artifacts
OUTPUT_FOLDER="$(pwd)/output"
SCRIPT_DIR=$(pwd)

echo "PACKAGE_NAME: $PACKAGE_NAME"
echo "PACKAGE_VERSION: $PACKAGE_VERSION"
echo "PACKAGE_URL: $PACKAGE_URL"
echo "OUTPUT_FOLDER: $OUTPUT_FOLDER"

# Install system-level build dependencies required for XGBoost
yum install -y git make cmake wget python3.12 python3.12-devel python3.12-pip pkgconfig g++ gcc-c++ gcc-gfortran graphviz

echo "Building xgboost..."

cd ${SCRIPT_DIR}

# Install Python build and test dependencies
pip3.12 install numpy==2.2.6 packaging pathspec pluggy trove-classifiers wheel build hatchling joblib threadpoolctl

# Install dependencies required for running the XGBoost Python test suite
pip3.12 install pytest hypothesis pandas matplotlib pyarrow dask modin shap  pyspark modin[ray] modin[dask] modin[unidist] graphviz

# Clone XGBoost source repository
echo "Cloning the repository..."
mkdir -p output
git clone $PACKAGE_URL
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

# Configure and build native components
cmake -DCMAKE_INSTALL_PREFIX=${OUTPUT_FOLDER} ..
make -j$(nproc)

# Copy generated shared libraries, headers and binaries to output directory
LIBDIR=${OUTPUT_FOLDER}/lib
INCDIR=${OUTPUT_FOLDER}/include
BINDIR=${OUTPUT_FOLDER}/bin
SODIR=${LIBDIR}
XGBOOSTDSO=libxgboost.so

mkdir -p ${LIBDIR} ${INCDIR}/xgboost ${BINDIR} || true

cp ${SRC_DIR}/lib/${XGBOOSTDSO} ${SODIR}
cp -Rf ${SRC_DIR}/include/xgboost ${INCDIR}/
cp -f ${SRC_DIR}/src/c_api/*.h ${INCDIR}/xgboost/
cd ../../

# Build python wheel
echo "Building xgboost Python artifacts and wheel..."

pushd ${SRC_DIR}/python-package

# Remove NCCL dependency since it is not required for non-GPU/Power builds
sed -i '/nvidia-nccl-cu12/d' pyproject.toml

python -m pip wheel -w ${OUTPUT_FOLDER} -v . --no-build-isolation --no-deps

popd

# Install locally built wheel for validation
if ! (pip3.12 install ${OUTPUT_FOLDER}/xgboost-*.whl  --no-deps); then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME | $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail | Install_Fails"
    exit 1
fi

echo "Build and installation completed successfully."

cd $SCRIPT_DIR
cd $PACKAGE_NAME

#skipping tests related to gpu and other server setupsi
if ! pytest tests/ \
    --ignore=tests/ci_build/test_r_package.py \
    --ignore=tests/python/test_cli.py \
    --ignore=tests/python/test_demos.py \
    --ignore=tests/python/test_openmp.py \
    --ignore=tests/python/test_tracker.py \
    --ignore=tests/python-gpu/ \
    --ignore=tests/test_distributed/test_gpu_with_dask \
    --ignore=tests/test_distributed/test_with_dask/test_demos.py \
    --ignore=tests/test_distributed/test_with_dask/test_with_dask.py \
    --ignore=tests/test_distributed/test_with_spark \
    --ignore=tests/test_distributed/test_gpu_with_spark \
    --ignore=tests/test_distributed/test_federated/test_federated.py \
    --ignore=tests/test_distributed/test_gpu_federated/test_gpu_federated.py \
    --ignore=tests/python-sycl \
    --ignore=tests/test_distributed/test_with_dask/test_external_memory.py \
    --ignore=tests/cross-platform \
    --ignore=tests/python/test_with_sklearn.py \
    --disable-warnings \
    -p no:xfail; then

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
