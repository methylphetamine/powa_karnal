# Variants

`onyx` is the single source branch. Root flavors and media overlays are patch
sets applied **at build time** — no per-variant branches, no merge conflicts
when upstream updates land.

## Roots

| Variant | Kernel side | Manager / flashing |
| --- | --- | --- |
| `vanilla` | none (onyx base) | none |
| `apatch` | `apatch.patch` (APatch defconfig + NoMount) | latest APatch APK bundled, auto-flashed during kernel flash |
| `folkpatch` | `apatch.patch` (same KernelPatch-based kernel side) | latest FolkPatch APK bundled, auto-flashed during kernel flash |
| `ksu` | `ksu.patch` (ReSukiSU submodule + NoMount + SuSFS + KSU-Next manager sign) | manager installed separately (KSU-Next / ReSukiSU) |

`apatch` and `folkpatch` produce a zip that, after writing the kernel, extracts
the bundled manager package and runs its installer against the new boot image
(KernelPatch `InstallAP.sh`), then stages the manager APK for first-boot
install. Set `BUNDLE_ROOT=0` to disable, or `APATCH_ZIP=/path/app.apk` /
`FOLKPATCH_ZIP=/path/app.apk` to bundle a pinned local build instead of latest.

## Overlays

| Overlay | Patch | Adds |
| --- | --- | --- |
| `miui` | `miui.patch` | WLAN/network hardening + `miui.config` fragment (MIUI/HyperOS) |
| `c2` | `c2.patch` | MTK VDEC/VENC + VCU Codec2 media stack |

`miui` and `c2` rewrite overlapping vendor media code and are mutually
exclusive.

## Selecting a variant

Local:

```bash
./build.sh variants                     # list patch sets
VARIANT=vanilla ./build.sh all
VARIANT=apatch ./build.sh all
VARIANT=folkpatch,miui ./build.sh all
VARIANT=ksu,c2 ./build.sh all
```

GitHub Actions: **Build & Release → Run workflow**, pick a root and at most one
overlay. `VARIANT` also falls back to the branch/tag name, so `onyx-ksu-next`
still builds the KSU edition.

## Patch sets

| Patch | Files | Notes |
| --- | --- | --- |
| `apatch.patch` | `begonia_apatch_defconfig`, `drivers/kernelsu` symlink, `fs/nomount/*` | used by both `apatch` and `folkpatch` |
| `ksu.patch` | `.gitmodules` + `KernelSU` gitlink (ReSukiSU), `reksun_defconfig`, `fs/nomount/*`, `fs/susfs.c`, `ksu-patches/ksu/*` | root drivers, applied before overlays |
| `miui.patch` | WLAN drivers, `miui.config` | overlay |
| `c2.patch` | MTK VCODEC/VCU, V4L2 uapi | overlay |

## Updating a patch

1. Collect the change on a branch or local tree based on `onyx`.
2. Regenerate the patch against the *current* `onyx` tree, limited to kernel
   sources and configs — never include `build.sh`, workflows, docs or
   `.gitignore` noise:

   ```bash
   git diff --no-color onyx..my-variant -- \
     arch/arm64/configs drivers fs include kernel lib mm net security scripts \
     .gitmodules KernelSU ksu-patches > variants/<name>.patch
   ```

   For a root that adds a submodule, keep the `KernelSU` gitlink and
   `.gitmodules` hunks; `build.sh` runs `git submodule update --init` after
   applying the patch. Fixes that must live inside the KernelSU submodule go
   to `ksu-patches/ksu/*.patch` (applied by `build.sh` with
   `--directory=KernelSU`), never into `KernelSU/` directly.

3. Verify it applies to a clean tree:

   ```bash
   git apply --check variants/<name>.patch
   VARIANT=<name> ./build.sh variants
   ```

4. Commit. The next workflow run with that variant picks it up.

## Rules

- A patch must apply cleanly to `onyx` with `git apply` (no fuzz). If it stops
  applying after an upstream sync, rebase the source change and regenerate.
- Keep patches scoped to their variant. Shared fixes belong on `onyx`.
- Defconfigs added by a patch must match the resolver
  (`begonia_apatch_defconfig`, `reksun_defconfig`).
- Root patches are applied before overlays; keep them independently applicable.
