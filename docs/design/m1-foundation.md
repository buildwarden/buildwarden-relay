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
| Unmodified forks, same directory, two builds a minute apart | Differ. The file holds two build times: `2026-11-13T00:27:59.779154332+00:00` (from `build_time`) and `Fri, 13 Nov 2026 00:27:59 +0000` (from `built`) |
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

12. **The kernel fork gains one carried commit and a new tag.** The
    kernel's `build_time_utc!()` has to stop reading the clock; nothing
    outside the kernel source can fix it (**What was measured**). The change
    goes to `bw/v0.13.2` by pull request, classed in `CARRIED.md`, and is
    tagged `v0.13.2-bw.2` (a10). The loader and `hermit-rs` forks stay at
    their `-bw.1` tags.

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
  toolchain, but lies between the nightly that works and the one that hangs
  and has not been tried. *Proceeding with A, and with one implementation
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
- **a9. Licence allowlist for this workspace: `Apache-2.0`, `MIT`,
  `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `0BSD`, `Zlib` and
  `Unicode-3.0`.** All eight are permissive and consistent with this
  repository's Apache-2.0 `LICENSE`. The Hermit kernel's own `deny.toml`
  also allows `MPL-2.0`; which of its crates needs it was not determined.
  Options: (A) the eight, with any other licence admitted only as a named
  exception for one crate; (B) the eight plus `MPL-2.0`, to match the
  kernel. *Proceeding with A.* The kernel is not in this workspace's
  dependency graph: the `hermit` crate's build script builds it, and its own
  `deny.toml` checks it. The unikernel image does contain the kernel's
  dependencies, so the third-party notices of the first real release must
  cover the kernel's set as well (deferred to M2).
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

## Design

### Repository layout

```
buildwarden-relay/
  Cargo.toml                 the workspace, its lints and its release profile
  Cargo.lock                 committed
  rust-toolchain.toml        channel = "1.100.0" (the host toolchain)
  pins.toml                  every external input, by hash (Decision 6)
  clippy.toml                disallowed types and methods for the relay crates
  deny.toml                  advisories, licences, bans, sources
  rustfmt.toml               edition = "2024", nothing else
  .cargo/config.toml         [alias] xtask = "run --package xtask --"
  .entire/settings.json      checkpoint_remote = buildwarden/buildwarden-sessions (a11)
  .github/
    workflows/               ci.yml, flow18.yml, audit.yml, builder.yml, release.yml
    pull_request_template.md with a "Security note" heading (GLOBAL-06)
  crates/
    relay-core/              library
    relay-hermit/            binary, Hermit targets only
    relay-native/            binary `relay`
  xtask/                     build, check and image tooling; its own clippy.toml
  images/
    builder/Containerfile    the builder image
    appliance/               kernel-x86_64.config, kernel-aarch64.config
  conformance/
    targets/                 target files for S1's harness (empty in M1)
  tests/lint-fixtures/       a crate, outside the workspace, that must fail the lints
  tools/flow18-check.sh      the FLOW-18 guard, until the loop repository supplies it
  docs/
    design/m1-foundation.md  this file
    invariants.md            the relay's invariants and the check that enforces each
    building.md              how to build, rebuild and verify a hash
  spike/                     M0, unchanged (Decision 13)
  README.md  CONTRIBUTING.md  SECURITY.md  LICENSE  NOTICE
```

The relay repository's `CONTRIBUTING.md` sets no convention for designs
today (it is the template). This design sits at `docs/design/<feature>.md`
as the main repository's do.

### The workspace

```toml
[workspace]
resolver = "3"
members = ["crates/relay-core", "crates/relay-hermit", "crates/relay-native", "xtask"]
default-members = ["crates/relay-core", "crates/relay-native", "xtask"]
exclude = ["spike", "tests/lint-fixtures"]

[workspace.package]
version = "0.0.1"
edition = "2024"
rust-version = "1.94"
license = "Apache-2.0"
repository = "https://github.com/buildwarden/buildwarden-relay"
publish = false

[profile.release]
panic = "abort"
overflow-checks = true
lto = true
codegen-units = 1
strip = "debuginfo"
```

Resolver 3 makes cargo prefer dependency versions whose `rust-version` is at
most the workspace's, which is what keeps one lock file buildable by the
older Hermit nightly. The spike's six apps each declare their own
`[workspace]`, so excluding `spike` changes nothing for them.

| Crate | Kind | Built for | What M1 creates | Real code arrives |
|---|---|---|---|---|
| `relay-core` | library | every target below | Real, and very small: the crate attributes, the function that formats the start-up banner (`buildwarden-relay <version> <form> <arch>`), and its unit tests | M2 (claim, collector client, ledger writer, proxy, DNS; the kernel network path), M3 (the frame path), M5 (truststores) |
| `relay-hermit` | binary | `x86_64-unknown-hermit`, `aarch64-unknown-hermit` | A stub: prints the banner, waits one second, returns (which powers the VM off). The wait is the spike's `hello-vz` finding: VZ drains the console asynchronously. On any other target its `main` prints that it runs only on Hermit and exits 2, so `--workspace` commands work on every host | M3 |
| `relay-native` | binary `relay` | `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl` (appliance, OCI image, Linux host mode); `aarch64-apple-darwin` (macOS host mode); `x86_64-pc-windows-msvc` (compiled and tested only, GLOBAL-07; a3 defers Windows host mode) | A stub: prints the banner. As PID 1 it then parks forever, because an init that exits panics the kernel; otherwise it exits 0. It reads no flag and no environment variable | M2 (appliance, OCI), M3 (host mode) |
| `xtask` | binary, tooling | the host | Real: `check-pins`, `lint-sources`, `fetch`, `build`, `images`, `repro-compare`, `smoke`, `conformance` | grows with each milestone |

The platforms for host mode are the ones the Go relay is released for today
(`.goreleaser.yaml` in the main repository: linux/amd64, linux/arm64,
darwin/arm64).

**`no_std`.** None (Decision 2).

**Features.** No relay crate has a cargo feature in M1. A relay crate gains
one only through a design, and no feature may relax a lint or admit a
filesystem or process API. `relay-hermit` enables these features of the
`hermit` crate, the set the spike's `hello-vz` booted with on QEMU and VZ:
`acpi`, `pci`, `virtio-console`, `virtio-rng`, with `default-features =
false`. M3 sets the relay's real set (the spike's relay prototype used
`acpi`, `pci`, `kernel-stack`, `virtio-console`, `virtio-rng`, `virtio-net`,
`net-packet`, `dhcpv4`, `tcp`, `udp`).

**The `hermit` dependency and the kernel.** `relay-hermit` depends on the
fork by commit:

```toml
[target.'cfg(target_os = "hermit")'.dependencies]
hermit = { git = "https://github.com/buildwarden/hermit-rs", rev = "d73a481110ed6b3e8d233654fabf4cb77266eade", default-features = false, features = ["acpi", "pci", "virtio-console", "virtio-rng"] }
```

Cargo has to fetch that repository on every platform to resolve the
workspace, including its `kernel` submodule, which points at upstream. That
is the cost of one lock file (Decision 1). The kernel that is actually built
is never that submodule: `cargo xtask build hermit` exports the kernel fork
at its pinned commit and sets `HERMIT_MANIFEST_DIR` to it, as the spike did.
A plain `cargo build -p relay-hermit --target x86_64-unknown-hermit` would
silently link upstream's kernel, without the carried commits and so without
fail-closed entropy. To make that impossible, `relay-hermit`'s `build.rs`
fails for a Hermit target unless `xtask` started it (it checks for
`BW_XTASK`), and the message names the command to use.

### Pins

`pins.toml`, with the values known today. `<...>` marks a value a task sets.

```toml
[toolchain.host]
channel = "1.100.0"                    # rustc 1.100.0 (0ef1bc386 2026-11-09)
manifest = "https://static.rust-lang.org/dist/channel-rust-1.100.0.toml"
manifest_sha256 = "3051e859570f64a8c5acb9d09e87425db52c7d97287c67e8f6d57d7d34ef9258"

