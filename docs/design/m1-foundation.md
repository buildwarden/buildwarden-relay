---
# Written from the main repository's docs/design/TEMPLATE.md, adapted: this
# repository has no rule files, no queue and no front-matter validator yet
# (see "The Loop Contract adopted").
feature: m1-foundation
status: draft
drivers: []              # this repository holds no driver, and M1 changes none
seams: []                # M1 implements no seam. Its release manifest is input to seam 8's
                         # specification (relay release forms), which is not written yet.
surfaces: []             # no user-facing surface: the M1 binaries are stubs
security_boundary: env-relay  # any change to the relay is high-severity (GLOBAL-06); M1 adds
                         # no relay behaviour. See the Security note.
alters_relationships: false
design_review: required
native_validation:
  - {host: macos-vz, blocking: false, reason: "the stub unikernel's aarch64-vz form boots under Apple's Virtualization framework; M0 proved the path, and hosted CI cannot run VZ"}
tier2_gaps:
  - {host: macos-vz, what: "boot of the stub unikernel (aarch64-vz loader) on VZ"}
  - {host: windows-hyperv, what: "boot of the stub appliance on Hyper-V; deferred with the appliance's disk form to M2"}
rules: [GLOBAL-01, GLOBAL-03, GLOBAL-04, GLOBAL-05, GLOBAL-06, GLOBAL-07, GLOBAL-08, GLOBAL-09,
        GLOBAL-10, GLOBAL-11, RELAY-01, RELAY-02, RELAY-03, RELAY-04, RELAY-05, RELAY-06,
        RELAY-07, RELAY-08, TEST-01, TEST-02, TEST-03, TEST-04, TEST-05, TEST-07, TEST-08,
        FLOW-08, FLOW-16, FLOW-17, FLOW-18, FLOW-19, FLOW-20]
                         # rule IDs are the main repository's (docs/development/ at b903f65)
rule_changes: []         # this repository has no rules to change; see "Rules mirrored"
concepts: [relay-split, relay-release-forms, relay-workspace, relay-lints, relay-ci,
           reproducible-images, release-manifest, hermit-forks, toolchain-pins, going-public,
           loop-contract, conformance, program]
related:
  - https://github.com/buildwarden/buildwarden/blob/main/docs/design/componentization.md
---

# M1: workspace, lints, CI, reproducible image tooling, and going public

