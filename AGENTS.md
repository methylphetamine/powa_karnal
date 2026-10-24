# Agent Rules & Repository Governance

This document establishes the **mandatory, non-negotiable rules** for all AI agents, contributors, and automated systems working on the Pox Kernel repository (`pox-kernel-begonia`).

---

## 0. One Branch, Variants as Patches (READ FIRST)
* **Single source branch**: All work lands on **`onyx`** (the default branch). There is exactly **one** long-lived branch. Do **not** create `onyx-ksun`, `onyx-miui`, `onyx-c2`, `onyx-apatch`, `onyx-bakasu` or any other per-variant branch, and do not push variant work to `main` (kept as a mirror during migration).
* **Variants are patch sets**: Root flavors and media overlays live in `patches/` and are applied at build time by `build.sh`:
  * Roots: `apatch.patch` (also used by `folkpatch`), `ksu.patch` (BakaSU); `vanilla` means no patch.
  * Overlays: `miui.patch`, `c2.patch`
* **Where a change belongs**:
  * Shared kernel fixes, upstream syncs, defconfig baseline changes → commit directly on `onyx` (no patch).
  * Anything that only exists because of a root flavor (KernelSU submodule, KSU/SuSFS/NoMount glue, root defconfig) → edit the matching `patches/<root>.patch` and regenerate it.
  * Anything that only exists for a media overlay (WLAN/HyperOS knobs, MTK VCODEC/VCU stack) → edit `patches/<overlay>.patch`.
  * Never mix variant-only code into the base tree "for convenience". That is what the patch is for.
* **Roots**: `vanilla`, `apatch`, `folkpatch`, `ksu`. `apatch`/`folkpatch` bundle the matching KernelPatch manager APK and auto-flash it during kernel flash; `ksu` builds the BakaSU submodule with NoMount/SuSFS and accepts both BakaSU and KernelSU-Next managers; `vanilla` is the untouched base.
* **Selecting a variant**: `VARIANT=<root>[,<overlay>] ./build.sh all` (e.g. `VARIANT=ksu,c2`, `VARIANT=folkpatch,miui`). CI does the same through the **Build & Release** workflow inputs (`root`, `miui`, `c2`). `miui` and `c2` are mutually exclusive.
* **Patch contract** (enforced in review):
  1. Applies to a clean `onyx` tree with `git apply --check patches/<name>.patch` — no fuzz, no `--3way`.
  2. Contains only kernel sources/configs relevant to the variant: `arch/arm64/configs`, `drivers`, `fs`, `include`, `kernel`, `lib`, `mm`, `net`, `security`, `scripts`, `ksu-patches`, `.gitmodules` / `KernelSU` (submodule gitlink). **No** `build.sh`, `.github/`, `README*`, `AGENTS.md`, `CHANGELOG*` or `.gitignore` hunks.
  3. Defconfigs follow the resolver names (`begonia_apatch_defconfig`, `bakasu_defconfig`, …).
  4. Root patches are applied before overlays; keep them independently applicable.
  5. Fixes that belong inside the KernelSU submodule are **not** committed there: add them to `ksu-patches/ksu/*.patch`, which `build.sh` applies with `--directory=KernelSU` after the submodule checkout.
* **Updating a patch** (the only sanctioned workflow):
  ```bash
  git checkout onyx && git pull
  git diff --no-color onyx..<source-ref> -- \
    arch/arm64/configs drivers fs include kernel lib mm net security scripts \
    .gitmodules KernelSU > patches/<name>.patch
  git apply --check patches/<name>.patch
  VARIANT=<name> ./build.sh patches      # sizes + file counts
  ```
  Follow the Conventional Commit rules for the patch update (e.g. `fix(ksu): refresh susfs glue against onyx`).
* **Never** hand-edit a patch hunk to "make it apply". Rebase the source change and regenerate the patch.

---

## 1. Concurrency & Mutation Safety: NEVER Edit While a Task is Running
* **Absolute File Freeze**: You must **NEVER** edit, create, delete, rebase, checkout, or stage any file while a build (`build.sh`, `make`), flash (`adb sideload`), test script, benchmark, or background process is actively executing.
* **Corrupted Builds**: Modifying source files during compilation produces non-deterministic artifacts, broken headers, and invalid object states.
* **Verify Idle State**: Before calling any file modification tool, verify that all background tasks and compiler processes have exited cleanly (`exit code 0`).

---