[toolchain.hermit]                     # relay-hermit and the Hermit kernel
channel = "nightly-2026-02-01"         # rustc 1.95.0-nightly (905b92696 2026-01-31)
manifest = "https://static.rust-lang.org/dist/2026-02-01/channel-rust-nightly.toml"
manifest_sha256 = "77b36daeb05df6b330c3a6774a23e65854959c57a3870d0afa3949ddd2390f3d"

[toolchain.loader]                     # the Hermit loader (a4)
channel = "nightly-2026-08-15"         # rustc 1.99.0-nightly (d453bdd8f 2026-08-14)
manifest = "https://static.rust-lang.org/dist/2026-08-15/channel-rust-nightly.toml"
manifest_sha256 = "0eee8c54cacbb2a6d8867a9dc9e9cafe936dd45bb6e2f36c8aa3e25b4ddafc38"

[fork.hermit-kernel]
repository = "https://github.com/buildwarden/hermit-kernel"
tag = "v0.13.2-bw.1"                   # becomes v0.13.2-bw.2 (Decision 12)
commit = "497bce24a8301f0d43cce785f1fcaa1854b5d8e8"

[fork.hermit-loader]
repository = "https://github.com/buildwarden/hermit-loader"
tag = "v0.5.7-bw.1"
commit = "47c70ab7c247dd72d38b3c9a2d3c4a1405be69ed"

[fork.hermit-rs]
repository = "https://github.com/buildwarden/hermit-rs"
tag = "hermit-0.13.2-bw.1"
commit = "d73a481110ed6b3e8d233654fabf4cb77266eade"

[linux]                                # M1's appliance kernel (a7)
version = "6.1.191"
tarball = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.191.tar.xz"
sha256 = "02f15b77d213e15607923832ef9382e2414ea90df6c007f15a910e139645c35d"

[builder]
image = "ghcr.io/buildwarden/relay-builder"
digest = "<sha256:..., set once the builder workflow has pushed>"
base = "docker.io/library/debian:trixie-slim@<sha256:...>"
debian_snapshot = "<a snapshot.debian.org timestamp>"
rustup_init = { version = "<x.y.z>", sha256 = "<...>" }

[conformance]                          # empty until S1 has a release
version = ""
url = ""
sha256 = ""
```

The three manifest hashes were computed on 2026-11-13 and equal the
`.sha256` files published beside each manifest. The fork commits are the
ones the annotated tags point at today (`git ls-remote`).

`cargo xtask check-pins` fails, naming the file and the fix, when
`rust-toolchain.toml` is not `[toolchain.host].channel`; when the `rev` of
the `hermit` dependency in `crates/relay-hermit/Cargo.toml` or in
`Cargo.lock` is not `[fork.hermit-rs].commit`; when a workflow names a
toolchain, a builder digest or a Firecracker version that `pins.toml` does
not; when any workspace member lacks `[lints] workspace = true`; or when a
relay crate's root file lacks `#![forbid(unsafe_code)]`. With `--online` it
also checks that each tag still points at its commit and that each manifest
still has its hash; CI runs that form weekly, not on pull requests.

A bump is one pull request that changes `pins.toml` and whatever
`check-pins` then names. A Hermit bump follows the forks' `CARRIED.md`: new
`bw/<tag>` branches and tags first, then the pins here.

### Lints

In the root `Cargo.toml`, inherited by every member:

```toml
[workspace.lints.rust]
unsafe_code = "forbid"
missing_docs = "warn"
rust_2018_idioms = { level = "warn", priority = -1 }

[workspace.lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
disallowed_types = "deny"
disallowed_methods = "deny"
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
todo = "deny"
unimplemented = "deny"
dbg_macro = "deny"
```

CI runs clippy with `-D warnings`, so every `warn` above fails a pull
request and passes a local build. A pedantic lint that proves to be noise is
turned off by name in this table, in a pull request that says why.

- **`unsafe`.** `forbid` cannot be overridden by an attribute in the code.
  It covers the 2024 edition's unsafe attributes (`no_mangle`,
  `export_name`, `link_section`) as well as blocks, functions and impls.
  Each relay crate's root also carries `#![forbid(unsafe_code)]`, which is
  the kickoff's wording and is what a reader sees first. Where `unsafe` is
  unavoidable is a2: outside this workspace.
- **Panics (GLOBAL-03).** `unwrap`, `expect`, `panic!`, `todo!` and
  `unimplemented!` are errors in non-test code of the relay crates; tests
  may use them (`allow-unwrap-in-tests`, `allow-expect-in-tests` and
  `allow-panic-in-tests` in `clippy.toml`). Release builds abort on a panic
  (`panic = "abort"`): a relay that hits a bug stops instead of continuing
  in an unknown state.
- **Formatting.** `cargo fmt --all --check` is a hard gate. The main
  repository's GLOBAL-02 makes `gofmt` advisory because Go toolchain skew
  reformats untouched files; here the toolchain is pinned, so that reason
  does not apply. `rustfmt.toml` sets only the edition. The Hermit forks use
  hard tabs and nightly-only rustfmt options; this workspace does not follow
  them, so that rustfmt stays on the stable toolchain.
- **No filesystem, no spawned process** (Decision 8; the kickoff's design
  constraints and RELAY-07):
  1. `clippy.toml` at the root lists, under `disallowed-types`:
     `std::fs::File`, `OpenOptions`, `DirBuilder`, `ReadDir`, `DirEntry`,
     and `std::process::Command`, `Child`, `Stdio`; and under
     `disallowed-methods`: every public free function of `std::fs`,
     `std::env::temp_dir`, `std::env::set_current_dir`, and the methods of
     `std::path::Path` that touch a filesystem (`exists`, `try_exists`,
     `metadata`, `symlink_metadata`, `canonicalize`, `read_link`,
     `read_dir`, `is_file`, `is_dir`, `is_symlink`). Each entry's `reason`
     cites RELAY-07 or the no-process rule. `xtask/clippy.toml` is empty of
     them: `xtask` is tooling and reads and writes files.
  2. `cargo xtask lint-sources` parses every `.rs` file under
     `crates/relay-*/src/` and fails on any path or `use` tree that begins
     with `std::fs`, `std::process::Command`, `std::process::Child`,
     `std::process::Stdio`, `std::os::*::fs`, `std::os::*::process`,
     `tokio::fs`, `tokio::process`, `async_std::fs`, `async_process`,
     `smol::fs` or `smol::process`, and on the keyword `unsafe`. It works on
     syntax, so it sees every `cfg` branch on every host, which clippy does
     not: clippy is not run for the Hermit targets at all, because the
     Hermit nightly's clippy has a different lint set from the host's.
     `std::process::exit`, `abort` and `id` are allowed: they spawn nothing.
     Integration tests under `crates/*/tests/` are not scanned and may
     allow the clippy lints at their crate root; unit tests inside `src/`
     get no exception.
  3. `deny.toml` bans the dependency features that bring either in:
     `tokio`'s `fs`, `process` and `full`. M2 extends the list with the
     runtime it chooses.

  What this does not see is a dependency that touches the filesystem
  itself. That is judged when a dependency is admitted (M2), and on Hermit
  the kernel is the backstop: the unikernel is built without `virtio-fs`,
  so there is no device to reach, and Hermit has no process to spawn.
  There is no suppression mechanism in M1. A needed exception is a design
  change, which is the point.
