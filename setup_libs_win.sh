#!/bin/bash

BUILDDIR="buildwin"
pushd c_libs
export PATH=$PATH:$(pwd)
popd
echo $PATH

pushd c_libs/freetype_build
rm -rf $BUILDDIR
meson setup $BUILDDIR -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Ddefault_library=static --cross-file ../meson_cross.txt
meson compile -C $BUILDDIR

popd
pushd c_libs/SDL

rm -rf $BUILDDIR 
rm -rf SDLBUILD

export CC="zig cc -target x86_64-windows-gnu"
export CXX="zig c++ -target x86_64-windows-gnu"
export RANLIB="zig ranlib"
cmake -S "." \
    -B $BUILDDIR -G Ninja \
    -D CMAKE_BUILD_TYPE=None \
    -D CMAKE_INSTALL_PREFIX=SDLBUILD \
    -D SDL_STATIC=ON \
    -D SDL_SHARED=OFF \
    -D CMAKE_TOOLCHAIN_FILE=../cmake_toolchain.txt \
    -D SDL_RPATH=OFF

cmake --build $BUILDDIR


popd

pushd c_libs/libepoxy
rm -rf $BUILDDIR
meson setup $BUILDDIR  -Ddefault_library=static -Dbuildtype=release -Dglx=no -Dx11=false --cross-file ../meson_cross.txt
meson compile -C $BUILDDIR

popd

pushd c_libs/miniz
rm -rf $BUILDDIR
meson setup $BUILDDIR --cross-file ../meson_cross.txt
meson compile -C $BUILDDIR
popd