## 2. Anti-Spaghetti Code Standards (Kernel Quality)
* **Linux Kernel Coding Style**: Adhere strictly to upstream kernel conventions (`Documentation/process/coding-style.rst`):
  * 8-space tabs for indentation, never spaces.
  * Opening braces on the same line for functions/blocks following kernel standards.
  * Descriptive variable and symbol naming.
* **Minimal Targeted Diffs**: Do not touch unrelated files or perform gratuitous reformatting. Solve the exact issue with the smallest sound patch.
* **No rodata / Write-to-Const Panics**:
  * Any sysctl or kernel parameter modified by user-space or vendor HALs (such as Xiaomi's `NodeLooperThread` power HAL) must **never** be marked `const` or `const_debug`.
  * E.g., `sysctl_sched_migration_cost` must remain writable (`unsigned int sysctl_sched_migration_cost`), otherwise write attempts trigger an **EL1 Data Abort** panic.
* **Hardware & Electrical Spec Compliance**:
  * Standard PC USB (`STANDARD_HOST`) charging current must strictly respect the 500mA (500000 µA) USB 2.0 SDP specification.
  * Forcing high currents (e.g. 1.2A+) on standard PC USB collapses VBUS voltage and triggers host motherboard overcurrent protection (causing repeated USB disconnect/reconnect cycles).
  * High-power fast charging (3.0A / 18W) is strictly for dedicated AC wall chargers (`STANDARD_CHARGER` / DCP) and dedicated charging ports.
* **Linux 64-Character UTS_RELEASE Hard Limit**:
  * The Linux kernel enforces `UTS_RELEASE` length $\le 64$ characters.
  * The branded localversion is derived from the selected variant (e.g., `-Pox-Apatch-C2`). Explicit `LOCALVERSION` overrides must still be clamped so the whole string stays under 64 characters.
* **Strict Variant Isolation**:
  * `CONFIG_SULTAN_DEBLOAT=y` is strictly exclusive to the `sultan` variant/patch. Never enable or leak it into the base tree or other variants.
  * APatch, FolkPatch, KernelSU-Next and unrooted builds must remain cleanly separated: root hooks and defconfigs belong in their `patches/<root>.patch`, never in `onyx` itself.
  * Overlays (`miui`, `c2`) must not be enabled together; their media code overlaps.
* **Zero Leftovers**: Never leave debug printk floods, scratch scripts, or ad-hoc binaries in committed code.

---

## 3. Anti-Spaghetti Commits (Git Hygiene)
* **Strict Conventional Commits**:
  * Format: `<type>(<scope>): <imperative summary>`
  * Valid types: `feat`, `fix`, `refactor`, `perf`, `chore`, `docs`, `ci`.
  * Valid scopes: `sched`, `power`, `fs`, `build`, `sultan`, `apatch`, `ksu`, `dts`, etc.
  * Example: `fix(power): enforce 500mA USB SDP limit to prevent host overcurrent trip`
* **Atomic Commits**: Exactly one logical change per commit. Never combine build script edits, driver fixes, and defconfig updates into a single monolithic commit.
* **No Lazy / WIP Commits**: Commits named `fix`, `wip`, `update`, `temp`, `test`, or `patch` are strictly forbidden.
* **Mandatory Rationale in Commit Body**: Every commit message must include a body explaining **why** the change was made and the technical rationale.
* **Linear History**: Rebase cleanly on the target branch. Do not create merge commits of main into feature branches.
* **Bisect-Friendly**: Every single commit must compile cleanly without breaking the build.

---

## 4. Pull Request (PR) Checklist & Quality Gates
Before submitting any Pull Request:
1. [ ] **Build Validation**: The kernel compiles completely with zero errors and zero fatal warnings using the repo toolchain.
2. [ ] **Packaging**: `build.sh zip` succeeds and produces a valid flashable AnyKernel3 package.
3. [ ] **UTS_RELEASE Check**: `include/generated/utsrelease.h` is $\le 64$ characters.
4. [ ] **Variant Correctness**: Base changes compile on `onyx`; variant changes were verified with `VARIANT=<root>[,<overlay>] ./build.sh all` (or at minimum `git apply --check patches/<name>.patch` + a CI run). Do not target per-variant branches — they no longer exist.
5. [ ] **Clean Git History**: Commits follow Conventional Commits and contain no merge commits or WIP clutter.
6. [ ] **No Regression**: Hardware charging limits, boot stability, and HAL sysctls are verified.