- **The lints are tested.** `tests/lint-fixtures/` is a crate, outside the
  workspace, with one file per forbidden thing (`unsafe`, `std::fs::read`,
  `std::process::Command`, `.unwrap()`). CI runs clippy and `lint-sources`
  on it and requires each to fail with the expected lint named. A lint that
  silently stops firing after a toolchain bump is then a CI failure.

**`deny.toml`.**

```toml
[graph]
targets = ["x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl",
           "x86_64-unknown-hermit", "aarch64-unknown-hermit",
           "aarch64-apple-darwin", "x86_64-pc-windows-msvc"]
all-features = true

[advisories]
yanked = "deny"

[licenses]
allow = ["Apache-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause", "ISC", "0BSD", "Zlib", "Unicode-3.0"]

[bans]
multiple-versions = "deny"
wildcards = "deny"
deny = [
  { crate = "openssl-sys" }, { crate = "openssl" }, { crate = "native-tls" },
  { crate = "cmake" }, { crate = "bindgen" }, { crate = "pkg-config" },
  { crate = "cc", wrappers = ["hermit"] },
]

[[bans.features]]
crate = "tokio"
deny = ["fs", "process", "full"]

[sources]
unknown-registry = "deny"
unknown-git = "deny"
allow-git = ["https://github.com/buildwarden/hermit-rs"]
```

The `deny` list is the kickoff's "prefer pure-Rust crates; no C bindings in
the relay layer" as a check. `cc` is allowed under `hermit` only, because
the `hermit` crate lists it as a build dependency. An exception (a
cryptography provider with assembly or C, for example, which M2 will have to
decide) is a named `wrappers` or `skip` entry added by the design that needs
it. `cargo deny` reads this workspace's graph; the Hermit kernel and loader
are separate workspaces built from the forks and keep their own checks.

### Rules mirrored

This repository has no rule files. Until the Loop Contract and the move of
RELAY-01 to RELAY-08 (M6 in the umbrella) give the relay its own, the main
repository's rules apply by ID, and this table says how each is met here.
`docs/invariants.md` holds the same table with job names, so the contract's
"declare the component's safety invariants" has something to point at.

| Rule | Here | Enforced in M1 by |
|---|---|---|
| GLOBAL-01 comments | Public items carry doc comments | `missing_docs`; review |
| GLOBAL-02 formatting | Stricter: a hard gate, since the toolchain is pinned | `fmt` job |
| GLOBAL-03 errors | `Result` everywhere; no `unwrap`, `expect` or `panic!` outside tests | clippy |
| GLOBAL-04 tests with the change | As written | review; `test` jobs |
| GLOBAL-05 reproducibility | Stricter: every release form must reproduce | `repro` job |
| GLOBAL-06 boundary changes | See below | pull request template; review |
| GLOBAL-07 cross-platform | Tests on Linux x86_64 and aarch64, macOS and Windows; platform code behind `cfg` with stubs | `clippy`, `test`, `native` jobs |
| GLOBAL-08 seams | The relay implements seams 1, 2, 3 and 6 from `buildwarden-specs`. From M2, a change to seam behaviour comes with a `[conformance]` pin at a release that specifies it | `conformance` job (inactive in M1) |
| GLOBAL-09 to GLOBAL-11 | As written | **Defaults and overrides**; review |
| RELAY-01 single-writer ledger | M2's code; restated for Rust at M6 | nothing in M1 |
| RELAY-02 sent equals recorded | M2's code; S1's `relay` suite checks the round trip | nothing in M1 |
| RELAY-03 keys in memory only | M2's code. M1 makes "never written to disk" structural: the relay crates cannot name a filesystem API | Decision 8's three checks |
| RELAY-04 mode parity | Becomes parity across release forms and the two network paths (M6). M1: every form is built and booted on every change | `images`, `smoke` jobs |
| RELAY-05 specs | The specifications are not here | n/a |
| RELAY-06 hot path | A benchmark arrives with the first hot path (M2) | nothing in M1 |
| RELAY-07 diskless | The kickoff's "no filesystem, no persistent storage" | Decision 8's three checks; no `virtio-fs` in the unikernel; no block or filesystem driver in the appliance kernel configuration |
| RELAY-08 configured by the claim | M2's code. The stub reads no flag and no variable | review |
| TEST-01, TEST-02 | Tier 0: `cargo test --workspace`. Tier 1: smoke boots under QEMU, Firecracker and a container runtime, and later the conformance suites, all on hosted runners. Tier 2: native hosts (VZ, Hyper-V) | `test`, `smoke`, `conformance` jobs |
| TEST-03 | Gaps are in this design's front matter | n/a |
| TEST-04 | A smoke boot is not retried | `smoke` job |
| TEST-05 | The suites are S1's | `conformance` job |
| TEST-07 | Jobs run in parallel; the builder image carries the toolchains | CI |
| TEST-08 | No suite exists yet (the main repository's `security-suite` item is closed for re-intake). The Security note says what it should exercise | n/a |
| FLOW-08, FLOW-16, FLOW-17 | Jeff merges; agents push feature branches only, never `main`, never by force, and delete no remote branch | branch protection once public |
| FLOW-18 | a11 | `sessions-private` job |

**What is high-severity under GLOBAL-06 here.** Every change under
`crates/` is a change to the relay. So is a change to what guards or builds
it: the lint tables in `Cargo.toml`, `clippy.toml`, `deny.toml`,
`pins.toml`, `xtask/`, `images/`, `.github/workflows/`, and any commit
carried on a Hermit fork. A pull request that touches any of them fills the
template's Security note: what boundary or guard it touches and how the
posture changes. M1 has no automated check for that; the Loop Contract's
process invariants are where one belongs.

### CI

Five workflows. Third-party actions are pinned by commit, every workflow
starts from `permissions: contents: read`, checkouts use
`persist-credentials: false`, and nothing runs on `pull_request_target`, so
a pull request from a fork runs with no secret and a read-only token.

**`ci.yml`** (workflow `ci`): on pull requests, on pushes to `main`, weekly,
and on demand.

| Job | Runner | Does | Cold run, estimated |
|---|---|---|---|
| `changes` | `ubuntu-24.04` | Classifies the pull request's paths, fail-open as the main repository's does. Docs-only is `docs/**`, top-level `*.md` and `spike/**`; anything else is code | 10 s |
| `fmt` | `ubuntu-24.04` | `cargo fmt --all --check` | 30 s |
| `pins` | `ubuntu-24.04` | `cargo xtask check-pins` (`--online` on the weekly run) | 1 to 2 min |
| `clippy` | `ubuntu-24.04`, `macos-15`, `windows-2025` | `cargo clippy --workspace --all-targets --locked -- -D warnings`; on Linux also `cargo xtask lint-sources` and the lint fixtures | 2 to 4 min |
| `test` | `ubuntu-24.04`, `ubuntu-24.04-arm`, `macos-15`, `windows-2025` | `cargo test --workspace --locked` | 2 to 4 min |
| `test-hermit-toolchain` | `ubuntu-24.04` | `cargo +nightly-2026-02-01 test -p relay-core --locked`: the unit tests under the compiler that builds the unikernel | 2 to 3 min |
| `native` | `ubuntu-24.04` (both musl targets, linked with `rust-lld`), `macos-15`, `windows-2025` | `cargo xtask build native --target <triple>`; runs the stub where the host can | 2 to 3 min |
| `hermit` | `ubuntu-24.04` | `cargo xtask build hermit` for both architectures and the four loader forms, with rustup-installed toolchains, outside the builder. Fast feedback, and it works before the builder image exists; its output is not what ships | 5 to 7 min |
| `deny` | `ubuntu-24.04` | `cargo deny check` | 1 min |
| `images` | `ubuntu-24.04`, in the builder | `cargo xtask images`: every form, both architectures; uploads `dist/` | 12 to 18 min |
| `images-rebuild` | a second `ubuntu-24.04` runner, in the builder | The same build again, independently (**Verification**) | 12 to 18 min |
| `repro` | `ubuntu-24.04` | `cargo xtask repro-compare` on the two `dist/` trees | 1 min |
| `smoke` | `ubuntu-24.04` for x86_64, `ubuntu-24.04-arm` for aarch64 | Boots what `images` built (**Smoke boots**) | 3 to 5 min |
| `conformance` | `ubuntu-24.04` | S1's harness against what `images` built; skipped while `[conformance]` is empty (**Conformance**) | n/a in M1 |
| `ci-ok` | `ubuntu-24.04` | The one check to require. Needs every job above; passes when each succeeded or was skipped, with the main repository's expression: `jq -e 'all(.[]; .result == "success" or .result == "skipped")'` | 5 s |

A docs-only pull request runs `changes` and `ci-ok` and finishes in under a
minute. A code pull request takes about twenty minutes of wall-clock time,
set by `images`, then `repro` and `smoke`. The estimates come from one
measurement (the Hermit kernel and a hello-world app build in about a
minute on four cores; a toolchain installs in half a minute) and from the
main repository's comparable jobs; the first runs replace them with
numbers.

**Caching.** `clippy`, `test`, `native` and `hermit` cache cargo's registry
and their target directories. Caches are written only by runs on `main` and
only read by pull requests, so a pull request cannot plant something `main`
later restores (the reason the main repository's `integration.yml` gives for
its own rule). `images`, `images-rebuild` and `release` use no cache at all:
what ships must not depend on what a cache held. Their toolchains come in
the builder image.

**What needs a native host.** Nothing that gates M1. The VZ boot of the stub
unikernel needs the MacBook and is a tracked, non-blocking validation.
Hyper-V has nothing to boot until M2 gives the appliance a disk form.

**`flow18.yml`** (workflow `flow18`, job `sessions-private`): the main
repository's guard, with the same triggers (pushes to `main`, pull requests,
daily, on demand), running `tools/flow18-check.sh origin`. The script is a
copy of the main repository's `tools/workflow/flow18-check.sh`, kept until
the loop repository supplies one to every component. Required beside
`ci-ok`.

