# Contributing to Kiska Command

The game is an early single-player prototype. Small reproducible fixes are especially useful.

1. Install Godot 4.5+, CMake 3.20+, Ninja, a C++17 compiler and Python 3.
2. Run `./tools/bootstrap.sh` to obtain the pinned godot-cpp binding. On macOS this also downloads Godot 4.5.2.
3. Run `./tools/build.sh`, then `./tools/run.sh`.
4. Run `./tools/test.sh` for changes affecting gameplay. A `GODOT_BIN` environment variable can point to an existing engine binary.

For native core changes, a quick independent check is:

```sh
cmake -S . -B build-core -DBUILD_GODOT_EXTENSION=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build-core --parallel 2
ctest --test-dir build-core --output-on-failure
```

Command work belongs in `game/scripts/squad_director.gd`. Keep player intent separate from vehicle mechanics and physical access checks. New tasks should have progress, completion, cancellation and a blocked outcome; do not move occupants by bypassing the cargo floor/exit checks.

When reporting a command bug, include the aimed object, player seat, crew seats, aircraft ramp state, and steps to reproduce. For performance reports include resolution, render scale, hardware, focus state and camera route.

Original contributions use the repository's MIT license. External assets need a documented source and a redistribution-compatible license in `ASSETS.md`. The included font and USGS-derived terrain retain their separate notices. Avoid committing engine binaries, build caches or proprietary game assets.

GitHub Actions currently tests only the standalone C++ core. Actual Godot gameplay suites run through `tools/test.sh`; a green native workflow does not claim that gameplay passed on that runner.
