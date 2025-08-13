#!/bin/bash

pushd c_libs/freetype_build
rm -rf build
meson setup build -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Ddefault_library=static
meson compile -C build

popd
pushd c_libs/SDL

rm -rf build 
rm -rf SDLBUILD

cmake -S "." \
    -B build -G Ninja \
    -D CMAKE_BUILD_TYPE=None \
    -D CMAKE_INSTALL_PREFIX=SDLBUILD \
    -D SDL_STATIC=ON \
    -D SDL_SHARED=OFF \
    -D SDL_RPATH=OFF

cmake --build build


popd

pushd c_libs/libepoxy
rm -rf build
meson setup build  -Ddefault_library=static -Dbuildtype=release
meson compile -C build

popd

pushd c_libs/miniz
rm -rf build
meson setup build
meson compile -C build
popd