**`audit.yml`**: daily, `cargo deny check advisories` on `main`. A new
advisory against a locked dependency then shows up as a failed scheduled
run, without waiting for the next pull request.

**`builder.yml`**: on pushes to `main` that change `images/builder/**`, and
on demand. Builds the builder image and pushes it to
`ghcr.io/buildwarden/relay-builder` by digest (`packages: write` for this
job only), and prints the digest. The digest reaches `pins.toml` by a pull
request; nothing uses a builder image that `pins.toml` does not name.

**`release.yml`**: on a `v*` tag (**Publication**).

**Code scanning** is a repository setting, not a workflow (a12).

Not in M1: an integration workflow against real drivers (there is no relay),
a benchmark job (RELAY-06), dependency-update automation (there are almost
no dependencies; `audit.yml` covers advisories; M2 decides).

### Reproducible images

**The rule.** For a commit `C`, `cargo xtask images` produces the same bytes
every time, on any machine that can run the builder image. The inputs are
`C`'s tree and what `pins.toml` at `C` names, and nothing else.

**Inputs, and how each is pinned.**

| Input | Pinned by | Checked |
|---|---|---|
| This repository | the commit; images are built from `git archive` of it, so uncommitted files are not in the build | by construction |
| Crates | `Cargo.lock` checksums; `--locked` | by cargo |
| `hermit-rs` fork | commit, as a cargo git dependency | by cargo; `check-pins` |
| Kernel and loader forks | commit | `xtask fetch` fetches the commit by ID, checks `git rev-parse HEAD`, and exports the tree without `.git` |
| The forks' own crates | their `Cargo.lock` files at the pinned commits | the forks' nested builds do not pass `--locked`, so `xtask` hashes each fork's `Cargo.lock` before and after and fails on a change |
| Rust toolchains | channel plus the SHA-256 of the dated channel manifest, which in turn lists the hash of every component | when the builder image is built; weekly by `check-pins --online` |
| C toolchain, `make`, `git` and the rest | the builder image's digest; inside it, a digest-pinned Debian base and one snapshot.debian.org timestamp | by the container runtime, on pull |
| Linux source | SHA-256 of the tarball | before extraction |
| Build date | `SOURCE_DATE_EPOCH` = the commit time of `C` | recorded in the manifest |

