---
date: 2026-08-15
issue: 136
title: Ship a native addon build toolchain in the base image
---

- Install `build-essential` and `pkg-config` in the base image so an npm install script that falls back from a prebuilt binary to `node-gyp rebuild` builds from source instead of failing the job.
- Extend the `ci` admission contract to prove the C compiler, a C++ compiler, `make`, and `pkg-config`, so a runner that lost the toolchain refuses to start rather than failing a job halfway through.
- Leave CMake out deliberately: no current consumer needs a `cmake-js` source build, cmake-js provisions its own CMake when one is, and the package measured a further 96 MB on top of the toolchain's 411 MB.