This is the design of milestone M1 of the relay track (track R) of the
componentization program. The umbrella design,
[`componentization.md`](https://github.com/buildwarden/buildwarden/blob/main/docs/design/componentization.md)
(main repository, merged as `b903f65`), fixes what M1 is:

> M1: Workspace, lints, CI, the Loop Contract adopted, reproducible image
> tooling. The repository goes public. The conformance harness comes from S1.

This design works inside that sentence and the umbrella's decisions, and does
not reopen them. It lists the umbrella in `related`, which is what makes it a
program item (FLOW-20).

Rule IDs (`GLOBAL-06`, `RELAY-03`, `FLOW-18`, ...) are the main repository's,
in its `docs/development/` at `b903f65`. "Decision N" with no other source is
the umbrella's Decision N. "Kickoff" is the document *BuildWarden Relay
Unikernel - Fork Kickoff* (2026-11-07), "decisions table" is *Relay Fork -
Decisions for Jeff* (2026-11-07), and "Loop Contract draft" is *BuildWarden
Loop Contract* (draft, 2026-11-07). None of the three is in a repository yet;
the umbrella says P1 and M1 give them homes.

## Problem

`buildwarden-relay` holds the M0 spike and nothing else. On `main` at
`e9b23d5` it has `spike/`, an Apache-2.0 `LICENSE`, a one-line `NOTICE`, and
three files that are still the unedited open-source template: `README.md`
("My Project. TODO: Fill this README out!"), `CONTRIBUTING.md` and
`CODE_OF_CONDUCT.md`. There is no Cargo workspace, no lint configuration, no
CI, no pinned build, and no way to turn a commit into an image. The
repository is private.

Four things depend on that changing, and each has a reason to happen before
relay code is written:

1. **The image hash is load-bearing.** The decisions table (row 13) makes the
   Linux appliance a permanent deliverable because "the hash of the whole
   relay image lets build executors verify they run a current relay without
   introspection", and the umbrella's seam 8 gives every release form "a
   published hash". A hash means something only if the same commit always
   builds the same bytes. The kickoff asks for the tooling to be chosen "in
   M1, before anything depends on the hash".
2. **The relay's invariants are cheap to enforce on an empty workspace and
   expensive to retrofit.** No `unsafe`, no filesystem, no spawned process,
   audited dependencies, two architectures: the kickoff and the Loop Contract
   draft (sections 3 and 8) name them. They need to be CI failures from the
   first line of relay code.
3. **Two other program items expect this repository to be ready.** S1's
   harness (item `seam-specs`) will run against a relay binary or image and
   says "that wiring is M1's, in the relay's queue". P1 (items
   `loop-contract` and `loop-repository`) is done when "this repository's
   loop and the relay's loop each complete one item from the loop
   repository".
4. **The repository goes public at M1** (Decision 16), so what is in it, on
   every branch, has to be fit to publish.

What M1 does not do is build a relay. `relay-core` starts in M2.

## Prior art

**In the main repository** (`buildwarden/buildwarden` at `b903f65`):

- [`componentization.md`](https://github.com/buildwarden/buildwarden/blob/main/docs/design/componentization.md).
  Binding here: Decision 9 (truststore generation moves into the relay; that
  is M5), Decision 11 (native host-mode binaries on every supported operating
  system and architecture, as well as unikernel images; host mode is built in
  M3), Decision 12 (the Linux appliance and the OCI image use the kernel
  network path; the unikernel and host mode use the relay's own stack over
  raw frames), Decision 15 (BuildWarden carries forks of `hermit-kernel`,
  `hermit-loader` and `hermit-rs`; nothing is raised upstream before the end
  of M6), Decision 16 (public at M1), a3 (host mode for Linux first, then
  macOS, Windows only once a frame transport is designed), a11 (visibility is
  changed by Jeff, or by an attended session on his word in that session),
  and the order: "S1 comes before M1's real work, because the relay has no
  written target until then."
- The standards in `docs/development/`: GLOBAL-01 to GLOBAL-11, RELAY-01 to
  RELAY-08, TEST-01 to TEST-08, FLOW-08, FLOW-16 to FLOW-18. **Rules
  mirrored** below says which apply to this repository and how.
- Its CI, `.github/workflows/`: `main.yml` (workflow `ci`: a `changes`
  classifier, `lint`, `tier1`, `tier1-test`, `keytool`, `test`, `tidy`,
  `build`, `book`, and `ci-ok`, "the one check to require: skipped jobs pass,
  so required checks need not track the filters or matrix names");
  `flow18.yml` (job `sessions-private`, which runs
  `tools/workflow/flow18-check.sh origin` on pushes, pull requests and
  daily); `integration.yml`; `firecracker.yml` (a hosted `ubuntu-latest`
  runner with `/dev/kvm`); `relay-image.yml` (pushes
  `ghcr.io/buildwarden/relay`); `release.yml` (GoReleaser, with checksums
  signed by cosign). CodeQL has no workflow file there; one comment in
  `integration.yml` refers to a CodeQL finding, so it is presumably
  GitHub's default setup, which this session could not confirm.
- The Go relay this one replaces: `relay/`, `cmd/relay` (one binary, three
  modes: `host`, `vm`, `container`), `relaycfg/` (the claim), and the relay
  VM tooling in `tools/relay-vm/`. Two facts about how its images are built
  matter here. `tools/relay-vm/build-initramfs.sh` takes "Alpine 3.21's
  current packages" (the comment is in `firecracker.yml`): it reads the
  package index at build time and pins no hash, so two builds of one commit
  can differ. `tools/firecracker-vm/build-kernel.sh` does the opposite and is
  the precedent this design follows: `linux-6.1.191.tar.xz` checked against
  a `sha256` copied from kernel.org's signed list.
- The S1 design, in draft: `docs/design/seam-specs.md` on branch
  `feat/seam-specs` at `056e7af`, not yet reviewed. It plans a Go harness,
  `bw-conformance`, in `buildwarden/buildwarden-specs`, released as a module
  tag and as static binaries with a `SHA256SUMS` file, driven by a *target
  file* (TOML) that names a launcher (`exec`, `oci` or `external`) and the
  attachment points of the relay under test. **Conformance** below is
  written against that draft and says what changes if it changes.

**Outside any repository:** the kickoff, the decisions table and the Loop
Contract draft, read on 2026-11-13. Where they decided something, this design
cites them. Where the umbrella, which is later, differs, the umbrella wins;
the differences are listed under **Conflicts between the sources**.

**In this repository:**

- `spike/REPORT.md` (M0, on `main`). What M1 takes from it: the pins that
  worked (Hermit `hermit-0.13.2`, kernel `v0.13.2`, loader `v0.5.7`,
  toolchains `nightly-2026-02-01` for apps and `nightly-2026-08-15` for the
  loader); that `nightly-2026-11-01` "builds a loader that hangs mid-print on
  Qemu"; that the kernel is taken from a checkout named by
  `HERMIT_MANIFEST_DIR`; that every relay VM needs a virtio entropy device,
  because the carried kernel fails closed without one and Rust's `std` then
  panics before `main`; that the loader's `aarch64-vz` form is an arm64
  `Image` made with `llvm-objcopy -O binary`; and that the prototype's four
  `unsafe` calls are raw `hermit-abi` system calls "for a safe wrapper type
  to hold".
- `spike/vznet/REPORT.md`, on branch `spike/vz-net-entitlements` (unmerged).
  Its conclusion, that the socket pair is the only VZ link that meets the
  isolation gate, is already in the umbrella as the build-link contract. For
  M1 it matters in one way: it is a branch with host evidence on it, and
  branches become public with the repository (**Going public**).

**The Hermit forks** (`buildwarden/hermit-kernel`, `hermit-loader`,
`hermit-rs`), read at the tags the spike pins:

| Fork | Branch | Tag | Commit | `rust-toolchain.toml` |
|---|---|---|---|---|
| `hermit-kernel` | `bw/v0.13.2` | `v0.13.2-bw.1` | `497bce24a8301f0d43cce785f1fcaa1854b5d8e8` | `nightly-2026-02-01`, components `llvm-tools`, `rust-src` |
| `hermit-loader` | `bw/v0.5.7` | `v0.5.7-bw.1` | `47c70ab7c247dd72d38b3c9a2d3c4a1405be69ed` | none |
| `hermit-rs` | `bw/hermit-0.13.2` | `hermit-0.13.2-bw.1` | `d73a481110ed6b3e8d233654fabf4cb77266eade` | `nightly-2026-02-01`, component `rust-src` |

Each branch's `CARRIED.md` classes every carried commit as upstream-bound or
a deviation. What the forks' sources say about building, each of which the
design below relies on:

- The `hermit` crate's `build.rs` builds the kernel itself: it runs
  `cargo run --package=xtask -- build --arch <arch> ...` in the kernel
  checkout (`HERMIT_MANIFEST_DIR`, or the `kernel` submodule beside the
  crate, which points at `hermit-os/kernel`, not at the fork). Before it
  does, it removes every environment variable whose name starts with `CARGO`
  or `RUST`. So the kernel is compiled by the toolchain its own
  `rust-toolchain.toml` names, through the rustup proxy, with rustup's and
  cargo's homes at their defaults under `$HOME`; and `RUSTFLAGS` set by the
  outer build never reach it.
- Both the kernel's and the loader's `xtask` run `rustup target add`, so they
  assume rustup.
- Hermit's targets (`x86_64-unknown-hermit`, `aarch64-unknown-hermit`) are
  built with `-Zbuild-std=std,panic_abort`, which needs a nightly compiler.
- The kernel embeds its build time twice: `src/fs/mod.rs` line 339 calls
  `build_time::build_time_utc!()` (the crate `build-time` 0.1.3, which calls
  `Utc::now()` and does not read `SOURCE_DATE_EPOCH`), and `build.rs` calls
  `built::write_built_file()` (`built` 0.8, which does read
  `SOURCE_DATE_EPOCH`). The loader's `build.rs` uses `built` too. `built` is
  built with its `git2` feature in both, and both print `GIT_VERSION` at
  boot when the checkout is a git repository.
- The kernel's own `deny.toml` allows the licences `0BSD`, `Apache-2.0`,
  `MIT`, `MPL-2.0`, `ISC` and `Unicode-3.0`.
- Upstream's loader CI builds the loader with stable Rust (all targets but
  `aarch64_be`); upstream's kernel CI boots Hermit under QEMU and Firecracker
  on GitHub's `ubuntu-24.04` and `ubuntu-24.04-arm` runners.

### What was measured for this design

To find out what a reproducible Hermit build needs, this session built the
spike's `hello-vz` app for `x86_64-unknown-hermit` twelve times on Linux
x86_64, from copies of the fork tags above, with `nightly-2026-02-01`
(`rustc 1.95.0-nightly (905b92696 2026-01-31)`, LLVM 22.1.0) and
`cargo build --locked -Zbuild-std=std,panic_abort
-Zbuild-std-features=compiler-builtins-mem --release`, and compared the
resulting ELF files by SHA-256.

| Compared | Result |
|---|---|
| Unmodified forks, same directory, two builds a minute apart | Differ. The file holds two build times: `2026-11-13T00:..` (RFC 3339, from `build_time`) and `Fri, 13 Nov 2026 00:31:45 +0000` (from `built`) |
| `build_time_utc!()` replaced by a constant, `SOURCE_DATE_EPOCH` unset, same directory | Differ (`built`'s time) |
| The same with `SOURCE_DATE_EPOCH=1700000000`, same directory: plain; with `TZ`, `LANG` and an extra variable changed; with an empty environment (`env -i`) | Identical, three builds |
| The same with `CI=true GITHUB_ACTIONS=true` | Differ from the three above, and identical to each other (two builds). Something in the build reads the CI's environment; `built` records a CI platform and is the likely reader, which was not confirmed |
| The same in a different directory | Differ. The file holds 59 strings with the build user's home in them: the `rust-src` path under `~/.rustup` (23) and crate sources under `~/.cargo/registry` |

The last row matches a line already in this repository: 
`spike/evidence/vz-norng-console.log` shows a panic message with the path of
the spike machine's rustup directory in it.

Limits of the measurement: one target, a hello-world app, one machine; the
loader was not built, `aarch64-unknown-hermit` was not built, and nothing was
booted. It shows what is necessary. Whether it is sufficient is what the
`repro` job (Design, **Verification**) decides on every change.

Also checked: stable Rust is `1.100.0 (0ef1bc386 2026-11-09)`; with it,
`cargo build --release --target <t>` with
`RUSTFLAGS="-Clinker=rust-lld -Clink-self-contained=yes"` produces statically
linked binaries for `x86_64-unknown-linux-musl` and
`aarch64-unknown-linux-musl` on an x86_64 host with no cross C compiler.

### Conflicts between the sources

The umbrella is the latest and wins each of these.

| Topic | Kickoff, decisions table, Loop Contract draft | Umbrella | Here |
|---|---|---|---|
| Release forms | Two: a Hermit unikernel image and "a plain Linux binary/appliance image" (kickoff) | Five kinds: host-mode binaries per platform, unikernel images, the Linux appliance, the OCI image, and an open-ended list (Decision 11, seam 8) | The second binary crate is not Linux-only, so it is not named `relay-linux` (Decision 1, a1) |
| Truststore | "`relay-core` ... trust-store generation"; a CI job runs "the trust-store conformance suite" (kickoff) | S2 specifies the endpoints; M5 builds them (Decision 9) | Not in M1. No JDK in M1's CI |
| First M1 commit | "The first commit of value is a conformance harness ... Wrap the main repo's collector conformance test" (kickoff, recommendation 2) | "The conformance harness comes from S1", in `buildwarden-specs` (Decision 3, phase S1) | M1 builds no harness; it adds the place one plugs in (**Conformance**) |
| Where the Loop Contract lives | "Likely the existing BuildWarden sessions repo" (decisions table rows 2, 7, 8; Loop Contract draft, open questions) | Its own public repository, `buildwarden-ai-workflow` or similar; the sessions repository "is private, so the queue and reports would stop being visible beside a public project" (Decision 13) | Adoption links to the loop repository once it exists (**The Loop Contract adopted**) |
| Where specifications live | "For now, the specification directory in the main BuildWarden project" (decisions table row 5; Loop Contract draft section 2) | `buildwarden/buildwarden-specs` (Decision 3, a10) | This repository holds no seam specification |
| Repository visibility | "Standalone repo in the BuildWarden org from day one"; nothing on visibility | Public at M1 (Decision 16) | **Going public** |
| Hermit pins | "Pinned to the latest tagged release with a single-place version bump" (kickoff; decisions table row 17) | BuildWarden carries forks (Decision 15) | The pins are fork commits, still in one file (Decision 6) |
| VZ reachability | "NAT with a host-side port forward is the expected answer; vsock ... out of scope unless M0 proves NAT insufficient" | M0's result: two NICs, the build link a socket pair, the host reached over vsock | No effect on M1 beyond the Hermit features the stub enables |
| Async runtime | Decided empirically in M3 (decisions table row 14) | The same; listed as a risk | M1 adds no runtime and bans none |
| Dependency audit | "`cargo-vet` or `cargo-audit` in CI" (kickoff); "dependency audit" (Loop Contract draft section 3) | Silent | `cargo deny` (a8) |

Not a conflict, but worth stating: the Loop Contract draft's build invariant
is "three crates, two architectures". This design keeps three relay crates
and adds one tooling crate, `xtask`, which is not a relay crate and ships in
no image.

## Decisions

1. **Three relay crates in one Cargo workspace, plus `xtask`.**
   `relay-core` (library: all relay logic), `relay-hermit` (binary: the
   unikernel) and `relay-native` (binary `relay`: the Linux appliance, the
   OCI image and host mode, selected at start the way the Go relay's `-mode`
   does). One workspace and one `Cargo.lock`, so every release form ships the
   same version of every dependency. *Rejected:* the kickoff's
   `relay-linux` name, because Decision 11 makes the same binary run in host
   mode on macOS. *Rejected:* a fourth crate now for host mode (`relay-host`
   beside `relay-linux`): the forms differ in launch wiring and in which of
   two network paths they use, and both paths belong in `relay-core`, where
   they are tested once. *Rejected:* a separate workspace for `relay-hermit`,
   which would spare other platforms from fetching the Hermit crate but give
   the unikernel its own lock file and its own dependency versions.

2. **`relay-core` is a `std` crate.** No crate in M1 is `no_std`.
   *Rejected:* `no_std` plus `alloc` for `relay-core`, which would make "no
   filesystem, no process" true by construction. The relay is an HTTP/2
   tunnel endpoint and a TLS-terminating proxy; the kickoff expects an async
   runtime "(Tokio or smol)", both of which need `std`, and Hermit provides
   `std`. A sans-I/O core is a possible M2 structure inside the crate, not a
   crate boundary to fix now.

3. **Three pinned toolchains, each for a named reason, in one file.**
   Host code (`relay-core`, `relay-native`, `xtask`; tests, clippy, rustfmt)
   uses stable `1.100.0`. The unikernel and the Hermit kernel use
   `nightly-2026-02-01`, because Hermit's targets need `-Zbuild-std` and both
   forks pin that nightly at the carried tags. The Hermit loader uses
   `nightly-2026-08-15`, the toolchain M0's eleven checks passed with (a4).
   *Rejected:* one nightly for everything: the appliance, the OCI image and
   the host binaries would ship from a nightly compiler for no reason, and
   clippy and rustfmt would follow a nightly's lint set. *Rejected:* stable
   with `RUSTC_BOOTSTRAP=1` for the Hermit targets: the kernel at `v0.13.2`
   uses unstable features as they were on its pinned nightly.

4. **Edition 2024; the minimum supported Rust version is 1.94, and the
   Hermit nightly sets it.** `relay-core` is compiled by two compilers, and
   the older one, `1.95.0-nightly`, has as stable everything that was stable
   in 1.94. So `rust-version = "1.94"`. The MSRV moves only when the Hermit
   forks' pin moves. *Rejected:* an MSRV policy stated in releases back
   ("the last N stable releases"): nothing consumes these crates as a
   library, and the real constraint is the fork pin.

5. **Dependencies are locked, not vendored.** `Cargo.lock` is committed and
   every cargo command in CI and in image builds passes `--locked`. Sources
   are restricted to crates.io and the three fork repositories. `cargo deny`
   checks advisories, licences, bans and sources on every change (a8, a9).
   *Rejected:* vendoring crate sources into the repository: a large diff on
   every bump, for a guarantee the lock file's checksums already give.
   Keeping a release rebuildable after an upstream source disappears is a
   release-time concern (a source bundle per release), deferred to M2 with
   the first real release.

6. **Every external input is pinned by hash in one file, `pins.toml`.**
   Toolchains by channel and by the SHA-256 of their dated channel manifest,
   fork sources by full commit ID, the builder image by digest, the Linux
   source tarball by SHA-256, and later the conformance harness by version
   and SHA-256. The decisions table's "one place to change the version" (row
   17) is kept; `cargo xtask check-pins` fails when `rust-toolchain.toml`,
   `Cargo.toml` or a workflow disagrees with it. *Rejected:* git submodules
   for the forks: three more places a pin lives, and a checkout step every
   contributor and every job has to remember.

7. **`unsafe` is forbidden in every crate of this workspace.** The kickoff:
   "`#![forbid(unsafe_code)]` in all relay crates. Unsafe is permitted only
   in the kernel/driver layer owned by Hermit." Where the relay needs a
   system interface with no safe API, the safe wrapper lives outside this
   workspace: for Hermit, in the `hermit-rs` fork, as a carried commit; on
   other operating systems, in a dependency admitted under the dependency
   policy (a2). M1 needs none.

8. **"No filesystem" and "no spawned process" are enforced three ways.**
   Clippy's `disallowed_types` and `disallowed_methods` on the relay crates'
   own code; a source scan, `cargo xtask lint-sources`, that sees every
   `cfg` branch, including the Hermit-only code clippy is not run on; and
   `cargo deny` bans on the dependency features that would bring either in.
   *Rejected:* `no_std` (Decision 2). *Rejected:* clippy alone: it checks
   only the configuration it compiles, and its lists name items one by one,
   so a function nobody listed passes. *Rejected:* a custom rustc or dylint
   lint: a nightly-bound tool to maintain for what a scan of four small
   crates does.

9. **CI has one required check, `ci-ok`, as the main repository's does.**
   Its jobs: format, pins, clippy, source scan, tests on four hosted
   platforms, native builds, Hermit builds, `cargo deny`, the image build,
   an independent image rebuild, the comparison of the two, smoke boots, and
   the conformance hook. Everything in M1 runs on GitHub-hosted runners; only
   the VZ boot needs a native host, and it does not block.

10. **Images are built in a builder container pinned by digest, at fixed
    paths, with a scrubbed environment, by `cargo xtask images`** (a5).
    *Rejected:* Nix. It is the more hermetic tool, and the kickoff names it
    first. It loses for M1 on what the forks' build does today: the `hermit`
    crate's build script starts a nested cargo through the rustup proxy with
    its environment stripped, both `xtask`s call `rustup`, and `-Zbuild-std`
    resolves the standard library's own dependencies at build time. Each of
    those needs a workaround or a carried fork commit inside a Nix sandbox,
    and none of that work brings the relay closer. The choice is confined to
    one `xtask` module and can be revisited between releases. *Rejected:*
    Linuxkit. It assembles Linux images from container images; it does not
    build the unikernel, and its inputs would still need pinning by the same
    means. *Rejected:* building on the hosted runner directly: compiler and
    tool versions change when GitHub updates the runner image, so the bytes
    for one commit would change over time.

11. **A release's hashes are over canonical forms, listed in one manifest.**
    The canonical form of the unikernel is the application ELF plus the
    loader for each boot protocol; of the appliance, the kernel image plus an
    initramfs; of the OCI image, an OCI layout whose index digest is the
    image's identity. Container formats a hypervisor needs (VHDX, qcow2,
    VMDK, ISO) are derived from those and are not what the published hash
    covers, unless M2 shows a derivation is byte-reproducible (a6).
    *Rejected:* hashing whatever file a driver boots: `qemu-img`-style
    converters write fresh identifiers into some formats, and the hash would
    then identify a conversion, not a relay.

12. **The kernel fork gains one carried commit, and the three forks new
    tags.** The kernel's `build_time_utc!()` has to take its value from
    `SOURCE_DATE_EPOCH`; nothing outside the kernel source can fix it
    (**What was measured**). The change goes to `bw/v0.13.2` by pull
    request, classed in `CARRIED.md`, and is tagged `v0.13.2-bw.2` (a10).

13. **`spike/` stays where it is, as evidence, outside the workspace.**
    The umbrella cites `spike/REPORT.md` by that path, and the fork branches'
    `CARRIED.md` files cite `spike/patches/`. *Rejected:* moving it under
    `docs/`, which breaks those references for no gain; deleting it, which
    removes the record of why each carried commit exists.

14. **The repository goes public after the foundation has merged and its CI
    is green on `main`, and before the stub pre-release** (a13, a16).
    *Rejected:* flipping first: the first thing a visitor would see is a
    template README and a spike. *Rejected:* waiting for the Loop Contract or
    for S1: neither changes what is in this repository's history.

15. **M1 runs in two parts.** M1a is everything that depends on nothing
    outside this repository and the forks. M1b is adoption: the Loop
    Contract, the loop repository, and the conformance pin. M1 is done when
    both are. M1a's tasks start now and merge as they are ready; M1b's are
    listed with what each waits for (**The Loop Contract adopted**).

## Questions

### Blocking

None stops this design or the start of M1a.

Two confirmations are Jeff's alone and gate one task each, not the design.
They are written as a15 and a14 below so they are decided in the design
review; the visibility change itself is his act in any case (a11 of the
umbrella).

### Assumed

"Proceeding with X; confirm." Each is confirmed or changed in the design
review (FLOW-19).

- **a1. The second binary crate is `relay-native`, and its binary is
  `relay`.** Options: (A) `relay-native`, one crate for the appliance, the
  OCI image and host mode; (B) keep the kickoff's `relay-linux` and add
  `relay-host` in M3, four relay crates; (C) another name (`relay-os`,
  `relay-host`). *Proceeding with A.* The Loop Contract draft's "three
  crates" holds, and the binary keeps the Go relay's name.
- **a2. No crate in this workspace may contain `unsafe`; wrappers live in
  the `hermit-rs` fork or in admitted dependencies.** Options: (A) as
  stated, which is the kickoff's rule read strictly; (B) a fourth crate here,
  `relay-sys`, with `unsafe` allowed, every block documented, and nothing
  else in it. *Proceeding with A.* The known needs are M3's: the packet
  socket and `read_entropy` on Hermit (the spike's four raw calls), and
  adopting an inherited descriptor in host mode, which `std` only offers
  through an `unsafe` function. If M2 or M3 finds a need that neither the
  fork nor an acceptable dependency covers, that is a return to this
  decision with B as the named alternative, not an `#[allow]`.
- **a3. Toolchains: stable `1.100.0` for host code,
  `nightly-2026-02-01` for the unikernel and the kernel, MSRV 1.94.**
  Options: (A) as stated; (B) host code on stable `1.95.0`, the release
  nearest the Hermit nightly, to narrow the gap between the two compilers
  that build `relay-core`; (C) one nightly for everything. *Proceeding with
  A.* The gap is covered by a job that runs `relay-core`'s tests with the
  Hermit nightly itself.
- **a4. The loader is built with `nightly-2026-08-15`.** It is what M0
  proved. The loader has no toolchain file, upstream builds it with stable,
  and the spike's Makefile notes the `v0.5.7` release was "built with rustc
  1.97.1". Options: (A) keep `nightly-2026-08-15`; (B) stable `1.97.1`,
  which removes one nightly; (C) the host stable, `1.100.0`, which removes a
  toolchain but is newer than the `nightly-2026-11-01`... no: older than it,
  and untested either way. *Proceeding with A, and with one implementation
  task that tries B:* if the loader built with `1.97.1` passes every smoke
  boot in CI and the VZ boot on the MacBook, the pin changes to `1.97.1` in
  that task's pull request; otherwise A stays and the result is recorded
  here. C is not tried in M1.
- **a5. Reproducibility tooling: a pinned builder container driven by
  `cargo xtask`.** Options: (A) as stated (Decision 10); (B) Nix flakes;
  (C) Linuxkit for the appliance plus A for the rest. *Proceeding with A.*
  This is the decision in this design that is most expensive to change
  later, so it is the one to look at hardest in review.
- **a6. The published hash covers canonical forms; derived disk formats are
  not hashed in M1.** Options: (A) as stated (Decision 11), with M2 deciding
  the appliance's disk form for Hyper-V; (B) M1 also settles a
  byte-reproducible raw disk image. *Proceeding with A.* The umbrella
  expects Hyper-V to use the appliance, and a generation 2 Hyper-V VM boots
  from a disk, so M2 cannot avoid the question; M1 leaves it room.
- **a7. M1's appliance kernel is Linux `6.1.191`, built from the tarball the
  main repository already pins, with a minimal configuration.** Options:
  (A) as stated: sha256
  `02f15b77d213e15607923832ef9382e2414ea90df6c007f15a910e139645c35d`, from
  `tools/firecracker-vm/build-kernel.sh`; (B) a newer longterm line now;
  (C) no kernel in M1, initramfs only. *Proceeding with A.* M1 needs a
  kernel only to prove that a kernel build reproduces and that the image
  boots. Which line and which configuration the appliance ships is M2's
  decision, with its drivers (virtio, Hyper-V, netfilter). This session
  could not reach kernel.org to read the current longterm versions.
- **a8. `cargo deny` is the dependency audit; `cargo vet` is decided in
  M2.** `cargo deny check advisories` reads the RustSec database, as
  `cargo audit` does, and the same tool checks licences, bans and sources.
  Options: (A) as stated; (B) `cargo audit` plus separate licence tooling;
  (C) `cargo vet` from the start. *Proceeding with A.* M1's relay crates
  have almost no dependencies, so there is nothing for `cargo vet` to
  attest yet; M2, which adds TLS and HTTP stacks, is where the question has
  content.
- **a9. Licence allowlist: `Apache-2.0`, `MIT`, `BSD-2-Clause`,
  `BSD-3-Clause`, `ISC`, `0BSD`, `Zlib`, `Unicode-3.0`, and `MPL-2.0`.**
  The first eight are permissive and consistent with this repository's
  Apache-2.0 `LICENSE`. `MPL-2.0` is on the list because the Hermit
  kernel's own `deny.toml` allows it, and the unikernel image contains the
  kernel's dependencies; which crate needs it was not determined. Options:
  (A) as stated; (B) the same without `MPL-2.0` for crates that reach
  `relay-core` and `relay-native`, allowed only by a named exception.
  *Proceeding with B* for this workspace's `deny.toml`, since the kernel is
  not in this workspace's dependency graph (it is built by the `hermit`
  crate's build script and checked by its own `deny.toml`). The first
  release's third-party notices must cover the kernel's set as well
  (deferred to M2).
- **a10. The fork change goes in by pull request to `bw/v0.13.2`, merged
  and tagged by Jeff or by an attended session on his word.** The loop
  writes the commit on a branch of `buildwarden/hermit-kernel` and opens the
  pull request; it does not push a `bw/` branch or a tag. Options: (A) as
  stated; (B) the loop pushes `bw/` branches and tags itself. *Proceeding
  with A:* a `bw/` branch is the fork's trunk (FLOW-08), and a tag is what
  `pins.toml` trusts.
- **a11. Agent sessions that commit here are recorded as the main
  repository's are, and this repository gets the same guard.** A
  `.entire/settings.json` naming `buildwarden/buildwarden-sessions`, and a
  `flow18` workflow whose `sessions-private` job fails if the settings name
  another remote or if this repository carries any `entire/` ref (FLOW-18).
  Options: (A) as stated; (B) nothing until the Loop Contract says what a
  component repository must carry. *Proceeding with A.* The check matters
  most at the moment the repository becomes public. On 2026-11-13 the
  remote carries no `entire/` ref.
- **a12. Code scanning is GitHub's default CodeQL setup, turned on when the
  repository is public, for Rust and for the workflows.** This session
  could not verify that default setup analyses Rust, nor how the main
  repository's CodeQL is configured. Options: (A) default setup, with an
  explicit `codeql.yml` only if default setup does not cover Rust;
  (B) no CodeQL; clippy, `cargo deny` and the source scan are the static
  checks. *Proceeding with A.*
- **a13. M1 ends with a stub pre-release, `v0.0.1`.** The Loop Contract
  draft, section 8, step 4: "Declare its consumables ..., even if the first
  release is a stub." Options: (A) Jeff, or an attended session on his
  word, pushes `v0.0.1` once M1a has merged and the repository is public;
  the release workflow publishes the stub images with their manifest,
  marked as a pre-release that does nothing; (B) no tag until M2 has a
  relay. *Proceeding with A.* The release path and the published hash are
  exercised before any driver depends on them, and K1's "relay source" has
  a real manifest to read.
- **a14. The repository's public documents mirror the main repository's.**
  `NOTICE` stays as it is: it is word for word the main repository's.
  `README.md` and `CONTRIBUTING.md` are rewritten for this repository.
  `SECURITY.md` is added and gives the same reporting route as the main
  repository's `SECURITY.md`. `CODE_OF_CONDUCT.md` and the security section
  of the template `CONTRIBUTING.md` point reports to another organization's
  addresses; the main repository has no `CODE_OF_CONDUCT.md`. Options for
  the code of conduct: (A) remove it, as the main repository has none;
  (B) keep it as it is; (C) replace it with one Jeff names. *Proceeding
  with A; this one needs Jeff's explicit word*, because it and the security
  contact are statements made in the project's name.
- **a15. What is already in the history is acceptable to publish, with one
  item for Jeff to rule on.** A scan of `main` at `e9b23d5` for keys,
  tokens, credentials and e-mail addresses found none beyond the template's
  conduct address. It found one private path:
  `spike/evidence/vz-norng-console.log` line 185 holds the spike machine's
  home directory path, user name included. The unmerged branch
  `spike/vz-net-entitlements` holds more: `spike/vznet/REPORT.md` and its
  `evidence/` name the host's LAN address, its interface names, and the
  services that were listening on it. Options: (A) accept `main` as it is,
  and for the branch, land a redacted copy of the report and evidence on
  `main` by pull request, after which Jeff deletes the branch; (B) accept
  both as they are; (C) rewrite history. *Proceeding with A.* C needs a
  force-push to `main`, which no agent does (FLOW-17), and buys little for
  a first name that is already public as the maintainer's. The branch's
  host details are a different kind of thing, and only Jeff can say they
  may be published.
- **a16. Order around the visibility change.** Proceeding with: M1a's pull
  requests merge while the repository is private; Jeff answers a14 and a15;
  the checklist under **Going public** is run and recorded; Jeff, or an
  attended session on his word, changes the visibility, sets branch
  protection and turns on code scanning in the same sitting; then `v0.0.1`.
  Whether the organization's plan allows branch protection on a private
  repository was not determined; if it does, protection is set before the
  change.
- **a17. Until the loop repository exists, M1a has no queue item.** Its
  work is done in attended or directly dispatched sessions, on feature
  branches of this repository, through pull requests Jeff merges (FLOW-08,
  FLOW-16, FLOW-17). The relay's first queue item is filed when the loop
  repository can hold it. Options: (A) as stated; (B) a temporary queue in
  this repository, moved later. *Proceeding with A*, which is what Jeff
  chose for this design itself.
- **a18. Hosted-runner assumptions.** Proceeding on: `ubuntu-24.04` offers
  `/dev/kvm` (the main repository's `firecracker.yml` relies on it);
  `ubuntu-24.04-arm` is available to this repository and runs
  `qemu-system-aarch64` (upstream Hermit's CI does); Linux arm runners are
  free of charge for a public repository. The last two were not verified
  from here. If an arm runner is not available, the aarch64 smoke boots run
  under emulation on `ubuntu-24.04`, and the aarch64 unit tests are a
  tracked gap.