**The builder image** (`images/builder/Containerfile`): Debian `trixie-slim`
by digest; packages from a single Debian snapshot (`ca-certificates`,
`curl`, `git`, `xz-utils`, `make`, `gcc`, `libc6-dev`,
`gcc-aarch64-linux-gnu`, `flex`, `bison`, `bc`, `libelf-dev`, `libssl-dev`:
the main repository's kernel build list plus the cross compiler);
`rustup-init` by version and hash; and the three toolchains, each installed
only after its channel manifest matched `pins.toml`: the host toolchain with
both musl targets; the Hermit nightly with `rust-src`, `llvm-tools` and
`x86_64-unknown-none`; the loader nightly with `llvm-tools`,
`x86_64-unknown-none` and `aarch64-unknown-none-softfloat`. Everything is
installed for `root` with `HOME=/root`, so rustup and cargo are at their
default locations, `/root/.rustup` and `/root/.cargo`. That placement is
required, not a convenience: the `hermit` crate's build script strips
`RUSTUP_HOME` and `CARGO_HOME` before it builds the kernel, so the kernel
build only finds a toolchain at the defaults.

The builder image is not itself reproduced bit for bit; it is pinned by
digest, kept in the organization's registry, and public, so that anyone can
rerun a build.

**How a build runs.** `cargo xtask images` on the host is a thin driver. It
refuses a working tree whose `HEAD` is not what the caller named unless told
`--worktree` (below), pulls the builder by digest, and starts one container
with the commit's tree unpacked at `/work/src` and an environment built from
nothing:

```
HOME=/root  PATH=/root/.cargo/bin:/usr/bin:/bin  LC_ALL=C.UTF-8  TZ=UTC
SOURCE_DATE_EPOCH=<commit time>  BW_XTASK=1
```

No variable of the caller or of the CI system is passed through. That is
because of what was measured: with `CI` and `GITHUB_ACTIONS` set, the same
source at the same path builds a different unikernel.

Inside, `xtask` does these in order, each at a fixed path under `/work`:

1. `check-pins`, then `fetch` (the kernel and loader forks, exported to
   `/work/forks/`; the Linux tarball).
2. **Unikernel**, for `x86_64` and `aarch64`:
   `HERMIT_MANIFEST_DIR=/work/forks/hermit-kernel cargo +nightly-2026-02-01
   build --locked -p relay-hermit --release --target <arch>-unknown-hermit
   -Zbuild-std=std,panic_abort -Zbuild-std-features=compiler-builtins-mem`
   (the spike's flags). Then the loaders, in `/work/forks/hermit-loader`:
   `cargo +nightly-2026-08-15 xtask build --target <t> --release` for
   `x86_64-linux` (Firecracker), `x86_64-multiboot` (QEMU), `aarch64-elf`
   (QEMU) and `aarch64-vz`; and for the last, `llvm-objcopy -O binary` to
   the arm64 `Image` that VZ boots, as the spike's Makefile does.
3. **Native**, for both musl targets: `cargo +1.100.0 build --locked -p
   relay-native --release --target <arch>-unknown-linux-musl`, linked with
   `-Clinker=rust-lld -Clink-self-contained=yes`, so no C toolchain touches
   the binary.
4. **Appliance kernel**, for both architectures, from the pinned tarball
   and `images/appliance/kernel-<arch>.config`: a complete, minimal
   configuration (a serial console, the initramfs, virtio over PCI, no
   modules, no block layer, no on-disk filesystems, no debug information,
   no structure randomization). `make olddefconfig` must leave the file
   unchanged, or the build fails. Built with
   `KBUILD_BUILD_TIMESTAMP=@$SOURCE_DATE_EPOCH`,
   `KBUILD_BUILD_USER=buildwarden`, `KBUILD_BUILD_HOST=relay-builder` and
   `KBUILD_BUILD_VERSION=1`; `ARCH=arm64
   CROSS_COMPILE=aarch64-linux-gnu-` for aarch64. Outputs: `bzImage`
   (x86_64) and `Image` (aarch64).
5. **Initramfs**: `xtask` writes a `newc` cpio archive itself, uncompressed,
   holding one file, `/init`, which is the `relay` binary: mode 0755, owner
   0:0, modification time `SOURCE_DATE_EPOCH`, fixed inode numbers. No
   `cpio` or `gzip` program is involved, so their versions cannot matter.
6. **OCI image**: `xtask` writes an OCI image layout itself: one
   uncompressed layer per architecture holding `/relay`, with the same
   normalized metadata; a configuration with `created` =
   `SOURCE_DATE_EPOCH`, entrypoint `/relay`, and the revision as an
   annotation; a manifest per architecture and one index. The index digest
   is the image's identity. No image builder and no base image is involved.
7. **The manifest** and `SHA256SUMS`.

**Time and paths.**

- *Time.* `SOURCE_DATE_EPOCH` is the commit time. `built` honours it in the
  kernel and in the loader. `build_time` does not, which is the carried
  commit of Decision 12: `src/fs/mod.rs` takes its string from
  `built_info::BUILT_TIME_UTC`, which the kernel already generates, and the
  `build-time` dependency is removed. `xtask` refuses to run with a
  `SOURCE_DATE_EPOCH` in its own environment that differs from the commit
  time; the date is not a knob.
- *Paths.* Every build happens at the same absolute paths in the builder
  (`/work/src`, `/work/forks/...`, `/root/.cargo`, `/root/.rustup`), and
  that is the mechanism, because the alternative does not reach far enough:
  the kernel is compiled by a nested cargo that has had `RUSTFLAGS` and
  `CARGO_ENCODED_RUSTFLAGS` removed, so `--remap-path-prefix` given to the
  outer build never applies to the kernel or to the standard library built
  with it. Where `xtask`'s own cargo call does control the flags, which is
  `relay-native`, it also passes `--remap-path-prefix` for the workspace
  root, cargo's home and rustup's home (to `/relay`, `/cargo`, `/rustup`),
  so that M3's host-mode binaries for macOS, which cannot be built in this
  builder, start from flags that already hide the build machine's paths.
- *The host that builds.* One platform, linux/amd64. The aarch64 artifacts
  are cross-built there. `built` records the build host's triple, so a
  build on an arm64 machine is not expected to match, and is not offered.
- *Git state.* The forks are built from exported trees with no `.git`, so
  `built` records no git version, and the result cannot depend on how deep
  a clone was or which tags it had. The fork commits are in the manifest
  instead.

**The canonical forms M1 builds** (Decision 11), all under `dist/`:

| Form | Architecture | Files |
|---|---|---|
| `unikernel` | `x86_64` | `relay-hermit-x86_64` (the application ELF), `hermit-loader-x86_64-linux`, `hermit-loader-x86_64-multiboot` |
| `unikernel` | `aarch64` | `relay-hermit-aarch64`, `hermit-loader-aarch64-elf`, `hermit-loader-aarch64-vz.Image` |
| `appliance` | `x86_64`, `aarch64` | `relay-appliance-<arch>-kernel`, `relay-appliance-<arch>-initramfs.cpio` |
| `oci` | both, one index | `relay-oci/` (an OCI image layout) |
| `host-binary` | linux `x86_64`, `aarch64` | `relay-linux-<arch>` (the same binary the appliance and the OCI image contain) |

A hypervisor boots a unikernel as a pair: the loader as the kernel, the
application as the initial ramdisk. Which loader forms the relay finally
ships, and whether the appliance needs an uncompressed `vmlinux` for
Firecracker or a disk form for Hyper-V, are M3's and M2's decisions; the
manifest lists files and does not care how many there are.

**The manifest**, `dist/relay-manifest.json`, is what seam 8 calls a
published hash per release form. Seam 8 has no specification yet, so this
is version 0 of a format this repository owns until one exists:

```json
{
  "schema": "buildwarden-relay-manifest/0",
  "version": "0.0.1",
  "commit": "<40 hex digits>",
  "source_date_epoch": 1700000000,
  "builder": "ghcr.io/buildwarden/relay-builder@sha256:<...>",
  "pins_sha256": "<sha256 of pins.toml>",
  "forks": {"hermit-kernel": "<commit>", "hermit-loader": "<commit>", "hermit-rs": "<commit>"},
  "forms": [
    {
      "form": "unikernel", "arch": "x86_64",
      "files": [
        {"name": "hermit-loader-x86_64-linux", "role": "loader", "boot": "linux", "size": 0, "sha256": "<...>"},
        {"name": "hermit-loader-x86_64-multiboot", "role": "loader", "boot": "multiboot", "size": 0, "sha256": "<...>"},
        {"name": "relay-hermit-x86_64", "role": "application", "size": 0, "sha256": "<...>"}
      ],
      "requires": ["virtio-rng"],
      "digest": "sha256:<...>"
    },
    {"form": "oci", "index_digest": "sha256:<...>",
     "platforms": [{"arch": "x86_64", "manifest_digest": "sha256:<...>"}, {"arch": "aarch64", "manifest_digest": "sha256:<...>"}]}
  ]
}
```

A form's `digest` is the SHA-256 of its files' `SHA256SUMS` lines
(`<sha256>  <name>`, sorted by name, each ending in a newline), so it can be
recomputed with `sha256sum` alone. `requires` is the start of seam 8's "the
devices a relay VM needs": in M1 it says the one thing M0 established for
every hypervisor, that the unikernel does not start without a virtio entropy
device. M3 adds the network devices and the vsock device. The manifest
contains no time but `source_date_epoch` and no host detail, its keys and
lists are in a fixed order, and it is itself part of what `repro` compares.

**Verification.** `images` and `images-rebuild` are two jobs on two runners
that share nothing but the commit and the builder digest: no cache, no
artifact, different start times. The rebuild also runs its container with a
different hostname and CPU limit. `repro` downloads both `dist/` trees and
runs `cargo xtask repro-compare`, which requires the same set of files and
identical bytes in every one, the manifest included. On a difference it
names the files and uploads both trees, so they can be compared offline. A
failed `repro` fails `ci-ok`: a change that makes any form irreproducible
cannot merge. The same two-build comparison runs inside `release.yml` before
anything is published.

Anyone can repeat it: `cargo xtask images` at the release's commit, with a
container runtime, then compare `dist/relay-manifest.json` with the
published one. `docs/building.md` gives the commands.

**Smoke boots.** `smoke` takes the `images` job's `dist/` and checks that
each form starts and prints the banner within 60 seconds, once, with no
retry (TEST-04):

- Unikernel, aarch64, QEMU: the spike's command line (`-machine
  virt,gic-version=3 -kernel hermit-loader-aarch64-elf -device
  virtio-rng-pci,disable-legacy=on -device
  guest-loader,addr=0x48000000,initrd=relay-hermit-aarch64`, serial to a
  file), with the runner's accelerator in place of the Mac's.
- Unikernel, x86_64, QEMU with the multiboot loader, and Firecracker with
  the `x86_64-linux` loader: with the command lines upstream's loader
  `xtask ci` uses for those targets, plus a virtio entropy device.
  Firecracker is the version the main repository pins (`v1.17.0`), checked
  against the release's own hash as `firecracker.yml` does.
- Appliance, both architectures: QEMU with `-kernel` and `-initrd` and a
  serial console.
- OCI image, both architectures: copied from the layout into the runner's
  container runtime and run.
- Unikernel on VZ (`hermit-loader-aarch64-vz.Image`): not in CI. A native
  session on the MacBook boots it with the spike's `vzrun` and records the
  console log. Non-blocking.

**Publication** (`release.yml`, on a `v*` tag; the tag is pushed by Jeff, or
by an attended session on his word):

1. Check that the tag is on `main` and equals the workspace version.
2. Build, rebuild and compare, as above. A difference stops the release.
3. Create the GitHub release with every file of every form,
   `relay-manifest.json` and `SHA256SUMS`, and sign the last two with
   cosign's keyless flow, as the main repository's release signs its
   checksums. Versions below `0.1.0` are marked pre-release.
4. Push the OCI index to `ghcr.io/buildwarden/buildwarden-relay:<version>`
   and fail unless the registry reports the manifest's `index_digest`. (The
   name `ghcr.io/buildwarden/relay` is the Go relay's.)
5. Put each form's digest in the release notes.

So a release's hashes are published three ways: the signed manifest, the
release notes, and the registry's own digest for the OCI image. How a driver
obtains and checks them is K1's "relay source" and each driver's M6 item.

**What M1 delivers of this:** the builder image, `pins.toml`, the `xtask`
commands, the `images`, `images-rebuild`, `repro` and `smoke` jobs,
`release.yml`, and stub images of every form: a unikernel, an appliance and
an OCI image that boot, print one line and do nothing. It does not deliver a
relay, a disk-image form, a hermetic (network-off) build phase, or
reproducible macOS binaries.

**`--worktree`.** For iterating on the tooling, `cargo xtask images
--worktree` builds the working tree as it is. Its manifest says
`"source": "worktree"` in place of a commit, and `release.yml` refuses such
a manifest.

### Changes in the Hermit forks

One, in `buildwarden/hermit-kernel` (Decision 12, a10):

- Branch `bw/v0.13.2`, one commit: `src/fs/mod.rs` uses
  `crate::built_info::BUILT_TIME_UTC` in place of
  `build_time::build_time_utc!()`, and `Cargo.toml` drops `build-time`.
  `CARRIED.md` gains its row, classed upstream-bound and "Not submitted":
  it removes a dependency and is useful to anyone building Hermit
  reproducibly, but Decision 15 holds it until the end of M6.
- Tag `v0.13.2-bw.2`. `pins.toml` moves to it in the images pull request.
- `spike/Makefile` keeps its `-bw.1` pins; the spike is evidence of what ran
  on 2026-11-07 to 2026-11-11, not a build that tracks the forks.

Whether `built` is what reads the CI's environment was not confirmed, and no
fork change is made for it: the scrubbed environment removes the input
whatever reads it.

### `spike/`

Unchanged and outside the workspace (Decision 13). `README.md` says what it
is and that nothing in it ships. Its two patch files stay, because the
forks' `CARRIED.md` files refer to them by path. The one private path in its
evidence is a15.

### The Loop Contract adopted

The Loop Contract draft's section 8 asks four things of a component
repository: link to the contract from the README and the loop configuration;
fill the local column of its section 1 (the specification's location, the
concrete checks, the queue's contents, the machines and schedules, where
reports are posted, reconciliation dates and owners); declare the safety
invariants; declare the consumables. Its section 3 names the relay's
invariants: three crates and two architectures build; `forbid(unsafe_code)`,
a dependency audit, and the no-filesystem and no-process lints hold.

The contract is a draft outside any repository, and the loop repository does
not exist. The main repository's queue has both items: `loop-contract`
(priority 59, in progress, at its design step) and `loop-repository`
(priority 60, queued, holding the cloud and every host while it runs). S1's
`seam-specs` (priority 61) is in design. So adoption splits by what each
piece needs:

| Work | Needs | When |
|---|---|---|
| The invariants themselves, as CI: three crates, two architectures, `forbid(unsafe_code)`, `cargo deny`, the no-filesystem and no-process checks | nothing | now (M1a) |
| `docs/invariants.md`: each invariant and the job that enforces it | nothing for its content | now; its final form follows the contract |
| The FLOW-18 guard | nothing | now |
| README, CONTRIBUTING, SECURITY | a14 | now |
| Reproducible images and the stub pre-release, which is the content of "declare its consumables" | the kernel fork's tag; the builder image; the repository public for the release | M1a, in the order under **Implementation plan** |
| The link to the contract from the README; the local column; the declarations in the contract's own form | `loop-contract`: the contract's final text and where it lives | M1b |
| A queue for the relay, its loop configuration (per the draft's section 5: Mac-specific work to the MacBook; Hyper-V, Windows and Linux-host work to the Windows desktop), `wf` working across repositories, and iteration reports | `loop-repository` | M1b |
| The relay's first item taken from the loop repository, which is half of P1's "done when" | `loop-repository` | M1b; the item is M1b itself |
| The conformance pin | a release of `buildwarden-specs` (`seam-specs`) | M1b |
| A conformance target that must pass | a relay | M2 |

Until `loop-repository` lands there is no relay queue, and M1a's work is
done as a17 says. Nothing in M1a waits for P1 or S1. The umbrella's "S1
comes before M1's real work" is kept in the sense it was meant: no relay
behaviour is written in M1, and M2, which writes it, starts from S1's
release.

### Going public

Decision 16 puts this in M1; a11 says who acts. The list is run once, in
order, and its results are recorded in the pull request that closes M1a.
"Agent" means a session prepares or checks; "Jeff" means only he, or an
attended session on his word in that session, does it.

Before the change:

1. **Secrets, on every ref** (agent, then Jeff reads the result). Scan
   every branch and the pull request refs, not only `main`, for keys,
   tokens, credentials and addresses. On 2026-11-13 the remote has `main`,
   `spike/vz-hermit` (merged as pull request 1), `spike/vz-net-entitlements`
   and this design's branch. This session scanned `main` only and found
   none (a15).
2. **Private paths and host details** (Jeff rules, a15). The home path in
   `spike/evidence/vz-norng-console.log`; the host details on
   `spike/vz-net-entitlements`.
3. **Pull request and issue text** (Jeff). Pull request 1's description and
   comments become public with the repository, as do existing Actions logs.
4. **Branches** (Jeff). Merged branches are deleted (FLOW-16); the vznet
   branch is resolved per a15. No agent deletes a remote branch.
5. **Licence and notices** (agent, Jeff confirms a14). `LICENSE` is
   Apache-2.0. `NOTICE` matches the main repository's. No template text is
   left: `README.md` describes the relay and its state; `CONTRIBUTING.md`
   is this repository's; `SECURITY.md` exists; `CODE_OF_CONDUCT.md` is as
   a14 decides.
6. **Session records** (agent). `.entire/settings.json` names the private
   sessions repository; `tools/flow18-check.sh origin` passes; the remote
   carries no `entire/` ref.
7. **Secrets and access in settings** (Jeff). No Actions secret is needed
   by any M1 workflow; deploy keys, webhooks and collaborators are as
   intended.
8. **CI** (agent). `ci-ok` and `sessions-private` are green on `main`.

The change, in one sitting (Jeff):

9. Change the visibility.
10. Protect `main`: pull request required, `ci-ok` and `sessions-private`
    required, no force-push, no deletion; turn on "Automatically delete
    head branches". Before step 9 if the plan allows it (a16).
11. Turn on code scanning (a12), secret scanning with push protection,
    dependency alerts and private vulnerability reporting.
12. Actions: the default token read-only; workflows from first-time
    contributors need approval.
13. Make the `relay-builder` package public, so that a third party can
    rerun a build.

After:

14. `v0.0.1` (a13).
15. The main repository's book and README link here. That is a change in
    the main repository's queue, not this one.

### Conformance

S1's harness tests a relay from outside. M1 has no relay, and must not wait
for S1. So M1a builds the place the harness plugs in, and nothing that
depends on the harness existing:

- `pins.toml` has a `[conformance]` table with an empty `version`.
- `conformance/targets/` exists, with a README that says target files in
  S1's format go there.
- `ci.yml` has the `conformance` job. It needs `images`, so what it tests
  is the bytes that would ship. With an empty `version` it prints
  `conformance: not pinned` and is skipped, which `ci-ok` accepts. With a
  version, `cargo xtask conformance` downloads the harness named by
  `[conformance].url`, checks it against `[conformance].sha256` (the hash
  is in this repository, so the release page is not trusted on its own),
  and runs it once for each file in `conformance/targets/`.

The S1 draft says a relay repository may consume a release "through the
module if its CI has Go or through the release binary and its checksum".
This design takes the binary: the relay's CI has no Go toolchain and needs
none. The draft does not yet fix the binaries' names or URLs, so the URL is
a pinned value, not a pattern in code.

M1b, once `buildwarden-specs` has its first release: set the three values,
and prove the wiring once, by hand (`workflow_dispatch`), by running the
harness from this repository's CI against the Go relay's published image
with the main repository's target file for it. That run gates nothing and
adds no target here; it shows that download, verification and execution
work before M2 depends on them.

M2 adds the first targets that must pass (`relay-native` through the `exec`
launcher, the OCI image through the `oci` launcher). M3 adds the unikernel,
which needs the VM launcher the S1 draft leaves to "the relay's M2 or M3
item, or seam 8's item", and host mode over `frames`.

If S1's design changes in review (the target-file format, how releases are
distributed, the harness's name), only `xtask conformance` and the files
under `conformance/` change.

## Defaults and overrides

| Default | Why it is the obvious one | Override |
|---|---|---|
| `cargo build` and `cargo test` at the root act on `relay-core`, `relay-native` and `xtask`, not `relay-hermit` | They work on any host with only the stable toolchain | `cargo xtask build hermit`. A direct cargo build of `relay-hermit` for a Hermit target is refused (it would link the wrong kernel) |
| `cargo xtask images` builds every form for both architectures from `HEAD`, in the builder, with `docker` | It is what CI and a release do | `--form` and `--arch` narrow it; `--runtime podman` replaces docker and is used exclusively, with no detection and no fallback; `--worktree` builds the working tree and marks the manifest |
| `SOURCE_DATE_EPOCH` is the commit time | The standard choice, and the only one that makes a commit determine its images | None. A different value in the caller's environment is an error that says to unset it |
| Release builds abort on panic, check integer overflow, and use one codegen unit with LTO | A relay that hits a bug stops; overflow is never silent | None in M1 |
| The stubs read no flag and no environment variable | RELAY-08: configuration will come by the claim | None |
| The `conformance` job is skipped while `[conformance].version` is empty | There is nothing to run | Setting the pin. A pin whose download or hash fails is an error, never a skip |

Fallbacks: none at run time. A failed pin check, fetch, hash, build, boot or
comparison stops and says which input failed. The one retry is a bounded
one: a download is tried three times, each attempt reported (GLOBAL-11).
The emulation route in a18 is a choice made in the workflow file if arm
runners prove unavailable, not something a run falls back to.

## Cross-driver impact

None. This repository has no driver, and no driver consumes anything M1
builds. For orientation only, the umbrella's expected form per driver, and
the stub of it that exists after M1:

| Driver | Form expected at M6 (umbrella) | Stub after M1 |
|---|---|---|
| container | OCI image | yes |
| qemu | unikernel or appliance | yes, both |
| vz | unikernel, in a second VM; host mode stays available | unikernel yes; macOS host binary is compiled, not shipped |
| hyperv | appliance | kernel and initramfs only; no disk form until M2 |
| firecracker | unikernel or appliance | unikernel yes (x86_64); the appliance needs M2's kernel form |

## Security note

**Boundary:** environment to relay. M1 adds no code on it: the binaries are
stubs that print one line. It is declared because every change to the relay
is high-severity (GLOBAL-06), and because M1 sets up what later guards the
boundary.

**How the posture changes:**

- **The relay's invariants become mechanical.** No `unsafe`, no filesystem
  API, no process API, no unreviewed C dependency, no unknown source. Before
  M1 they are sentences in a planning document.
- **`unsafe` is not removed from the system; it is kept out of this
  workspace.** The Hermit kernel is a kernel and contains `unsafe`. The
  spike report says what follows: on Hermit's single address space the
  kernel's memory safety is the whole boundary inside the VM, and the
  hypervisor is the boundary around it (the kickoff's last design
  constraint). M1 does not change that; it stops the relay's own code from
  adding to it.
- **Build inputs are pinned and checked.** Toolchains, forks, the builder,
  the Linux source. A change to any of them is a visible line in
  `pins.toml`. The unikernel is built with a compiler from February 2026;
  fixes made to rustc and the standard library since then are not in it
  until the forks move (Risks).
- **A published hash will mean one thing.** Two independent builds must
  agree before a pull request merges and before a release publishes. That
  is what lets an executor trust a hash without inspecting an image.
- **Fail-closed entropy is kept.** The stub unikernel already runs on the
  carried kernel, and its manifest already says a virtio entropy device is
  required. `relay-hermit` cannot be built against upstream's kernel by
  accident.
- **The repository becomes public.** Its CI then runs code from strangers'
  pull requests. The workflows give such runs no secret and a read-only
  token, write caches only from `main`, push the builder image only from
  `main`, and publish only from a tag that Jeff pushes. What is already in
  the history is reviewed first (**Going public**).
- **Session records stay private** (FLOW-18), checked daily.

**What the TEST-08 suite should exercise**, when it exists: for M1's
deliverables, that the guards hold against someone trying to get past them.
A relay crate that reaches the filesystem through a re-export or a macro; a
dependency added from an unlisted git source; a `pins.toml` whose toolchain
hash was changed; a release artifact that differs from an independent
rebuild; a workflow change that would hand a fork's pull request a token
with write access. For the relay proper, the cases start in M2 and are the
umbrella's: the existing relay cases against each release form.

## Validation plan

**Tier 0 (every platform, every change):** `cargo test --workspace` on
Linux x86_64 and aarch64, macOS and Windows; `relay-core`'s tests again
under the Hermit nightly; the lint fixtures; `xtask`'s own tests, which
cover `check-pins` (each kind of disagreement), `lint-sources` (each
forbidden path, in each `cfg` position), the cpio and OCI writers (golden
files) and the manifest (a fixed input gives fixed bytes).

**Tier 1 (hosted runners):** every release form builds for both
architectures; two independent builds agree; each form boots and prints its
banner under QEMU, Firecracker (x86_64 unikernel) or a container runtime.

**Tier 2 (native):** the stub unikernel's VZ form boots on the MacBook
(`macos-vz`), non-blocking, recorded with its console log. Hyper-V is a
tracked gap until M2.

**Done when**, for M1a: `ci-ok` and `sessions-private` are green on `main`
with all of the above in place; the a4 trial has an answer; the repository
is public with its checklist recorded; `v0.0.1` is published and a rebuild
from its commit on another machine gives the published manifest. For M1b:
the README links to the Loop Contract and the declarations are in its form;
the relay has completed one item from the loop repository; the conformance
pin is set and the dispatch run against the Go relay's image has passed.

**Not validated by M1, and said so:** that the reproducibility method holds
for a real relay with a TLS stack and an async runtime (M2 and M3 find
out, with the `repro` job already in place); throughput of anything;
macOS binaries' reproducibility.

## Implementation plan

Each task is one pull request to `main` unless it says otherwise, on its own
feature branch, merged by Jeff (FLOW-08). Tasks 1 to 3 can start together;
the rest follow the arrows.

**M1a: nothing here waits for another program item.**

1. **Housekeeping** (documents and the session guard). `README.md`,
   `CONTRIBUTING.md` (set-up, the commands in this design, the pull request
   flow, and the main repository's standards by link), `SECURITY.md`,
   `CODE_OF_CONDUCT.md` per a14, the pull request template,
   `.entire/settings.json`, `tools/flow18-check.sh`, `flow18.yml`, a root
   `.gitignore`, `docs/invariants.md`. Rules: FLOW-18, GLOBAL-06. Needs
   a14's answer before it merges.
2. **Workspace, lints and the first CI.** `Cargo.toml`, the three relay
   crates as stubs, `xtask` with `check-pins`, `lint-sources`, `fetch` and
   `build`; `rust-toolchain.toml`, `pins.toml` (toolchains, forks at
   `-bw.1`, Linux; no builder yet), `clippy.toml`, `deny.toml`,
   `rustfmt.toml`, the lint fixtures; `ci.yml` with `changes`, `fmt`,
   `pins`, `clippy`, `test`, `test-hermit-toolchain`, `native`, `hermit`,
   `deny`, the inactive `conformance` and `ci-ok`; `audit.yml`. Rules:
   GLOBAL-01, GLOBAL-03, GLOBAL-04, GLOBAL-07, RELAY-07, TEST-01.
3. **The kernel fork's commit** (in `buildwarden/hermit-kernel`, a pull
   request to `bw/v0.13.2`; Decision 12). Jeff merges and tags
   `v0.13.2-bw.2` (a10).
4. **The builder image** (after 2). `images/builder/Containerfile` and
   `builder.yml`. After the merge the workflow pushes the image and prints
   its digest.
5. **Image tooling** (after 3 and 4). `xtask images`, `repro-compare` and
   `smoke`; the kernel configurations; the manifest; `pins.toml` gains the
   builder digest and moves the kernel fork to `-bw.2`; `ci.yml` gains
   `images`, `images-rebuild`, `repro` and `smoke`; `docs/building.md`.
   Rules: GLOBAL-05, TEST-02, TEST-04. If a form cannot be made to
   reproduce, that is a return to this design (FLOW-06), not a form left
   out of `repro`.
6. **The loader toolchain trial** (after 5; a4). Build the loader with
   stable `1.97.1`; if every smoke boot and the VZ boot pass, change the
   pin; either way record the result under **Design review** or
   **Rollback notes**.
7. **VZ boot of the stub** (after 5; native, MacBook, non-blocking). The
   console log goes into the pull request of task 5 or 6.
8. **Going public** (after 1, 2 and 5 have merged). The checklist; the
   redaction pull request for the vznet material if a15 is confirmed as A;
   then Jeff's steps 9 to 13.
9. **Release workflow and the stub pre-release** (after 8). `release.yml`;
   Jeff pushes `v0.0.1`; a rebuild elsewhere is compared with the published
   manifest.

**M1b: each task names what it waits for.**

10. *Waits for `loop-contract`.* Link the contract from the README; put
    `docs/invariants.md` and the consumables declaration in the form the
    contract asks for; fill the local column.
11. *Waits for `loop-repository`.* File the relay's queue item (this one)
    there; add the loop configuration this repository needs; complete the
    item through the loop, which gives P1 its relay half.
12. *Waits for the first release of `buildwarden-specs`.* Set
    `[conformance]`; run the dispatch check against the Go relay's image;
    record it.

## Deferred, and to which milestone

**M2** (`relay-core` on the appliance and the OCI image, over the kernel
path; UDP and DNS on the build link):

- All relay behaviour: the claim, the collector client, the ledger writer,
  the proxy, DNS. RELAY-01 to RELAY-03 bind that code as written, before M6
  restates them.
- The TLS and cryptography stack, and with it the first real use of the
  `deny.toml` exception route: the common providers contain C or assembly,
  which the ban on `cc` stops until a design admits one by name.
- An async runtime for Linux that does not close off M3's evaluation on
  Hermit (decisions table, row 14).
- Upstream CA roots for a relay with no filesystem.
- The appliance: its kernel line and configuration (virtio, Hyper-V,
  netfilter), its init and boot channel (reading the kernel command line is
  a filesystem read, which the relay crates may not do; M2 decides whether a
  separate init does it or the lint changes by design), and its disk forms
  and whether any derived form is hashed (a6).
- The OCI image's real contents.
- The first conformance targets.
- `cargo vet` (a8); third-party notices for each form, the kernel's
  dependencies included (a9); a source bundle per release; dependency-update
  automation; a benchmark (RELAY-06); a build phase with the network off.

**M3** (the unikernel on firecracker, qemu and vz over the frame path, with
throughput measured; host mode on Linux first):

- The `hermit` feature set for the relay; the safe wrappers for the packet
  socket and entropy, carried on the `hermit-rs` fork (a2).
- The async runtime on Hermit.
- Host mode: the frame path, adopting an inherited descriptor without
  `unsafe` in this workspace (a2), the dial filter; Linux, then macOS.
- Reproducibility and signing of macOS binaries.
- The harness's VM launcher; conformance targets for the unikernel and host
  mode.
- Which loader forms ship; Firecracker on aarch64.

**M5:** truststore endpoints. **M6:** adoption by each driver; RELAY-04
restated; the Go relay retired; then, and not before, anything raised with
`hermit-os`.

## Risks

- **Reproducibility is shown for one piece.** A hello-world unikernel
  application on one target. The loader, aarch64, the Linux kernel build
  and the hand-written cpio and OCI writers are designed to reproduce and
  have not been seen to. Task 5 is where that is found out, and `repro` is
  the test.
- **Only the builder's output is canonical.** A build outside it, or with
  CI variables in its environment, gives different bytes. A contributor who
  compares a local cargo build with a published hash will see a mismatch;
  `docs/building.md` has to say so plainly.
- **A pinned input can disappear.** Dated nightlies, a Debian snapshot, a
  kernel.org tarball and the forks are all fetched at build time. The
  toolchains are also inside the builder image, which the organization
  hosts. One input is weaker than the rest: the Hermit kernel depends on
  `hermit-os/async-executor` by branch, held to a commit only by the
  kernel's `Cargo.lock`; if that branch is rewritten upstream, the commit
  may stop being fetchable. A fork of it, or the source bundle deferred to
  M2, closes this.
- **The unikernel's compiler is nine months old and the lag will grow.**
  It moves only when BuildWarden replays its carried commits onto a newer
  Hermit release. The MSRV of 1.94 follows from it and can hold back a
  dependency's fixed version.
- **Two compilers build `relay-core`.** The tests run under both; the
  optimized unikernel is still only exercised by booting it.
- **Pushing `unsafe` out of the workspace pushes work into the forks**
  (a2), where review is harder and upstreaming is on hold.
- **The S1 design and the Loop Contract are drafts.** M1b absorbs their
  final shape; M1a is built not to depend on it.
- **CI time.** About twenty minutes for a code change, most of it building
  images twice. If that proves too slow, the rebuild can move to `main` and
  the weekly run, which trades merge-time certainty for speed and needs a
  decision.
- **Hosted arm runners** may not be available to this repository (a18).
- **One person** merges the fork change, tags it, changes the visibility,
  and pushes the release tag. Each is a point where M1a waits.

## Design review

(None yet.)
