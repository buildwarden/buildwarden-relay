---
# Written from the main repository's docs/design/TEMPLATE.md, adapted: this
# repository has no rule files and no front-matter validator yet, and it never
# gets a queue of its own: there is one queue, on the main repository's
# `workflow` branch, and it cannot hold this repository's work yet (a17; see
# "The Loop Contract adopted").
feature: m1-foundation
status: draft
drivers: []              # this repository holds no driver, and M1 changes none
seams: []                # M1 implements no seam. Its release manifest is unstable first content
                         # for seam 8 (relay release forms), which has no specification and no
                         # phase assigned to write it; whether M1 may publish it is a20. The
                         # driver-contract design (K1) names the same forms from the other side.
surfaces: []             # no user-facing surface: the M1 binaries are stubs
security_boundary: env-relay  # any change to the relay is high-severity (GLOBAL-06); M1 adds
                         # no relay behaviour. See the Security note.
alters_relationships: false
design_review: required
native_validation:
  - {host: macos-vz, blocking: true, reason: "only VZ boots the unikernel's aarch64-vz loader form. The boot blocks two things and nothing else: a change of the loader's toolchain pin (task 6) and the v0.0.1 release, which publishes that form's hash (task 9). Each is a boot of the bytes it clears: the pull request's build for task 6, the tagged commit's build for task 9. Every other pull request merges without it"}
tier2_gaps:
  - {host: macos-vz, what: "the aarch64-vz form is booted on VZ once before a release and on a loader pin change, not on every change"}
  - {host: windows-hyperv, what: "boot of the stub appliance on Hyper-V; deferred with the appliance's disk form to M2"}
rules: [GLOBAL-01, GLOBAL-02, GLOBAL-03, GLOBAL-04, GLOBAL-05, GLOBAL-06, GLOBAL-07, GLOBAL-08,
        GLOBAL-09, GLOBAL-10, GLOBAL-11, RELAY-01, RELAY-02, RELAY-03, RELAY-04, RELAY-05,
        RELAY-06, RELAY-07, RELAY-08, BOOT-06, TEST-01, TEST-02, TEST-03, TEST-04, TEST-05,
        TEST-06, TEST-07, TEST-08, FLOW-03, FLOW-05, FLOW-06, FLOW-07, FLOW-08, FLOW-09,
        FLOW-14, FLOW-16, FLOW-17, FLOW-18, FLOW-19, FLOW-20, LINT-01]
                         # rule IDs are the main repository's (docs/development/ at b903f65).
                         # LOOP-01 to LOOP-09 are cited in the text as the loop-contract
                         # design proposes them; they are not on `main` and not listed here
rule_changes: []         # this repository has no rules to change, and a feature's design may
                         # not declare a change to a loop rule; see "Rules mirrored", a24, a25
concepts: [relay-split, relay-release-forms, relay-workspace, relay-lints, relay-ci,
           reproducible-images, release-manifest, hermit-forks, toolchain-pins, going-public,
           loop-contract, one-queue, conformance, program]
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
not reopen them. Where it reads one of the umbrella's sentences in a way the
owner should confirm, or cannot follow one as written, it says so in a
question and does not settle the point itself; those are listed after the
conflicts table under **Prior art**. It lists the umbrella in `related`, as
FLOW-20 asks of a program item's design. FLOW-20 defines a program item as a
queue item, and this design has no queue item: the one queue cannot hold
work in this repository yet, and how M1 is worked until it can is a17.

It was revised on 2026-11-14, before its review, for what Jeff settled that
day about the loop (one queue) and the driver contract, and for an
independent reader's concerns. **Revised on 2026-11-14, before review**,
at the end of **Prior art**, says what changed. Nothing in it is approved.

Rule IDs (`GLOBAL-06`, `RELAY-03`, `FLOW-18`, ...) are the main repository's,
in its `docs/development/` at `b903f65`. "Decision N" is always the
umbrella's Decision N; this design's own decisions are D1 to D15. Its
assumptions are a1 to a28; the umbrella's and other designs' are named as
such ("the umbrella's a11", "`loop-contract`'s a18"). LOOP-01 to LOOP-09
are the rules the `loop-contract` design proposes; they are not on `main`
yet. "Kickoff" is the document *BuildWarden Relay
Unikernel - Fork Kickoff* (2026-11-07), "decisions table" is *Relay Fork -
Decisions for Jeff* (2026-11-07), and "Loop Contract draft" is *BuildWarden
Loop Contract* (draft, 2026-11-07). None of the three is in a repository yet;
the umbrella says P1 and M1 give them homes. The Loop Contract's home is
P1's work. Where the kickoff and the decisions table go is a21. "The change
proposal" is the proposal for one queue that Jeff took as the direction on
2026-11-14; the second entry of the `loop-contract` design's **Design
review** section records it and his answer.

## Problem

`buildwarden-relay` holds the M0 spike and nothing else. On `main` at
`e9b23d5` it has `spike/`, an Apache-2.0 `LICENSE`, a one-line `NOTICE`, and
three files that are still the unedited Amazon open-source template:
`README.md` ("My Project", "TODO: Fill this README out!"), `CONTRIBUTING.md`
and `CODE_OF_CONDUCT.md`. There is no Cargo workspace, no lint configuration, no
CI, no pinned build, and no way to turn a commit into an image. The
repository is private.

Four things depend on that changing, and each has a reason to happen before
relay code is written:

1. **The image hash is load-bearing.** The decisions table (row 13) makes the
   Linux appliance a permanent deliverable because "the hash of the whole
   relay image lets build executors verify they run a current relay without
   introspection or managing their own VMs", and the umbrella's seam 8 gives
   every release form "a published hash". A hash means something only if the same commit always
   builds the same bytes. The kickoff asks for the tooling to be chosen "in
   M1, before anything depends on the hash".
2. **The relay's invariants are cheap to enforce on an empty workspace and
   expensive to retrofit.** No `unsafe`, no filesystem, no spawned process,
   audited dependencies, two architectures: the kickoff and the Loop Contract
   draft (sections 3 and 8) name them. They need to be CI failures from the
   first line of relay code.
3. **Two other program phases expect this repository to be ready.** S1's
   harness (item `seam-specs`) will run against a relay binary or image and
   says that wiring is M1's. P1 is done, in the umbrella as merged, when
   "this repository's loop and the relay's loop each complete one item from
   the loop repository". Since 2026-11-14 there is one loop and one queue,
   and the `loop-contract` design proposes that sentence as one item in the
   main repository and one in this repository each completing from the one
   queue (its a18 and a20). Either way a relay item has to be workable by
   the loop, and the repository has to be one the loop can work in.
4. **The repository goes public at M1** (Decision 16), so what is in it, in
   every commit on every ref, has to be fit to publish.

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
  RELAY-08, TEST-01 to TEST-08, and of the loop's rules FLOW-03, FLOW-07 to
  FLOW-09, FLOW-14 and FLOW-16 to FLOW-20. **Rules mirrored** below says
  which apply to this repository and how.
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
- The S1 design: `docs/design/seam-specs.md` on branch `feat/seam-specs`,
  read on 2026-11-14 at `618ae78` and in the revision then being made to
  it for one queue. Its Design step is done and it waits for its design
  review; it is cited here by section and question, not by line. It plans a Go harness, `bw-conformance`, in
  `buildwarden/buildwarden-specs`, released as a module tag and as static
  binaries with a `SHA256SUMS` file (its Decision 5, and **Releases and how
  they are consumed**), driven by a *target file* (TOML) that names a
  launcher (`exec`, `oci` or `external`) and the attachment points of the
  relay under test (its Decision 6). Its work in the specs repository is
  done from the one queue, with the item, the design and both reviews in
  the main repository (its a4, and **How the loop treats the second
  repository**). **Conformance** below is written against that design and
  says what changes if it changes.
- The P1 design: `docs/design/loop-contract.md` on branch
  `feat/loop-contract`, read on 2026-11-14 at `04cc9bb`. It is in its design
  review. Jeff stopped the first sitting, settled the direction the same
  day (one queue, items that do not collide side by side, items a native
  machine leads), and has since answered its questions; three of his
  answers differ from what that text recommends (its a5, part b of its a15,
  and its a19) and are being folded into it. So it is cited here by
  question ID, as answered, and its rule wording is not quoted as final. It
  turns Jeff's Loop Contract draft into nine rules, LOOP-01 to LOOP-09, in
  `docs/development/loop-contract.md` of the main repository. What this
  design takes from it:
  - *One queue* (its a18). There is one queue, the one on the main
    repository's `workflow` branch, for work in every repository. An item
    names the repositories it works in, in its design until the queue has
    a field for them. A component is a repository that has adopted the
    contract, and it has no queue of its own.
  - *Adoption* (LOOP-08 as proposed, six steps): a link to the contract; a
    profile; the repository's invariants as rules in LINT-01's format under
    a prefix the component names in its own profile (its a16; no prefix is
    registered in the contract); a design template; the consumables
    declared; and the repository set up as FLOW-08, FLOW-16 and FLOW-18
    need, with the trunk protected where the host offers that (its a21).
    The steps need nothing from P1's later items.
  - *A repository that has not adopted* (its a17). An item may work in
    one. The worker is bound there by FLOW-08, FLOW-16, FLOW-17 and
    FLOW-18, and the item's design says which invariants apply, by rule
    ID. `seam-specs` works in the specs repository that way.
  - *Who changes which rule* (its a10). A loop rule (LOOP, FLOW, LINT)
    changes only through a process item. A feature's design may change
    the invariants and the profile of a component it works in, and may
    not declare a change to a loop rule.
  - *P1's items, in order:* `loop-contract` (the rules); `alters-slot`
    (in implementation: `wf` counts items that alter relationships against
    the configured limit of 3); `loop-parallel` (items that do not collide
    run side by side, and the queue records the repositories an item
    names); `loop-native-lead` (a native machine may lead an item from its
    first step); `loop-repository` (`wf`'s gates, branches, pull requests
    and checks in a second repository); and last, the move of the loop to
    its own repository, which the umbrella's Decision 13 names (its a19).
    `loop-repository` is queued and not yet designed; `loop-parallel`,
    `loop-native-lead` and the move are not yet filed.

  **The Loop Contract adopted** below is written against that, with the
  same caveat as for S1's.
- The K1 design: `docs/design/driver-contract.md` on branch
  `feat/driver-contract`, read on 2026-11-14 at `0c29fc3`. Jeff sent its
  first draft back, and this is the redraft, waiting for his review; its
  direction is taken here as settled and its details as proposed. Seam 9
  becomes a command contract: `warden` finds a `warden-driver-<name>`
  binary as git finds a subcommand and runs commands on it; `warden` keeps
  the session, the collector, the claim and the reporting, and a driver
  starts the relay and the environment. Three things in it reach this
  design:
  - *The relay source* (its Decision 11, a3, and **The relay source**) is
    a library of the kit and not part of the contract. It defines
    provisional names in Go: the forms `host-binary`, `oci-image`,
    `appliance` and `unikernel`, and the file roles `binary`, `kernel`,
    `initramfs` and `disk`. The container driver uses it in K1 and the VM
    drivers in K2. It builds no source that downloads a release and checks
    a published hash: that "waits for seam 8".
  - *Seam 8 has no owner.* Its a11: "Seam 8 (relay release forms) has no
    phase that writes it", with a seam 8 item of its own on the S track as
    the recommended answer. This design meets the same gap from the
    relay's side (a20).
  - *The claim.* `warden`'s session sends it, at an endpoint the driver
    reports (its a13), and most of the umbrella's S4 is absorbed into K1
    (its **The boundary with S4 and K2**). What remains of S4, a claim
    endpoint that is not TCP, is proposed for wave 3, beside M3. Nothing
    in M1 depends on who sends the claim; M2's and M3's designs read it.

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
  `HERMIT_MANIFEST_DIR`; that every relay VM is given a virtio entropy
  device, because the carried kernel fails closed without an entropy source
  (on aarch64 the device is the only one) and Rust's `std` then panics
  before `main`; that the loader's `aarch64-vz` form is an arm64
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
  on GitHub's `ubuntu-24.04` and `ubuntu-24.04-arm` runners. Two limits of
  that precedent matter for **Smoke boots**. It accelerates only x86_64
  (`--accel --sudo` is in the x86_64 matrix entry alone); for aarch64 the
  loader's `xtask` runs QEMU without an accelerator, with `-cpu cortex-a72`,
  and its accelerated branch is `todo!()`. And its Firecracker runs boot an
  application built with `--no-default-features`, so without `acpi` and
  `pci`, from a configuration with no entropy device.
- Entropy in the carried kernel (`src/entropy.rs`, commit `0b0d1e3`): the
  pool is seeded from the processor first and from the virtio entropy
  device only if the processor gives nothing. On x86_64 the processor
  source is `RDSEED`; on aarch64 there is none, so the device is the only
  source. The driver is PCI-only (`virtio-rng = ["virtio", "pci"]`).
- The kernel fork has two lock files, `Cargo.lock` and
  `hermit-builtins/Cargo.lock` (`hermit-builtins` is excluded from its
  workspace and built by the kernel's `xtask` with its own cargo call), and
  two git dependencies named by branch in repositories outside the fork
  set: `hermit-os/async-executor` (branch `no_std`) and, as a
  `[patch.crates-io]` entry, `hermit-os/safe-mmio` (branch `be`). Only the
  kernel's `Cargo.lock` holds them to a commit.
- The kernel reads `HERMIT_IP`, `HERMIT_GATEWAY`, `HERMIT_MASK` and
  `HERMIT_DNS1`/`HERMIT_DNS2` with `option_env!` when it is compiled
  (`src/macros.rs`), as defaults for a static network configuration. The
  `hermit` crate's build script removes only `CARGO*` and `RUST*`
  variables, so a `HERMIT_*` variable in the outer build's environment
  reaches the kernel build and is compiled into the image.

### What was measured for this design

To find out what a reproducible Hermit build needs, this session built the
spike's `hello-vz` app for `x86_64-unknown-hermit` twelve times on Linux
x86_64, from copies of the fork tags above with their `.git` directories
removed, with `nightly-2026-02-01`
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
booted. The app was the spike's, which depends on the `hermit` crate by path,
not by git as the workspace will, and sets no `[profile]`, so the workspace's
release profile (LTO, one codegen unit, `panic = "abort"`, stripping) was not
part of what was measured. It shows what is necessary. Whether it is
sufficient is what the `repro` job (Design, **Verification**) decides on
every change.

Also checked: stable Rust is `1.100.0 (0ef1bc386 2026-11-09)`; with it,
`cargo build --release --target <t>` with
`RUSTFLAGS="-Clinker=rust-lld -Clink-self-contained=yes"` produces statically
linked binaries for `x86_64-unknown-linux-musl` and
`aarch64-unknown-linux-musl` on an x86_64 host with no cross C compiler.

### Conflicts between the sources

Between the three planning documents and the umbrella, the umbrella is the
later and wins each of these. Jeff's direction of 2026-11-14 is later than
the umbrella and changes two of its points, noted in the rows they touch
and after the table.

| Topic | Kickoff, decisions table, Loop Contract draft | Umbrella | Here |
|---|---|---|---|
| Release forms | Two: a Hermit unikernel image and "a plain Linux binary/appliance image" (kickoff) | Five kinds: host-mode binaries per platform, unikernel images, the Linux appliance, the OCI image, and an open-ended list (Decision 11, seam 8) | The second binary crate is not Linux-only, so it is not named `relay-linux` (D1, a1) |
| Truststore | "`relay-core` ... trust-store generation"; a CI job runs "the trust-store conformance suite" (kickoff) | S2 specifies the endpoints; M5 builds them (Decision 9) | Not in M1. No JDK in M1's CI |
| First M1 commit | "the first commit of value is a conformance harness ... Wrap the main repo's collector conformance test" (kickoff, recommendation 2) | "The conformance harness comes from S1", in `buildwarden-specs` (Decision 3, phase S1) | M1 builds no harness; it adds the place one plugs in (**Conformance**) |
| Where the Loop Contract lives | "likely the existing BuildWarden sessions repo" (kickoff, open questions; decisions table rows 2, 7 and 8 and the Loop Contract draft's open questions say the same) | Its own public repository, `buildwarden-ai-workflow` or similar; the sessions repository "is private, so the queue and reports would stop being visible beside a public project" (Decision 13) | Decision 13 stands, and the move there is P1's last item (`loop-contract`'s a19). Until it happens the contract is in the main repository's `docs/development/`, and adoption links there (**The Loop Contract adopted**) |
| Queues | A queue per component: "nothing in one component's queue blocks another component's queue" (Loop Contract draft) | "Each component gets its own repository and its own queue" (Decision 2); "The relay's milestones run in the relay repository's queue" | One queue, on Jeff's direction of 2026-11-14 (`loop-contract`'s a18). This repository never has a queue; its work becomes items in the one queue (a17) |
| Where specifications live | "For now, the specification directory in the main BuildWarden project" (decisions table row 5; Loop Contract draft section 2) | `buildwarden/buildwarden-specs` (Decision 3, a10) | This repository holds no seam specification |
| Repository visibility | "a standalone repo in the BuildWarden org from day one" (kickoff); nothing on visibility | Public at M1 (Decision 16) | **Going public** |
| Hermit pins | "pinned to the latest tagged release with a single-place version bump" (kickoff; decisions table row 17) | BuildWarden carries forks (Decision 15) | The pins are fork commits, still in one file (D6) |
| VZ reachability | "NAT with a host-side port forward is the expected answer; vsock ... out of scope unless M0 proves NAT insufficient" | M0's result: two NICs, the build link a socket pair, the host reached over vsock | No effect on M1 beyond the Hermit features the stub enables |
| Async runtime | Decided empirically in M3 (decisions table row 14) | The same; listed as a risk | M1 adds no runtime and bans none |
| Dependency audit | "`cargo-vet` or `cargo-audit` in CI" (kickoff); "dependency audit" (Loop Contract draft section 3) | Silent | `cargo deny` (a8) |

Not a conflict, but worth stating: the Loop Contract draft's build invariant
is "three crates, two architectures". This design keeps three relay crates
and adds one tooling crate, `xtask`, which is not a relay crate and ships in
no image.

**Where this design meets the umbrella itself.** These are not conflicts
the umbrella wins by being later; each is a sentence of the umbrella that
this design reads, cannot follow as written, or finds no owner for. None is
settled here. Each is a question for Jeff:

| The umbrella says | The difficulty | Question |
|---|---|---|
| "The relay's milestones run in the relay repository's queue" | The one-queue direction replaces the sentence: there will be no relay queue. The one queue cannot hold or gate work in this repository until P1's later items land, so M1a is worked outside it until then | a17 |
| "S1 comes before M1's real work, because the relay has no written target until then" | Wave 1 runs P1, S1 and M1 together. This design reads "real work" as relay behaviour, and so puts all of M1a before S1 | a19 |
| Seams 1 to 8 "each get a specification and a black-box conformance suite"; a phase that touches a seam "changes the seam's specification first, then the code" | No phase is given seam 8 (S1 writes 1, 2, 3, 5 and 6). M1's release manifest is the first thing anyone publishes in seam 8's territory | a20 |
| The kickoff and the decisions table "are not yet in any repository; P1 and M1 give them homes" | They are Jeff's documents, the repository becomes public, and nothing says which of them M1 homes, or in what form | a21 |
| Decision 15 names three forks | The shipped kernel has two more git inputs outside the fork set, pinned by branch | a22 |
| Seam 8's forms: "host-mode binary per platform, unikernel image, appliance image, OCI image" | Host mode is M3's (Decision 11). Whether M1's stub release already lists a `host-binary` form for the Linux binary it builds | a27 |
| The VZ networking report is cited as "`spike/vznet/REPORT.md` on its branch `spike/vz-net-entitlements`" | That branch holds host details; a15's recommended option ends with the branch deleted and a redacted copy on `main`, so the umbrella's pointer goes stale. Deleting it meets FLOW-16, and correcting the pointer amends an archived design | a15, a25, a28 |
| "What the TEST-08 suite should exercise: for S2 ...; for S3 ...; for M6, the existing relay cases against each release form" | No relay release before M6 is on that list, the suite does not exist, and its item is closed until after the freeze (Decision 14). TEST-08 as written binds a release that trips GLOBAL-06, which this design reads every relay release as doing | a24 |
| M1 includes "the Loop Contract adopted", and P1 is done when "the relay's loop" completes an item | With one queue, adoption no longer includes a queue. Whether M1 is done at adoption, or only when a relay item has completed from the one queue, which waits for `loop-repository` | a26 |

**The umbrella's sentences on queues.** Where this design quotes the
umbrella it quotes the text merged at `b903f65`. One queue changes its
Decision 2, the sentence on the relay's queue, track R's heading, P1's row
and the wave-1 gate. The `loop-contract` design lists the amendments for
Jeff's approval by name (its a20), to be made in its pull request. The
`driver-contract` design does the same for Decisions 4 and 5, seams 1, 6
and 9 and the K1, K2 and S4 rows (its a18). Neither set is made yet, and
this design proposes none of its own.

### Revised on 2026-11-14, before review

Jeff has not reviewed this design. It was drafted, checked by two reviewers
and revised by 2026-11-13 (`13ce286`). This revision was made on
2026-11-14, before any review sitting, and does three things:

1. **It folds in what Jeff settled on 2026-11-14.** One queue, with no
   queue for this repository; an item may work in a repository that has
   not adopted the contract; a prefix is named in the component's own
   profile; trunk protection where the host offers it; loop rules change
   only through a process item; the loop repository as P1's last item; and
   the driver contract redrafted as a command contract with `warden` as
   the claimant. These rewrite a17, D15, **The Loop Contract adopted**,
   tasks 10 to 12, the trunk-protection steps of **Going public**, and the
   account of K1 and seam 8 (a20).
2. **It takes up thirteen concerns of an independent reader**, each
   checked against this design and the sources. They change: which build
   the VZ boot covers (task 7, **Publication**); how the two places where
   the plan meets a MUST rule are asked (a24 and a25, in place of a waiver
   and an exception that no rule provides for); what is said about M2's
   release and the security suite (a24); how CI pulls the builder image
   while the repository is private, and the release workflow's
   permissions (**CI**); how this file reaches `main` (task 0) and which
   pull request closes M1a (task 9); the front matter's `rules`; the two
   follow-ups in the main repository (a28); a16's order; the `host-binary`
   row (a27); and where the Firecracker trial is recorded (task 5).
3. **It brings citations up to date**: the S1, P1 and K1 designs as read
   on 2026-11-14, and both repositories' settings as read that day.

Questions a1 to a23 keep their IDs. a13, a15, a16, a17, a20 and a21 are
reworded, and a11 gains a sentence. a24 to a28 are new. None is retired.
The table at the head of **Assumed** lists them. Two recommendations
changed with the direction: a17's (no queue for this repository, where it
had "the relay's first queue item is filed in M1b") and, through a26,
what M1 is done at. One changed with a concern: a16's order.

## Decisions

Cited elsewhere in this design as D1 to D15.

1. **Three relay crates in one Cargo workspace, plus `xtask`.**
   `relay-core` (library: all relay logic), `relay-hermit` (binary: the
   unikernel) and `relay-native` (binary `relay`: the Linux appliance, the
   OCI image and host mode, selected at start the way the Go relay's `-mode`
   does). One workspace and one `Cargo.lock`, so every release form ships the
   same version of every dependency. *Rejected:* the kickoff's
   `relay-linux` name, because the umbrella's Decision 11 makes the same binary run in host
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
   every cargo command in CI and in image builds passes `--locked`. For
   this workspace's dependency graph, sources are restricted to crates.io
   and the `hermit-rs` fork, and `cargo deny` checks advisories, licences,
   bans and sources on every change (a8, a9). The kernel and the loader are
   separate workspaces with their own graphs, which `cargo deny` here does
   not see. Those graphs are pinned through the forks' own lock files at
   the pinned commits, which `xtask` holds unchanged during a build. The
   kernel's graph includes two git dependencies outside the fork set (a22).
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
   *Rejected:* `no_std` (D2). *Rejected:* clippy alone: it checks
   only the configuration it compiles, and its lists name items one by one,
   so a function nobody listed passes. *Rejected:* a custom rustc or dylint
   lint: a nightly-bound tool to maintain for what a scan of four small
   crates does.

9. **The `ci` workflow has one check to require, `ci-ok`, as the main
   repository's does.** Its jobs: format, pins, clippy, source scan, tests
   on four hosted platforms, native builds, Hermit builds, `cargo deny`,
   the image build, an independent image rebuild, the comparison of the
   two, smoke boots, and the conformance hook. Branch protection, set when
   the repository becomes public (a16), requires two checks: `ci-ok` and
   the FLOW-18 guard's `sessions-private`, which is a workflow of its own.
   Everything in M1 runs on GitHub-hosted runners
   except the VZ boot, which needs a native host and blocks only the two
   things the front matter names. *Rejected:* requiring each job by name:
   the required list would have to follow every path filter and matrix
   change, which is the reason the main repository gives for `ci-ok`.

10. **Images are built in a builder container pinned by digest, at fixed
    paths, with a scrubbed environment, by `cargo xtask images`** (a5).
    *Rejected:* Nix. It is the more hermetic tool, and the kickoff names it
    first. It loses for M1 on what the forks' build does today: the `hermit`
    crate's build script starts a nested cargo through the rustup proxy with
    its environment stripped, both `xtask`s call `rustup`, and `-Zbuild-std`
    resolves the standard library's own dependencies at build time. Each of
    those needs a workaround or a carried fork commit inside a Nix sandbox,
    and none of that work brings the relay closer. The choice is confined to
    one `xtask` module, so the code to change is small. The cost of changing
    it later is elsewhere: a release's hashes can be reproduced only with
    the tooling of its commit, so a switch changes the bytes of every form
    and leaves two rebuild recipes to keep working (a5). *Rejected:*
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
    covers, unless M2 shows a derivation is byte-reproducible (a6). M1
    publishes these three forms. Whether the Linux binary inside two of
    them is also listed as a form of its own is a27.
    *Rejected:* hashing whatever file a driver boots: `qemu-img`-style
    converters write fresh identifiers into some formats, and the hash would
    then identify a conversion, not a relay.

12. **The kernel fork gains one carried commit and a new tag.** The
    kernel's `build_time_utc!()` has to stop reading the clock; nothing
    outside the kernel source can fix it (**What was measured**). The change
    goes to `bw/v0.13.2` by pull request, classed in `CARRIED.md`, and is
    tagged `v0.13.2-bw.2` (a10). The loader and `hermit-rs` forks stay at
    their `-bw.1` tags. *Rejected:* having `xtask` patch the exported
    kernel tree at build time: the spike moved from patch files to carried
    fork commits for the reasons Decision 15 gives, and a patch applied by
    the build is a carried change with no `CARRIED.md` row. *Rejected:*
    faking the clock inside the builder: every build would depend on a
    preloaded shim reaching a procedural macro run by a nested cargo, and
    the kernel would still embed the time for anyone who builds it another
    way.

13. **`spike/` stays where it is, as evidence, outside the workspace.**
    The umbrella cites `spike/REPORT.md` by that path, and the kernel and
    loader forks' `CARRIED.md` files cite `spike/patches/`. *Rejected:*
    moving it under `docs/`, which breaks those references for no gain;
    deleting it, which removes the record of why each carried commit
    exists. The umbrella's other citation, the VZ networking report on its
    branch, is not kept by this decision; what happens to it is a15.

14. **The repository goes public after the foundation has merged and its CI
    is green on `main`, and before the stub pre-release** (a13, a16), and
    only once every commit that would be published has been scanned and
    Jeff has ruled on what the scan and a15 show. *Rejected:* flipping
    first: the first thing a visitor would see is a template README and a
    spike. *Rejected:* waiting for the Loop Contract or
    for S1: neither changes what is in this repository's history.

15. **M1 runs in two parts.** M1a is everything that depends on nothing
    outside this repository and the forks. M1b is what waits for another
    item: adoption in the Loop Contract's form, which waits for
    `loop-contract` to merge, and the conformance pin, which waits for
    S1's first release. M1 is done when both are (a26). This repository
    gets no queue in either part: its work becomes items in the one queue
    when P1's later items let the queue hold them, and that is P1's work,
    not M1's (a17, a26). M1a waits for no other program item, but it does
    wait for this design's review: its tasks start once the design review
    has approved the design (FLOW-19) and then merge as they are ready.
    M1b's tasks are listed with what each waits for (**The Loop Contract
    adopted**). That M1a may run before S1 lands is a reading of the
    umbrella's order, and is a19. *Rejected:* one part that waits for P1
    and S1: the image tooling, the fork commit and the public repository
    would be held behind items none of them depends on. a19 holds the
    alternative in between. *Rejected:* keeping M1 open until a relay item
    has completed through `wf`'s gates, as this design had it before one
    queue: M1 would wait for most of P1 (a26).

## Questions

### Blocking

None stops this design from being reviewed.

Nothing in the implementation plan starts before the design review has
approved this design. FLOW-07 requires every assumption below to be
confirmed, and FLOW-03 the review to be recorded as approved, before
planning starts; several of the assumptions change what the first tasks
build (a1 the crate name, a3 the toolchains, a9 the allowlist, a11 the
guard, a14 the documents). For an item the queue holds, `wf` enforces that
order. This design has no queue file, because the queue cannot hold work in
this repository yet (a17), so the entry under **Design review** (`approved
at <sha>`) is the only record of the approval, and it is the gate: no M1a
branch is opened before it exists.

Two confirmations are Jeff's alone, a15 and a14, and one more needs his
ruling on content, a21. Two more ask how the plan stands with a MUST rule
that has no exception route, a24 (TEST-08) and a25 (FLOW-16), and only he
can answer those. They are written as assumptions so they are decided in
the design review; the visibility change itself is his act in any case
(a11 of the umbrella).

### Assumed

"Proceeding with X; confirm." Each is confirmed or changed in the design
review (FLOW-19).

Against the text at `13ce286`, after the revision of 2026-11-14:

| | Questions |
|---|---|
| Unchanged | a1 to a10, a12, a14, a18, a19, a22, a23 |
| A sentence added | a11 (the contract as proposed asks the same) |
| Reworded | a13 (its first and third acceptances), a15 (the branch deletion and the umbrella's pointer now point to a25 and a28), a16 (the order, and the two settings as read), a17 (one queue: rewritten), a20 (K1's redraft; a second part on names), a21 (one clause on the Loop Contract's home) |
| New | a24 (the relay's security-testing invariant, in place of a waiver of TEST-08), a25 (the unmerged spike branch and FLOW-16), a26 (M1 done at adoption), a27 (no `host-binary` form in M1), a28 (the two follow-ups in the main repository) |
| Retired | none |

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
  task that tries B.* The pin changes to `1.97.1` only if the loader built
  with it passes every smoke boot in CI and the VZ boot on the MacBook;
  the VZ boot blocks that pull request (FLOW-09), because only VZ runs the
  `aarch64-vz` form. If CI passes and no MacBook session has run, the pin
  stays at A and the trial is recorded as unfinished; M1a does not wait
  for it. C is not tried in M1.
- **a5. Reproducibility tooling: a pinned builder container driven by
  `cargo xtask`.** Options: (A) as stated (D10); (B) Nix flakes;
  (C) Linuxkit for the appliance plus A for the rest. *Proceeding with A.*
  This is the decision in this design that is most expensive to change
  later, so it is the one to look at hardest in review.
- **a6. The published hash covers canonical forms; derived disk formats are
  not hashed in M1.** Options: (A) as stated (D11), with M2 deciding
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
  remote carries no `entire/` ref. The contract, as the `loop-contract`
  design proposes it, asks the same of a component (LOOP-08, step 6), and
  FLOW-18 is one of the four rules that bind a worker in a repository that
  has not adopted (its a17).
- **a12. Code scanning is GitHub's default CodeQL setup, turned on when the
  repository is public, for Rust and for the workflows.** This session
  could not verify that default setup analyses Rust, nor how the main
  repository's CodeQL is configured. Options: (A) default setup, with an
  explicit `codeql.yml` only if default setup does not cover Rust;
  (B) no CodeQL; clippy, `cargo deny` and the source scan are the static
  checks. *Proceeding with A.*
- **a13. M1a ends with a stub pre-release, `v0.0.1`.** The Loop Contract
  draft, section 8, step 4: "Declare its consumables ..., even if the first
  release is a stub." Options: (A) Jeff, or an attended session on his
  word, pushes `v0.0.1` once M1a has merged and the repository is public;
  the release workflow publishes the stub images with their manifest,
  marked as a pre-release that does nothing; (B) no tag until M2 has a
  relay. *Proceeding with A.* The release path and the published hash are
  exercised before any driver depends on them. Confirming A accepts three
  things by name:
  - *`v0.0.1` has no security-suite run.* TEST-08 requires the suite on a
    release that includes changes that trip GLOBAL-06, this design
    declares the env-relay boundary, and no suite exists (the main
    repository's `security-suite` item is closed for re-intake). `v0.0.1`
    would ship without a run, on the grounds that it contains no boundary
    code: the binaries print one line, and what M1 adds are guards, which
    the lint fixtures and the `repro` job test. No rule provides a waiver
    of a MUST rule for one release, so this is not asked as one. It is
    asked as a24: what the relay's own invariant on security testing
    binds, which this design may state for this repository and Jeff
    approves by name.
  - *The manifest format is published before seam 8 is written* (a20).
  - *The bytes `v0.0.1` publishes for the `aarch64-vz` form have booted
    on VZ before the tag is pushed.* M0 built that loader on the Mac. M1
    cross-builds it in the Linux builder and pairs it with an application
    linked against the `-bw.2` kernel, and nothing has booted that pair.
    The build time is in the image: `SOURCE_DATE_EPOCH` is the commit
    time, and `built` writes it into the kernel and the loader. So every
    commit builds different bytes for this form, and a boot of an earlier
    commit's build is not a boot of what the tag publishes. The boot is
    therefore of the `images` job's output for the commit that will be
    tagged, identified by the SHA-256 of the two files booted (task 7).
    It is a blocking native validation for the release (front matter).
- **a14. The repository's public documents mirror the main repository's.**
  `NOTICE` stays as it is: it is word for word the main repository's.
  `README.md` and `CONTRIBUTING.md` are rewritten for this repository.
  `SECURITY.md` is added and gives the same reporting route as the main
  repository's `SECURITY.md`. The template's `CODE_OF_CONDUCT.md` and the
  security section of its `CONTRIBUTING.md` send conduct and vulnerability
  reports to Amazon's and AWS's addresses; the main repository has no
  `CODE_OF_CONDUCT.md`. Options for
  the code of conduct: (A) remove it, as the main repository has none;
  (B) keep it as it is; (C) replace it with one Jeff names. *Proceeding
  with A; this one needs Jeff's explicit word*, because it and the security
  contact are statements made in the project's name.
- **a15. What would be published, and one item for Jeff to rule on.**
  Pull request 1 was merged with a merge commit, so the spike's whole
  history becomes public with the repository, not only the tree on `main`.
  Two scans were made for this design, both on 2026-11-13 and both by
  pattern, with no dedicated secret scanner (none was available to the
  session):
  - *The tree of `main` at `e9b23d5`.* No key, token or credential. One
    private path: `spike/evidence/vz-norng-console.log` line 185 holds the
    spike machine's home directory path, user name included. The probe
    logs in `spike/evidence/` hold the MAC addresses of the host's VZ
    bridge and of virtual interfaces, and addresses on VZ's own NAT
    network. The template's conduct and security addresses are a14.
  - *Every commit reachable from every ref the remote serves* (four
    branches and pull request 1's head; 16 commits), from a mirror clone,
    over the lines each commit adds. The patterns: private key headers,
    cloud-provider, GitHub, Slack and API-key token formats, JSON web
    tokens, `password=`-style assignments, SSH public keys, home
    directory paths, e-mail addresses, private-range IP addresses and MAC
    addresses. No key, token or credential in any commit. History holds
    three things the tip does not: nine patch files under `spike/patches/`
    from before the forks existed, whose `From:` lines carry the same
    author addresses as the commits; a one-line log with an address on
    VZ's NAT network; and, on `spike/vz-net-entitlements` only, the
    material below. Every commit also publishes its author's name and
    e-mail address, which are the maintainer's own.

  The unmerged branch `spike/vz-net-entitlements` has two commits that are
  not on `main`. `spike/vznet/REPORT.md` and its `evidence/` name the
  host's LAN address, its interface names and the services that were
  listening on it, and three of its probe logs hold the same home
  directory path. Options: (A) accept `main`'s history as it is, on the
  condition that the scanner run in **Going public** step 1 finds nothing
  these scans missed; and for the branch, land a redacted copy of the
  report and evidence on `main` by pull request, at the same path,
  `spike/vznet/`, after which Jeff deletes the branch; (B) accept both as
  they are, and merge the branch or leave it; (C) rewrite history.
  *Proceeding with A.* Three things about A are Jeff's to accept by name.
  It deletes a branch whose commits are not contained in trunk. FLOW-16
  says a branch is deleted only after it is shown to be contained in
  trunk, and no rule provides an exception to it; how the deletion stands
  with that rule is a25, and no agent deletes the branch. The umbrella
  cites the report "on its branch `spike/vz-net-entitlements`"; after A
  the citation resolves on `main` at the same path, and the umbrella's
  wording is corrected by the follow-up a28 describes. And a deleted branch's commits can stay
  retrievable from the host by commit ID for some time (general knowledge
  of GitHub, not checked here), so the checklist confirms they are gone
  before the visibility change (step 4). C needs a force-push to `main`,
  which no agent does (FLOW-17), and buys little for a first name that is
  already public as the maintainer's. The branch's host details are a
  different kind of thing, and only Jeff can say they may be published.
- **a16. Order around the visibility change.** Options: (A) Jeff answers
  a14, a15, a21, a24 and a25 in the design review, before any task; task 0
  and tasks 1 to 5 merge while the repository is private, and task 6 too
  if its boot has run; the checklist under **Going public** is run and
  recorded; Jeff, or an attended session on his word, changes the
  visibility, protects `main` and turns on code scanning in the same
  sitting; task 9's release workflow merges in public; then the release
  boot and `v0.0.1`; (B) change the visibility first and build M1a in
  public, which shows a visitor a template README and a spike; (C) hold
  the change until the Loop Contract or S1 has landed, which changes
  nothing about what is in this repository's history. *Proceeding with A*
  (D14). Two settings, as read with `gh api` on 2026-11-14:
  - *Trunk protection cannot be set before the change.* The host answers
    that protecting a branch of this repository needs a paid plan or a
    public repository. The contract asks a component to protect its trunk
    where its host offers that, and lets this repository adopt while
    private (`loop-contract`'s a21). So `main` is protected in the sitting
    that changes the visibility, and until then FLOW-08 is held here by
    the rule and by the sessions' settings, with no repository setting
    behind it. (The main repository's `main` has no protection today
    either; Jeff protects it before `loop-contract`'s pull request
    merges.)
  - *Head branches are kept on merge.* Deleting them is a setting the host
    offers a private repository. Jeff turns it on before task 0's pull
    request merges, so that FLOW-16's cleanup needs no hand deletion while
    M1a's pull requests merge.

  It was not determined what hosted runner time, and which arm runners, a
  private repository in this organization gets. If that is a constraint,
  the aarch64 legs of `test` and `smoke` are switched on by the first pull
  request after the change, and that is recorded with the checklist.
- **a17. Until the one queue can hold work in this repository, M1a is
  worked outside it.** The umbrella says "The relay's milestones run in
  the relay repository's queue". Jeff's direction of 2026-11-14 replaces
  that: there is one queue, on the main repository's `workflow` branch,
  and this repository never gets one of its own (`loop-contract`'s a18).
  An item in that queue may already work in a repository that has not
  adopted the contract (its a17), as `seam-specs` does in the specs
  repository. But that item's design, branch and gates are in the main
  repository. M1's design is here, each of its tasks is a pull request
  here, and `wf` looks for a design and a branch in the main repository
  only. The queue records the repositories an item names from
  `loop-parallel`, and `wf` runs its gates, branches and pull requests in
  a second repository from `loop-repository`. Options: (A) the change
  proposal's answer (its question 10, recommended option), which is part
  of the direction Jeff took: M1a is worked by hand after this design's
  review, in attended sessions, on feature branches of this repository,
  through pull requests Jeff merges. The sessions are bound here by
  FLOW-08, FLOW-16, FLOW-17 and FLOW-18, the four rules `loop-contract`'s
  a17 names for a repository that has not adopted, and by the invariants
  **Rules mirrored** lists. Once `loop-parallel` lands, what is still
  open of M1 is recorded in the one queue as an item that names this
  repository, tracked and not gated. Once `loop-repository` lands, each
  task still open, and every later milestone's work, is an item `wf`
  gates here; (B) hold M1a until `loop-parallel` lands, so that none of
  it is outside the queue's record; (C) recast M1 as one item with one
  pull request, in the main repository's pattern, once the queue can hold
  it; (D) an item for M1 in the one queue now, as `seam-specs` has: this
  design and its reviews would move to the main repository, and `wf`'s
  gates would still see none of the pull requests here. *Proceeding with
  A; confirm it for this design.* This design was itself written outside
  the queue: the `workflow` branch's digest for 2026-11-12 records it as
  drafted "Outside the queue, on Jeff's word", with "No relay queue item
  and no PR". That word covers the drafting. Whether M1a's implementation
  is worked the same way is what this question asks. What A costs, and
  where each thing a queue would carry goes instead:
  - *Program item.* FLOW-20 defines one as a queue item. Under A this
    design is a program item's design with no item until `loop-parallel`
    lets it be recorded, and the freeze and its exemptions are applied to
    it by Jeff's dispatch, not by intake.
  - *The Plan gate.* No tool checks that the review came before the work.
    The **Design review** entry is the gate (**Blocking**, above).
  - *Native validation.* The blocking VZ boots are attended sessions on
    the MacBook that Jeff starts: a native session takes its steps from
    the queue, and the queue has no step for this repository. Once
    `loop-native-lead` lands, a native machine may lead an item from its
    first step, and the MacBook could lead work of this kind. For work in
    this repository that also needs `loop-repository`, which gives the
    native machines a checkout of it and its toolchain; the change
    proposal has a led item in another repository attended only until
    then. The release task names the boot as a precondition, so it
    cannot be skipped unnoticed.
  - *Tracked gaps.* TEST-03 and FLOW-09 put a gap in `tier2_gaps` and on
    the `workflow` branch's native-gap backlog. Under A the two gaps are
    in this design's front matter and in `docs/invariants.md`, and they
    are filed on that backlog once a native session can work in this
    repository (task 11).
  - *What a private repository's work shows in the public queue.* The
    queue, its digest and its reports are public, and this repository is
    private until **Going public**. The `loop-contract` design leaves the
    rule to `loop-repository`, together with this question. Proceeding
    with: before the visibility change, nothing of this repository's
    content (file text, logs, scan results) is written to the queue, the
    digest or a report. An entry gives the item's name, its state, pull
    request numbers and commit IDs, which is what the digest of
    2026-11-12 already says of this design. After the change, relay work
    is written up as any other.

  Under B nothing in this repository starts before `loop-parallel`, which
  is not yet filed. Under C the nine pull requests of M1a become one,
  which gives up merging the housekeeping, the workspace and the fork
  commit as each is ready.
- **a18. Hosted-runner assumptions.** Proceeding on four, of which only
  the first has evidence in the sources:
  - GitHub's hosted x86_64 Linux runners offer `/dev/kvm` once a udev rule
    has opened it. The main repository's `firecracker.yml` (on
    `ubuntu-latest`) installs that rule and then boots Firecracker VMs.
    Whether that workflow has passed on a hosted runner was not checked.
  - `ubuntu-24.04-arm` is available to this repository, and free of charge
    once it is public. Not verified from here.
  - The arm runner is *not* assumed to offer an accelerator. Upstream
    Hermit's CI runs aarch64 QEMU there without one. So every aarch64
    QEMU boot in `smoke` is specified under emulation (TCG) with a named
    CPU, and is the same command line on any host.
  - The arm runner has a container runtime that can run the aarch64 OCI
    image.

  Options: (A) as stated; (B) no aarch64 runner: aarch64 QEMU boots run on
  `ubuntu-24.04` with the same emulated command line, and the aarch64 unit
  tests and the aarch64 OCI run are tracked gaps; (C) self-hosted arm
  runners. *Proceeding with A.* If an arm runner turns out not to be
  available, B is a change to the workflow file made by a pull request,
  not something a run falls back to.
- **a19. M1a proceeds before S1 lands.** The umbrella: "S1 comes before
  M1's real work, because the relay has no written target until then",
  and its wave 1 runs P1, S1 and M1 together. This design reads "real
  work" as work that needs a written target: relay behaviour, which M1
  has none of, and the conformance pin. Under that reading the workspace,
  the lints, CI, the image tooling, the kernel fork commit, going public
  and `v0.0.1` all come before S1. Options: (A) that reading; (B) only
  housekeeping and scaffolding (tasks 1 and 2) before S1, with the image
  tooling, the visibility change and `v0.0.1` after it; (C) nothing in
  this repository before S1's first release. *Proceeding with A.* Nothing
  in tasks 1 to 9 consumes a specification, and the reason the umbrella
  gives for the order does not reach them. The sentence is Jeff's, so the
  reading is his to confirm.
- **a20. `v0.0.1` publishes a release manifest before seam 8 has a
  specification, and names its forms as K1's redraft does where the two
  name the same thing.** The manifest (`buildwarden-relay-manifest/0`:
  form names, file roles, the per-form digest rule, a `requires` list),
  the release's file names and the OCI image name are seam 8 material, and
  a public release makes them something a reader can depend on. The
  umbrella gives seam 8 a specification and a suite, says a phase touching
  a seam changes the specification first, and assigns seam 8 to no phase.
  The K1 redraft raises the same gap (its a11) and defines provisional
  names of its own for its relay-source library. Two things are asked.

  *Whether M1 publishes the manifest.* Options: (A) M1 publishes it as
  version 0, marked unstable in the file and in the release notes; no
  consumer may depend on it; and a named item writes seam 8 before any
  M6 item, or a relay source that pins a release by hash, reads a
  manifest, at which point this format is replaced, not grandfathered
  (K1's redraft builds no such source and says it waits for seam 8);
  (B) a seam 8 stub lands in `buildwarden-specs` first and the manifest
  follows it, which makes `v0.0.1` wait for S1's repository;
  (C) `v0.0.1` ships `SHA256SUMS` only and no manifest. *Proceeding with
  A.* Which item writes seam 8 is not this design's to assign; the
  umbrella leaves it open, and the K1 redraft recommends an S-track item
  of its own (its a11, option a). It needs an owner before M2's design,
  which gives the appliance its real forms.

  *Which names version 0 uses.* Both sets are provisional and neither
  design is reviewed. As drafted, this manifest said `oci` where K1 says
  `oci-image`. Options: (A) this manifest uses K1's provisional names
  wherever both name the same thing: the forms `unikernel`, `appliance`
  and `oci-image`, and `host-binary` when that form appears (a27); the
  roles `kernel` and `initramfs` for the appliance's two files, and
  `binary` for a host binary; it keeps
  roles of its own, `loader` and `application`, for the unikernel, which
  K1 only reserves a name for; (B) this manifest keeps the names as
  drafted and seam 8's writer reconciles the two; (C) K1 takes this
  manifest's names, which is K1's review to decide, not this one's.
  *Proceeding with A*, and the forms table and the manifest below are
  written that way. Three differences remain under A, and they are for
  whoever writes seam 8, not settled here:
  - K1 describes a unikernel as "a single bootable unikernel image" with
    the role `kernel`. M0 found that a hypervisor boots it as a pair, the
    loader in the kernel's place and the application as the initial
    ramdisk, and this manifest lists a loader per boot protocol plus the
    application.
  - K1's `Relay` type holds one file per role. The x86_64 unikernel here
    has two files with the role `loader`, told apart by `boot`.
  - K1's roles `disk` (an appliance as one boot disk) and `binary` inside
    an appliance (a relay appended to the initramfs per build, as the Go
    relay is) have no counterpart here: the disk form is M2's (a6), and
    this appliance carries its relay inside the initramfs, which K1's
    text already allows for.
- **a21. The kickoff and the decisions table: where they go.** The
  umbrella says P1 and M1 give the planning documents homes. P1 homes the
  Loop Contract: in the main repository's `docs/development/` first, and
  in the loop repository when P1's last item moves it. Nothing homes the
  other two, and this design
  cites the kickoff as authority throughout. They are Jeff's documents,
  parts of them are superseded by the umbrella (**Conflicts between the
  sources**), and this repository becomes public. Options: (A) both land
  under `docs/planning/` in task 1, before the visibility change, copied
  from the documents as they stand, each with a header that says the
  umbrella supersedes it where they differ and points at the conflicts
  table; (B) they stay private, and this design's quotations are the
  public record of them; (C) they land in the main repository beside the
  umbrella, as a main-repository item. *Proceeding with A, which is what
  the umbrella's sentence asks of M1; this one needs Jeff's explicit
  word*, because it publishes his planning documents under the project's
  name. Without it task 1 lands neither file, and B is the state the
  repository goes public in.
- **a22. Two of the shipped kernel's inputs are outside the fork set.**
  Decision 15 has BuildWarden carry three forks. The kernel at the pinned
  tag also depends on `hermit-os/async-executor` (branch `no_std`) and
  patches `safe-mmio` to `hermit-os/safe-mmio` (branch `be`). Both are
  held to a commit only by the kernel's `Cargo.lock`. If either branch is
  rewritten upstream, the locked commit may stop being fetchable and the
  kernel stops building from source. Options: (A) leave them, held by the
  lock file, and close the gap with the per-release source bundle deferred
  to M2; (B) fork both into the organization and point the kernel fork at
  them with a carried commit, which widens Decision 15's fork set to five
  and adds two repositories for Jeff to create; (C) vendor the two crates
  into the kernel fork. *Proceeding with A for M1.* `v0.0.1` is a stub,
  and losing the ability to rebuild it costs little. B and C change what
  Decision 15 covers, so they are Jeff's.
- **a23. The Firecracker boot of the stub is a trial, not a gate.** The
  stub is built with the `acpi` and `pci` features (the set M0 booted on
  aarch64). No source shows a Hermit unikernel with that set booting on
  Firecracker: upstream's Firecracker runs use an application without
  them, the kernel's ACPI code panics when it finds no tables, and
  Firecracker presents virtio devices on MMIO unless it is started with
  `--enable-pci`. Options: (A) task 5 tries the boot on Firecracker
  `v1.17.0` with `--enable-pci`; if it prints the banner, the Firecracker
  leg joins `smoke`; if it does not, M1 has no Firecracker leg, the result
  is recorded, and the question goes to M3, which sets the relay's real
  feature set and owns the unikernel on Firecracker; (B) a second
  x86_64 application ELF built without `acpi` and `pci` for Firecracker,
  which doubles the x86_64 unikernel's forms for the sake of a stub and
  has no entropy device, relying on `RDSEED`; (C) no Firecracker boot in
  M1 at all. *Proceeding with A.* QEMU with the multiboot loader is the
  x86_64 unikernel's required smoke boot either way; upstream boots an
  application with `acpi` and `pci` there.
- **a24. What the relay's invariant on security testing binds, starting
  with `v0.0.1`.** TEST-08 (MUST) requires the security suite on a
  release that includes changes that trip GLOBAL-06. This design reads
  every change to the relay, and to what guards or builds it, as tripping
  GLOBAL-06 (**Rules mirrored**), so TEST-08 as written binds every relay
  release, `v0.0.1` included. Three facts stand against that. No suite
  exists: the main repository's `security-suite` item was closed for
  re-intake after the freeze (the umbrella's Decision 14), the freeze
  ends no earlier than wave 4 (its a4), and FLOW-20 exempts only fixes
  for regressions and for security problems. The umbrella's own list of
  what the suite should exercise names S2, S3 and M6, and no relay
  release before M6. And no rule gives a way to waive a MUST rule: the
  main repository's `docs/development/` has no waiver or exception route,
  FLOW-14 knows only rule changes approved by name, and FLOW-20 says
  "Nothing else is relaxed". What this design can do is say which
  invariants bind work in this repository and how (`loop-contract`'s
  a17), and state the relay's own (its a10 lets a feature's design change
  the invariants of the component it works in). TEST-08 is the main
  repository's invariant, not a loop rule, and nothing in the main
  repository changes under any option but D. Options: (A) the relay's
  invariant, written in `docs/invariants.md` in task 1 and as a rule
  under the relay's prefix in task 10: the security suite runs on a
  relay release that contains code on the env-relay boundary. A stub
  release, whose binaries print one line, is outside it, so `v0.0.1`
  ships without a run. The first release with relay behaviour is M2's
  and is inside it. This design cannot promise a suite by then: M2 is
  wave 2 and the suite's item is behind the freeze. So M2's design
  settles with Jeff, before M2 tags anything, whether the suite's item
  comes back early (whether it may is FLOW-20's judgment at intake, and
  his) or M2 ends without a tagged release; (B) the same invariant,
  binding from the first release a driver may adopt, which is M6 and
  matches the umbrella's list; every release before that is a
  pre-release whose notes and manifest say it has had no security-suite
  run; (C) TEST-08 as written, here too: no tag, `v0.0.1` included,
  until a suite exists, which is a13's option B and leaves the release
  path unexercised until after the freeze; (D) an item in the main
  repository changes TEST-08's wording to say when a release is outside
  it, and `v0.0.1` waits for that item. *Proceeding with A; this one
  needs Jeff's explicit word*, because A narrows, for this repository,
  what a MUST rule of the main repository would ask of it.
- **a25. Deleting the unmerged spike branch, and FLOW-16.** a15's
  recommended option ends with `spike/vz-net-entitlements` deleted from
  the remote. Its two commits are not in trunk, and they are deleted for
  that reason: they hold host details that the redacted copy on `main`
  leaves out. FLOW-16 (MUST) says "a branch is deleted only after it is
  shown to be contained in trunk", and gives the reason: "Deleting a
  branch loses any commit not on trunk". No rule provides an exception
  (a24 gives the sources), and FLOW-16 is a loop rule, which only a
  process item changes; this design may not declare a change to it
  (`loop-contract`'s a10). Options: (A) a reading for Jeff to confirm by
  name: FLOW-16 governs the loop's cleanup of a merged feature's branch.
  Removing unpublished material from a repository before it is made
  public is the owner's act, like the visibility change itself (the
  umbrella's a11), and is not a cleanup the rule covers. Jeff first
  keeps the two commits somewhere private (a `git bundle` of the branch,
  or a push of it to a private repository), so that what the rule guards
  against, a lost commit, does not happen. Then he deletes the branch.
  No agent deletes it or prepares the deletion beyond naming the
  command; (B) no deletion: the branch is published as it is (a15's
  option B), or the visibility change waits; (C) a process item amends
  FLOW-16 with a clause for material removed before a repository is made
  public, and the deletion, and so the visibility change, waits for it.
  *Proceeding with A; this one needs Jeff's explicit word.* If he does
  not confirm the reading, C is the route the rules give, and a16's
  order gains that item before step 4 of **Going public**.
- **a26. M1 is done at adoption, not at the relay's first gated item.**
  The umbrella's M1 includes "the Loop Contract adopted". As drafted,
  this design also put into M1b "the relay's first item taken from the
  loop repository", which was half of P1's done-when. With one queue,
  adoption is LOOP-08's six steps as the `loop-contract` design proposes
  them, and a repository's work being in the queue is not one of them:
  that design lists it "beyond the six steps", as what P1's later items
  owe. Options: (A) M1 is done when M1a is done, the six steps are done
  (task 10) and the conformance pin is set (task 12). The first relay
  item that `wf` gates is P1's to complete, with whichever relay work is
  next when `loop-repository` lands (task 11), and M1 does not wait for
  it; (B) as drafted: M1 stays open until a relay item has completed
  through `wf`'s gates. M1 then waits for `loop-parallel`,
  `loop-native-lead` and `loop-repository`, which is most of P1.
  *Proceeding with A.* When M2 may start is the umbrella's wave-1 gate,
  not this design's, and what that gate is with one queue is
  `loop-contract`'s to settle.
- **a27. Whether `v0.0.1` lists a `host-binary` form.** As drafted, the
  forms table had a fourth row, `host-binary`: `relay-linux-x86_64` and
  `relay-linux-aarch64` in `dist/`, the same binary the appliance and the
  OCI image contain, which **Publication** would then release with "every
  file of every form". D11, a6 and **What M1 delivers** name three forms,
  host mode is M3's (the umbrella's Decision 11), and no driver runs a
  Linux host-mode relay today. Options: (A) three forms in M1. The Linux
  binary is in `dist/` only inside the initramfs and the OCI layer, both
  uncompressed, so `repro` still compares its bytes. The `host-binary`
  form first appears in M3, with host mode, for Linux and macOS together;
  (B) four forms: `v0.0.1` also publishes the two Linux binaries as
  `host-binary`, and D11, a6, a13 and **What M1 delivers** say so. It
  exercises the release path for a fourth form early, and publishes under
  the name of host mode a binary that has none. *Proceeding with A*, and
  the forms table below has three rows.
- **a28. The two follow-ups in the main repository after going public.**
  Step 16 of **Going public** needs two edits there: the book and the
  README link to this repository; and, if a15 is confirmed as A, the
  umbrella's pointer to the VZ networking report is corrected, since it
  names a branch that will no longer exist. The umbrella is an archived
  design whose sentences change only with Jeff's approval by name, and a
  new item that is not a program item is filed on hold while the freeze
  stands (FLOW-20). Options: (A) one small item in the queue, filed at
  intake once this repository is public. Its design lists the umbrella
  in `related`, which makes it a program item; whether it is one is
  intake's and the design review's judgment (FLOW-20). It carries the
  links and the corrected pointer, the latter as an amendment Jeff
  approves by name; (B) the two edits ride in the pull request of a
  program item that is open then and already edits the book or amends
  the umbrella (`seam-specs`, `loop-contract` or `driver-contract`), on
  Jeff's word in that item's review; (C) they wait for the end of the
  freeze, and the umbrella's pointer is stale until then. *Proceeding
  with A.* This design files nothing in the queue itself; it names the
  need, and step 16 is done when the item exists.

## Design

### Repository layout

```
buildwarden-relay/
  Cargo.toml                 the workspace, its lints and its release profile
  Cargo.lock                 committed
  rust-toolchain.toml        channel = "1.100.0" (the host toolchain)
  pins.toml                  every external input, by hash (D6)
  clippy.toml                disallowed types and methods for the relay crates
  deny.toml                  advisories, licences, bans, sources
  rustfmt.toml               edition = "2024", nothing else
  .cargo/config.toml         [alias] xtask = "run --package xtask --"
  .entire/settings.json      checkpoint_remote = buildwarden/buildwarden-sessions (a11)
  .github/
    workflows/               ci.yml, flow18.yml, audit.yml, builder.yml, release.yml,
                             conformance-dispatch.yml (M1b)
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
  tests/lint-fixtures/       a workspace member whose cases must each fail a lint
  tools/flow18-check.sh      the FLOW-18 guard: a copy of the main repository's, until a
                             later P1 item says how a second repository gets the loop's checks
  docs/
    design/m1-foundation.md  this file
    design/TEMPLATE.md       this repository's design template (M1b)
    invariants.md            the relay's invariants and the check that enforces each; rules
                             in LINT-01's format from M1b
    (the profile)            M1b; task 10 names the file
    building.md              how to build, rebuild and verify a hash
    planning/                the kickoff and the decisions table, if a21 is confirmed as A
  spike/                     M0, unchanged (D13); spike/vznet/ is added if a15 is confirmed as A
  README.md  CONTRIBUTING.md  SECURITY.md  LICENSE  NOTICE
  AGENTS.md                  the agent context file; links to the Loop Contract (M1b)
```

The relay repository's `CONTRIBUTING.md` sets no convention for designs
today (it is the template). This design sits at `docs/design/<feature>.md`
as the main repository's do.

### The workspace

```toml
[workspace]
resolver = "3"
members = ["crates/relay-core", "crates/relay-hermit", "crates/relay-native", "xtask",
           "tests/lint-fixtures"]
default-members = ["crates/relay-core", "crates/relay-native", "xtask"]
exclude = ["spike"]

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
`[workspace]`, so excluding `spike` changes nothing for them. Every member
takes `version`, `edition`, `rust-version`, `license` and `publish` from
`[workspace.package]` (`publish.workspace = true`); `publish = false` in
every member is what lets `cargo deny` accept dependencies named by path or
by git revision (**`deny.toml`**).

| Crate | Kind | Built for | What M1 creates | Real code arrives |
|---|---|---|---|---|
| `relay-core` | library | every target below | Real, and very small: the crate attributes, the function that formats the start-up banner (`buildwarden-relay <version> <form> <arch>`), and its unit tests | M2 (claim, collector client, ledger writer, proxy, DNS; the kernel network path), M3 (the frame path), M5 (truststores) |
| `relay-hermit` | binary | `x86_64-unknown-hermit`, `aarch64-unknown-hermit` | A stub: prints the banner, waits a second and a half, returns (which powers the VM off). The wait is the spike's `hello-vz` finding: VZ drains the console asynchronously. On any other target its `main` prints that it runs only on Hermit and exits 2, so `--workspace` commands work on every host | M3 |
| `relay-native` | binary `relay` | `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl` (appliance, OCI image, Linux host mode); `aarch64-apple-darwin` (macOS host mode); `x86_64-pc-windows-msvc` (compiled and tested only, GLOBAL-07; the umbrella's a3 defers Windows host mode) | A stub: prints the banner. As PID 1 it then parks forever, because an init that exits panics the kernel; otherwise it exits 0 (**Defaults and overrides**). It reads no flag and no environment variable | M2 (appliance, OCI), M3 (host mode) |
| `xtask` | binary, tooling | the host | Real: `check-pins`, `lint-sources`, `fetch`, `build`, `images`, `repro-compare`, `smoke`, `conformance` | grows with each milestone |
| `lint-fixtures` | library, test only | the host | Cases that must each fail a lint (**Lints**). With no feature enabled it is empty, so `--workspace` commands pass over it | grows with the lint tables |

The platforms for host mode are the ones the Go relay is released for today
(`.goreleaser.yaml` in the main repository: linux/amd64, linux/arm64,
darwin/arm64).

**`no_std`.** None (D2).

**Features.** No relay crate has a cargo feature in M1. A relay crate gains
one only through a design, and no feature may relax a lint or admit a
filesystem or process API. (`lint-fixtures` has one feature per case; it is
not a relay crate and ships nowhere.) `relay-hermit` enables these features
of the `hermit` crate, the set the spike's `hello-vz` booted with on QEMU
and VZ: `acpi`, `pci`, `virtio-console`, `virtio-rng`, with
`default-features = false`. Both of those boots were aarch64. For x86_64
this set was built for this design and has not been booted anywhere:
upstream boots its demo application with `acpi` and `pci` on QEMU, and
boots Firecracker only without them (a23). M3 sets the relay's real set
(the spike's relay prototype used `acpi`, `pci`, `kernel-stack`,
`virtio-console`, `virtio-rng`, `virtio-net`, `net-packet`, `dhcpv4`,
`tcp`, `udp`).

**The `hermit` dependency and the kernel.** `relay-hermit` depends on the
fork by commit:

```toml
[target.'cfg(target_os = "hermit")'.dependencies]
hermit = { git = "https://github.com/buildwarden/hermit-rs", rev = "d73a481110ed6b3e8d233654fabf4cb77266eade", default-features = false, features = ["acpi", "pci", "virtio-console", "virtio-rng"] }
```

Cargo fetches a git dependency to resolve the workspace whatever the target,
so every platform fetches that repository, with its `kernel` submodule,
which points at upstream. That is the cost of one lock file (D1). The kernel
that is actually built is never that submodule: `cargo xtask build hermit` exports the kernel fork
at its pinned commit and sets `HERMIT_MANIFEST_DIR` to it, as the spike did.
A plain `cargo build -p relay-hermit --target x86_64-unknown-hermit` would
silently link upstream's kernel, without the carried commits and so without
fail-closed entropy. To make that impossible, `relay-hermit`'s `build.rs`
fails for a Hermit target unless `xtask` started it (it checks for
`BW_XTASK`), and the message names the command to use. The guard is
expected to fire late: the `hermit` crate declares `links`, so cargo runs
its build script, which builds the submodule's kernel, before
`relay-hermit`'s. The build still fails and nothing is linked. Task 2
checks the order and words the message for it.

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
tag = "v0.13.2-bw.1"                   # becomes v0.13.2-bw.2 (D12)
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

[smoke.firecracker]
version = "v1.17.0"                    # the main repository's pin; checked
                                       # against the release's own sha256 file

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
not; when any workspace member lacks `[lints] workspace = true` or
`publish.workspace = true`; or when a relay crate's root file lacks
`#![forbid(unsafe_code)]`. With `--online` it
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
- **No filesystem, no spawned process** (D8; the kickoff's design
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
- **The lints are tested.** `tests/lint-fixtures/` is a workspace member
  with `[lints] workspace = true`, so it is checked against the same lint
  tables and the same `clippy.toml` as the relay crates, not against a
  copy. (A crate outside the workspace cannot inherit `[workspace.lints]`:
  cargo refuses the manifest, and without the table `unwrap_used` and the
  rest are simply off.) It has one cargo feature per forbidden thing
  (`case-unsafe`, `case-fs-read`, `case-process-command`, `case-unwrap`,
  and so on), each gating one small module. With no feature it compiles
  to nothing, so `cargo clippy --workspace` and `cargo test --workspace`
  pass over it. CI runs `cargo clippy -p lint-fixtures --features <case>`
  for each case, and `cargo xtask lint-sources` on the crate's sources,
  and requires each to fail with the expected lint named. A lint that
  silently stops firing after a toolchain bump is then a CI failure. The
  arrangement was tried for this design on a three-case workspace: the
  whole-workspace run passed and each case failed with its own lint.

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
allow-wildcard-paths = true
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
it.

`wildcards = "deny"` on its own would reject this workspace's own
dependencies: `hermit` is named by git revision and the relay crates name
`relay-core` by path, both without a `version`, and `cargo deny` counts
those as wildcards. `allow-wildcard-paths` exempts path and git
dependencies of crates that are not published, which is why every member
must carry `publish = false` and `check-pins` verifies it. This is from
`cargo deny`'s documentation; the tool was not available to run here. So
task 2 runs `cargo deny check` against the stub workspace before the file
is treated as settled, and checks every key above against the version CI
pins.

`cargo deny` reads this workspace's graph. The Hermit kernel and loader
are separate workspaces built from the forks; the kernel keeps its own
`deny.toml`. Their graphs, the kernel's two branch-named git dependencies
included, are outside what this file can allow or refuse (D5, a22).

### Rules mirrored

This repository has no rule files. Until it adopts the Loop Contract
(task 10) and the umbrella's M6 moves RELAY-01 to RELAY-08, the main
repository's rules apply by ID, and this table says which bind work here
and how each is met. That is what the `loop-contract` design proposes for
an item that works in a repository that has not adopted: the worker is
bound by FLOW-08, FLOW-16, FLOW-17 and FLOW-18, and the item's design says
which invariants apply, by rule ID (its a17). `docs/invariants.md` holds
the same table with job names, and the two tracked native gaps, so the
contract's "declare the component's safety invariants" has something to
point at. In M1a it is a plain table. The contract asks for a component's
invariants as rules in LINT-01's format, under a prefix the component
names in its own profile (`loop-contract`'s a16); that form is M1b's
(**The Loop Contract adopted**). `rule_changes` is empty: nothing here
changes a rule of the main repository, and a24 and a25 are where the plan
meets one it cannot follow as written.

| Rule | Here | Enforced in M1 by |
|---|---|---|
| GLOBAL-01 comments | Public items carry doc comments | `missing_docs`; review |
| GLOBAL-02 formatting | Stricter: a hard gate, since the toolchain is pinned | `fmt` job |
| GLOBAL-03 errors | `Result` everywhere; no `unwrap`, `expect` or `panic!` outside tests | clippy |
| GLOBAL-04 tests with the change | As written | review; `test` jobs |
| GLOBAL-05 reproducibility | Stricter: every release form must reproduce | `repro` job |
| GLOBAL-06 boundary changes | See below | pull request template; review |
| GLOBAL-07 cross-platform | Tests on Linux x86_64 and aarch64, macOS and Windows; platform code behind `cfg` with stubs | `clippy`, `test`, `native` jobs |
| GLOBAL-08 seams | The relay implements seams 1, 2, 3 and 6 from `buildwarden-specs` and writes seam 4, the ledger format. Its releases are one side of seam 8, which the manifest feeds (a20). From M2, a change to seam behaviour comes with a `[conformance]` pin at a release that specifies it | `conformance` job (inactive in M1) |
| GLOBAL-09 to GLOBAL-11 | As written | **Defaults and overrides**; review |
| RELAY-01 single-writer ledger | M2's code; restated for Rust at M6 | nothing in M1 |
| RELAY-02 sent equals recorded | M2's code; S1's `relay` suite checks the round trip | nothing in M1 |
| RELAY-03 keys in memory only | M2's code. M1 makes "never written to disk" structural: the relay crates cannot name a filesystem API | D8's three checks |
| RELAY-04 mode parity | Becomes parity across release forms and the two network paths (M6). M1: every form is built and booted on every change | `images`, `smoke` jobs |
| RELAY-05 specs | The specifications are not here | n/a |
| RELAY-06 hot path | A benchmark arrives with the first hot path (M2) | nothing in M1 |
| RELAY-07 diskless | The kickoff's "no filesystem, no persistent storage" | D8's three checks; no `virtio-fs` in the unikernel. (The stub appliance's kernel also has no block layer and no on-disk filesystem. That is a property of M1's stub configuration, not an invariant: Hyper-V's relay boot channel is a seed ISO, which M2's appliance kernel will have to read) |
| RELAY-08 configured by the claim | M2's code. The stub reads no flag and no variable | review |
| BOOT-06 images carry no per-build network value | The umbrella binds the relay's release forms and images to it. M1's images carry none: the stubs configure no network, and the Hermit kernel's compile-time `HERMIT_IP`, `HERMIT_GATEWAY`, `HERMIT_MASK` and `HERMIT_DNS*` defaults cannot be set, because the builder's environment is built from nothing | the scrubbed build environment; `xtask` refuses to build images with any `HERMIT_*` variable set other than `HERMIT_MANIFEST_DIR` |
| TEST-01, TEST-02 | Tier 0: `cargo test --workspace`. Tier 1: smoke boots under QEMU and a container runtime (and Firecracker, if the a23 trial passes), and later the conformance suites, all on hosted runners. Tier 2: native hosts (VZ, Hyper-V) | `test`, `smoke`, `conformance` jobs |
| TEST-03 | Gaps are in this design's front matter and in `docs/invariants.md`; they are not on the queue's native-gap backlog until a native session can work in this repository (a17, task 11) | n/a |
| TEST-04 | A smoke boot is not retried | `smoke` job |
| TEST-05 | The suites are S1's | `conformance` job |
| TEST-06 coverage | As written: cover behaviour, and the guards heavily; no percentage target. M1's code is the guards, which the lint fixtures and `xtask`'s tests cover case by case | review |
| TEST-07 | Jobs run in parallel; the builder image carries the toolchains | CI |
| TEST-08 | Not mirrored as written; a24 asks what binds here. Under its recommended option the relay's invariant is that the suite runs on a release with code on the env-relay boundary, so not on the stub `v0.0.1`. No suite exists yet (the main repository's `security-suite` item is closed for re-intake), and this design does not promise one by M2. The Security note says what the suite should exercise | the design review, for `v0.0.1` |
| FLOW-03, FLOW-07, FLOW-19 | Every assumption confirmed and the review approved before any task starts | the **Design review** entry; `wf` cannot gate work here yet (a17) |
| FLOW-09 | A VZ boot blocks the loader pin change and the release, each a boot of the bytes it clears; otherwise tracked | task 6's and task 9's preconditions (task 7) |
| FLOW-08, FLOW-16, FLOW-17 | Jeff merges; agents push feature branches only, never `main`, never by force, and delete no remote branch. The one deletion of an unmerged branch in this plan is a25 | the rule and the sessions' settings while the repository is private, since its host offers no branch protection until it is public (a16); branch protection from then on; head branches deleted on merge from task 0 |
| FLOW-14, FLOW-20 | No rule of the main repository is changed from here, and none is waived (a24, a25). This design lists the umbrella in `related` | the design review |
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

Five workflows in M1a. Third-party actions are pinned by commit, every
workflow starts from `permissions: contents: read`, and nothing runs on
`pull_request_target`, so a pull request from a fork runs with no secret
and a read-only token. Checkouts use `persist-credentials: false`, with one
exception: `flow18.yml`, whose script lists the remote's refs and needs
the job's read-only token to do that while the repository is private. The
main repository's `flow18.yml` leaves the credential in place too.

No workflow uses a configured secret; the only credential is the job's own
token. The permissions a job adds to `contents: read`, each for that job
alone:

| Job | Adds | For |
|---|---|---|
| `builder.yml`, its one job | `packages: write` | pushing the builder image |
| `images`, `images-rebuild` (`ci.yml`) and the two builds in `release.yml` | `packages: read` | pulling the builder image while its package is private |
| `release.yml`, the publishing job | `contents: write`, `packages: write`, `id-token: write` | creating the release; pushing the OCI index to the registry; cosign's keyless signature |

**Pulling the builder while the repository is private.** The builder's
package is created by `builder.yml`, from this repository, and is private
until step 14 of **Going public** makes it public. Until then the jobs
that pull it log in to the registry with the job's token, which is why
they add `packages: read`. `ci-ok` has to be green on `main` before the
visibility change (step 9), and it needs `images` and `images-rebuild`,
so this path is exercised while the repository is private, not after.
Once the package is public a pull needs no login, and the pull request
that follows the visibility change removes the login step, so that a
fork's pull request, whose token may not read packages, pulls the same
way as any other. That a package pushed by a repository's own workflow
can be pulled with that repository's job token is general knowledge of
the host, not checked here; task 4's first `images` run finds out, and
if it cannot, the package's access settings are Jeff's to change.

**`ci.yml`** (workflow `ci`): on pull requests, on pushes to `main`, weekly,
and on demand.

| Job | Runner | Does | Cold run, estimated |
|---|---|---|---|
| `changes` | `ubuntu-24.04` | Classifies the pull request's paths, fail-open as the main repository's does. Docs-only is `docs/**`, top-level `*.md` and `spike/**`; anything else is code | 10 s |
| `fmt` | `ubuntu-24.04` | `cargo fmt --all --check` | 30 s |
| `pins` | `ubuntu-24.04` | `cargo xtask check-pins` (`--online` on the weekly run) | 1 to 2 min |
| `clippy` | `ubuntu-24.04`, `macos-15`, `windows-2025` | `cargo clippy --workspace --all-targets --locked -- -D warnings`; on Linux also `cargo xtask lint-sources` and the lint fixtures, one clippy run per case, each required to fail | 2 to 4 min |
| `test` | `ubuntu-24.04`, `ubuntu-24.04-arm`, `macos-15`, `windows-2025` | `cargo test --workspace --locked` | 2 to 4 min |
| `test-hermit-toolchain` | `ubuntu-24.04` | `cargo +nightly-2026-02-01 test -p relay-core --locked`: the unit tests under the compiler that builds the unikernel | 2 to 3 min |
| `native` | `ubuntu-24.04` (both musl targets, linked with `rust-lld`), `macos-15`, `windows-2025` | `cargo xtask build native --target <triple>`; runs the stub where the host can | 2 to 3 min |
| `hermit` | `ubuntu-24.04` | `cargo xtask build hermit` for both architectures and the four loader forms, with rustup-installed toolchains, outside the builder. Fast feedback, and it works before the builder image exists; its output is not what ships | 5 to 7 min |
| `deny` | `ubuntu-24.04` | `cargo deny check` | 1 min |
| `images` | `ubuntu-24.04`, in the builder | `cargo xtask images`: every form, both architectures; uploads `dist/` | 12 to 18 min |
| `images-rebuild` | a second `ubuntu-24.04` runner, in the builder | The same build again, independently (**Verification**) | 12 to 18 min |
| `repro` | `ubuntu-24.04` | `cargo xtask repro-compare` on the two `dist/` trees | 1 min |
| `smoke` | `ubuntu-24.04` for x86_64 (KVM, after the udev rule that opens `/dev/kvm`), `ubuntu-24.04-arm` for aarch64 (emulated, a18) | Boots what `images` built (**Smoke boots**) | 3 to 8 min |
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

**What needs a native host.** One thing: the VZ boot of the stub
unikernel's `aarch64-vz` form, on the MacBook. No hosted runner can run VZ
and nothing else boots that form. It blocks the pull request that changes
the loader's toolchain pin (task 6) and the `v0.0.1` tag (task 9), and no
other merge. Each blocking boot is of the bytes it clears, taken from the
`images` job's uploaded `dist/` for the commit in question (task 7); the
MacBook does not build them, because only a linux/amd64 build is
canonical. After that it is a tracked gap: the form is not booted on
every change. Hyper-V has nothing to boot until M2 gives the appliance a
disk form.

**`flow18.yml`** (workflow `flow18`, job `sessions-private`): the main
repository's guard, with the same triggers (pushes to `main`, pull requests,
daily, on demand), running `tools/flow18-check.sh origin`. The script is a
copy of the main repository's `tools/workflow/flow18-check.sh`, kept until
a later P1 item says how a second repository gets the loop's checks (the
`loop-contract` design hands that question to `loop-repository`). Required
beside `ci-ok` once `main` is protected. Its checkout keeps the job's token, as above: on a private
repository `git ls-remote origin` fails without it, and the job has to be
green on `main` before the visibility change (**Going public**, step 9).

**`audit.yml`**: daily, `cargo deny check advisories` on `main`. A new
advisory against a locked dependency then shows up as a failed scheduled
run, without waiting for the next pull request.

**`builder.yml`**: on pushes to `main` that change `images/builder/**`, and
on demand. Builds the builder image and pushes it to
`ghcr.io/buildwarden/relay-builder` by digest (`packages: write` for this
job only), and prints the digest. The digest reaches `pins.toml` by a pull
request; nothing uses a builder image that `pins.toml` does not name.

**`release.yml`**: on a `v*` tag (**Publication**). Its permissions are in
the table above.

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
| The forks' own crates | every lock file at the pinned commits: the loader's `Cargo.lock`, and the kernel's `Cargo.lock` and `hermit-builtins/Cargo.lock` | the forks' nested builds do not pass `--locked`, so `xtask` hashes every lock file in each exported fork before and after and fails on a change |
| The kernel's two git dependencies (`async-executor`, `safe-mmio`) | a commit each, in the kernel's `Cargo.lock` only; named by branch in its `Cargo.toml` | by cargo, against the lock file; nothing checks that the commits stay fetchable (a22) |
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
exports the commit at `HEAD` with `git archive`, so uncommitted changes are
not in the build (`--worktree`, below, is the exception), pulls the builder
by digest, and starts one container with that tree unpacked at `/work/src`
and an environment built from nothing:

```
HOME=/root  PATH=/root/.cargo/bin:/usr/bin:/bin  LC_ALL=C.UTF-8  TZ=UTC
SOURCE_DATE_EPOCH=<commit time>  BW_XTASK=1
```

No variable of the caller or of the CI system is passed through. That is
because of what was measured: with `CI` and `GITHUB_ACTIONS` set, the same
source at the same path builds a different unikernel. It is also what
keeps a network value out of the image (BOOT-06): the kernel compiles in
`HERMIT_IP` and its siblings when they are set at build time, and the
`hermit` crate's build script would pass them through. `xtask` sets
`HERMIT_MANIFEST_DIR` itself and refuses to build a unikernel, in or out
of the builder, when any other `HERMIT_*` variable is set.

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
  commit of D12: `src/fs/mod.rs` takes its string from
  `built_info::BUILT_TIME_UTC`, which the kernel already generates, and the
  `build-time` dependency is removed. `xtask` refuses to run with a
  `SOURCE_DATE_EPOCH` in its own environment that differs from the commit
  time; the date is not a knob.
- *Paths.* Every build happens at the same absolute paths in the builder
  (`/work/src`, `/work/forks/...`, `/root/.cargo`, `/root/.rustup`), and
  that is the mechanism, because the alternative does not reach far enough:
  the kernel is compiled by a nested cargo that has had `RUSTFLAGS` and
  `CARGO_ENCODED_RUSTFLAGS` removed, so `--remap-path-prefix` given to the
  outer build never applies to the kernel. It can reach everything else:
  `relay-native`; the outer `relay-hermit` build, which compiles the
  application, `std` and their dependencies; and the loader, whose `xtask`
  forwards an outer `CARGO_ENCODED_RUSTFLAGS`. M1 applies it to
  `relay-native` only: `xtask` passes `--remap-path-prefix` for the
  workspace root, cargo's home and rustup's home (to `/relay`, `/cargo`,
  `/rustup`), so that M3's host-mode binaries for macOS, which cannot be
  built in this builder, start from flags that already hide the build
  machine's paths. The unikernel application and the loader rely on the
  fixed paths, like the kernel they are linked or paired with: remapping
  two thirds of an image whose kernel still holds `/root/.rustup` paths
  would not make it buildable anywhere else.
- *The host that builds.* One platform, linux/amd64. The aarch64 artifacts
  are cross-built there. `built` records the build host's triple, so a
  build on an arm64 machine is not expected to match, and is not offered.
- *Git state.* The forks are built from exported trees with no `.git`, so
  `built` records no git version, and the result cannot depend on how deep
  a clone was or which tags it had. The fork commits are in the manifest
  instead.

**The canonical forms M1 builds** (D11), all under `dist/`:

| Form | Architecture | Files |
|---|---|---|
| `unikernel` | `x86_64` | `relay-hermit-x86_64` (the application ELF), `hermit-loader-x86_64-linux`, `hermit-loader-x86_64-multiboot` |
| `unikernel` | `aarch64` | `relay-hermit-aarch64`, `hermit-loader-aarch64-elf`, `hermit-loader-aarch64-vz.Image` |
| `appliance` | `x86_64`, `aarch64` | `relay-appliance-<arch>-kernel`, `relay-appliance-<arch>-initramfs.cpio` |
| `oci-image` | both, one index | `relay-oci/` (an OCI image layout) |

The form names are the K1 redraft's provisional ones (a20). There is no
`host-binary` row: the Linux `relay` binary is in `dist/` only inside the
appliance's initramfs and the OCI image's layer, and the form first
appears with host mode in M3 (a27).

A hypervisor boots a unikernel as a pair: the loader as the kernel, the
application as the initial ramdisk. Which loader forms the relay finally
ships, and whether the appliance needs an uncompressed `vmlinux` for
Firecracker or a disk form for Hyper-V, are M3's and M2's decisions; the
manifest lists files and does not care how many there are.

**The manifest**, `dist/relay-manifest.json`, is what seam 8 calls a
published hash per release form. Seam 8 has no specification and no phase
assigned to write one, so this is version 0 of a format this repository
owns until one exists. It is unstable: the file says so (`"unstable":
true`), the release notes say so, no consumer may depend on it, and the
seam 8 specification replaces it when it is written. Whether M1 may
publish it on those terms is a20.

```json
{
  "schema": "buildwarden-relay-manifest/0",
  "unstable": true,
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
    {"form": "oci-image", "index_digest": "sha256:<...>",
     "platforms": [{"arch": "x86_64", "manifest_digest": "sha256:<...>"}, {"arch": "aarch64", "manifest_digest": "sha256:<...>"}]}
  ]
}
```

The example leaves out the aarch64 unikernel and the two appliance
entries. An appliance entry has the same shape as the unikernel's, with
two files whose roles are `kernel` and `initramfs` (a20).

A form's `digest` is the SHA-256 of its files' `SHA256SUMS` lines
(`<sha256>  <name>`, sorted by name, each ending in a newline), so it can be
recomputed with `sha256sum` alone. `requires` is the start of seam 8's "the
devices a relay VM needs". In M1 it says the one thing M0 established, that
a relay VM is given a virtio entropy device, and it means different things
on the two architectures. On aarch64 the device is the kernel's only
entropy source, and the unikernel does not start without it. On x86_64
the kernel seeds from `RDSEED` when the processor has it and reads the
device only when it does not, and only if the device is on PCI, since the
carried driver is PCI-only; so there the entry is a requirement for hosts
without `RDSEED` and a precaution otherwise. Both forms list
`virtio-rng`, because the rule for a driver is the same on both: attach
the device, on PCI. Saying which hosts can do without it is seam 8's to
specify. M3 adds the network devices and the vsock device. The manifest
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
each form starts and prints the banner, once, with no retry (TEST-04). The
limit is 60 seconds for an accelerated or native run and 180 seconds for an
emulated one; the first runs replace both with measured numbers. A VM that
does not power itself off is stopped by `xtask` once the banner is seen.

- Unikernel, aarch64, QEMU, emulated: `-machine virt,gic-version=3 -cpu
  cortex-a72 -kernel hermit-loader-aarch64-elf -device
  virtio-rng-pci,disable-legacy=on -device
  guest-loader,addr=0x48000000,initrd=relay-hermit-aarch64`, serial to a
  file. This is the spike's command line with upstream's emulated CPU in
  place of `-accel hvf -cpu host`, which works only on the Mac. No
  accelerator is used or looked for (a18), so the command is the same on
  any host. M0 booted this loader and kernel under HVF and VZ, not under
  TCG; upstream boots its own kernel under TCG with this CPU.
- Unikernel, x86_64, QEMU with the multiboot loader, under KVM: the
  command line upstream's loader `xtask ci` uses for that target, plus
  `-device virtio-rng-pci`. This is the x86_64 unikernel's required boot.
  The job first installs the udev rule that opens `/dev/kvm` on a hosted
  runner, as the main repository's `firecracker.yml` does.
- Unikernel, x86_64, Firecracker with the `x86_64-linux` loader: a trial
  in task 5, not a required leg until it has passed (a23). Upstream's
  Firecracker precedent does not cover this stub: it boots an application
  without `acpi` and `pci`, from a configuration with no entropy device.
  The trial starts Firecracker `v1.17.0` (the main repository's pin,
  checked against the release's own hash as `firecracker.yml` does) with
  `--enable-pci` and an entropy device, so that the kernel finds its
  devices on PCI. Without `--enable-pci` Firecracker attaches virtio
  devices on MMIO, where the carried entropy driver would not see one;
  the kernel would then be seeded by `RDSEED` alone.
- Appliance, x86_64: QEMU under KVM with `-kernel`, `-initrd` and a serial
  console. Appliance, aarch64: the same under emulation with `-machine
  virt -cpu cortex-a72`.
- OCI image, both architectures: copied from the layout into the runner's
  container runtime and started detached. The stub is PID 1 in the
  container and so never exits; `xtask` reads the container's log until
  the banner appears, then removes the container.
- Unikernel on VZ (`hermit-loader-aarch64-vz.Image`): not in CI. An
  attended session on the MacBook boots it with the spike's `vzrun` and
  records the console log, with the SHA-256 of the loader and of the
  application it booted. Required before the loader pin changes and
  before `v0.0.1`, each time for the bytes in question (task 7); not run
  on other changes (a17 says how the session is started while the queue
  has no step for this repository).

**Publication** (`release.yml`, on a `v*` tag; the tag is pushed by Jeff, or
by an attended session on his word):

1. Check that the tag is on `main` and equals the workspace version.
   Before pushing the tag, Jeff has the VZ boot's console log for this
   commit's `aarch64-vz` form: the two files of the `images` job's
   `dist/` for this commit on `main`, with their SHA-256 recorded beside
   the log (task 7). An earlier commit's boot does not serve. The build
   time is part of the kernel and of the loader, so no two commits build
   the same bytes for this form, and a digest never carries over. The
   workflow cannot check that the boot happened, so the release task
   does.
2. Build, rebuild and compare, as above. A difference stops the release.
   The release task then compares the manifest's hashes for
   `hermit-loader-aarch64-vz.Image` and `relay-hermit-aarch64` with the
   ones recorded at the boot. They are equal if the build reproduces,
   which is the rule this whole section rests on; a difference is a
   return to this design (FLOW-06), with the pre-release marked as not
   booted.
3. Create the GitHub release with every file of every form,
   `relay-manifest.json` and `SHA256SUMS`, and sign the last two with
   cosign's keyless flow, as the main repository's release signs its
   checksums. Versions below `0.1.0` are marked pre-release.
4. Push the OCI index to `ghcr.io/buildwarden/buildwarden-relay:<version>`
   and fail unless the registry reports the manifest's `index_digest`. (The
   name `ghcr.io/buildwarden/relay` is the Go relay's.) Whether a package
   first pushed from a public repository is itself public was not
   determined; the release task checks, and making it public is Jeff's.
5. Put each form's digest in the release notes.

So a release's hashes are published three ways: the signed manifest, the
release notes, and the registry's own digest for the OCI image. How a driver
obtains and checks them is for a relay source that pins a release, which
K1's redraft does not build and leaves to seam 8 (its a3 and a11), and for
each driver's M6 item, against seam 8's specification, not against this
version 0 (a20).

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

One, in `buildwarden/hermit-kernel` (D12, a10):

- Branch `bw/v0.13.2`, one commit: `src/fs/mod.rs` uses
  `crate::built_info::BUILT_TIME_UTC` in place of
  `build_time::build_time_utc!()`, and `Cargo.toml` drops `build-time`.
  The same commit removes `build-time` from the kernel's `Cargo.lock`.
  If it did not, the nested build, which does not pass `--locked`, would
  rewrite the lock file and `xtask`'s before-and-after check would fail.
  `CARRIED.md` gains its row, classed upstream-bound and "Not submitted":
  it removes a dependency and is useful to anyone building Hermit
  reproducibly, but the umbrella's Decision 15 holds it until the end of M6.
- Tag `v0.13.2-bw.2`. `pins.toml` moves to it in the images pull request.
- `spike/Makefile` keeps its `-bw.1` pins; the spike is evidence of what ran
  on 2026-11-07 to 2026-11-11, not a build that tracks the forks.

Whether `built` is what reads the CI's environment was not confirmed, and no
fork change is made for it: the scrubbed environment removes the input
whatever reads it.

### `spike/`

Unchanged and outside the workspace (D13). `README.md` says what it
is and that nothing in it ships. Its two patch files stay, because the
forks' `CARRIED.md` files refer to them by path. The one private path in its
evidence is a15. If a15 is confirmed as A, a redacted copy of the VZ
networking report and its evidence is added at `spike/vznet/`, the path it
has on its branch, so that the umbrella's citation resolves on `main`.

### The Loop Contract adopted

The contract this repository adopts is the one the `loop-contract` design
finishes (**Prior art**): nine rules, LOOP-01 to LOOP-09, in
`docs/development/loop-contract.md` on the main repository's `main`. It
stays there until P1's last item moves the loop to its own repository.
That design is in review and not merged, so none of it is on `main` yet:
there is no contract to link to and no list of profile terms. This section
is written against it as read on 2026-11-14 and against Jeff's answers to
its questions, cited by ID. Its rule wording may still change.

Jeff's Loop Contract draft, section 8, asks four things of a component
repository: link to the contract from the README and the loop
configuration; fill the local column of its section 1; declare the safety
invariants; declare the consumables. Its section 3 names the relay's
invariants: three crates and two architectures build;
`forbid(unsafe_code)`, a dependency audit, and the no-filesystem and
no-process lints hold. The `loop-contract` design turns that into rule
LOOP-08.

**What adopting means here.** LOOP-08, as proposed, has six steps, and a
repository that has done them is a component. The six need nothing from
P1's later items. For this repository:

| Step | Here | Needs | When |
|---|---|---|---|
| 1. A link, not a copy | `README.md` and a new agent context file, `AGENTS.md`, link to the contract on the main repository's `main`. The link follows the contract's trunk and is not pinned. It changes once, when P1's last item moves the contract to the loop repository | `loop-contract` merged, so that the target exists | M1b, task 10 |
| 2. A profile | One document that fills every term the contract lists, or says `none`. For this repository: Rust and the three toolchains; `main` as trunk; where the rules and designs are; the prefix of its own rules (step 3); the seams it implements and how it pins a specifications release (`[conformance]`); the fast gate (`cargo fmt`, `clippy`, `test`, `xtask check-pins`, `lint-sources`); the checks by class and tier; the host names its native work uses, from the one host table (`macos-vz` in M1); `GLOBAL-06` as read in **Rules mirrored** as its boundary rule; the release workflow; its session-recording configuration; and step 5's declarations | `loop-contract` merged: the term list is the contract's | M1b, task 10 |
| 3. Its invariants as rules | In LINT-01's format (an ID, a severity, a check), under a prefix this repository names in its own profile. No prefix is registered in the contract (`loop-contract`'s a16), so choosing one changes nothing outside this repository; the review of the profile judges that it is unique. `RELAY-` is the main repository's until M6 moves those rules, so the relay's own invariants take another prefix until then, which task 10 proposes. The relay goes on citing the main repository's rules by ID as binding beside its own | The substance: nothing. The form: `loop-contract` merged | M1a for the substance (below); M1b, task 10, for the form |
| 4. A design template | `docs/design/TEMPLATE.md`: the contract's core front matter and sections, plus this repository's. This design follows the main repository's template by hand and is not rewritten | `loop-contract` merged: it names the core keys | M1b, task 10 |
| 5. Its consumables declared | In the profile: what it releases, which is the release forms (seam 8), the first of them the stub pre-release; and what it consumes, which is the specifications release and the three forks | The stub: the kernel fork's tag, the builder image, the repository public. The declaration: `loop-contract` merged | M1a, task 9, for the stub; M1b, task 10, for the declaration |
| 6. The repository set up as FLOW-08, FLOW-16 and FLOW-18 need | Only Jeff merges to `main`, with the trunk protected where the host offers that; head branches deleted on merge; sessions recorded only to the private sessions repository, and the FLOW-18 guard run here (a11). Read on 2026-11-14, this repository is private, keeps head branches on merge, and cannot be protected on its current plan. So the deletion setting is turned on before task 0 merges, the guard lands in task 1, and `main` is protected in the sitting that makes the repository public (a16; `loop-contract`'s a21 lets a repository adopt while private) | Nothing, but for protection, which needs the visibility change | M1a: task 0, task 1, and **Going public** step 11 |

The substance of step 3 is M1a's and waits for nothing: the invariants
themselves as CI jobs (three crates, two architectures,
`forbid(unsafe_code)`, `cargo deny`, the no-filesystem and no-process
checks), and `docs/invariants.md` as a plain table of each invariant and
the job that enforces it. So are the README, `CONTRIBUTING.md` and
`SECURITY.md` (a14), which no step asks for.

Task 10 is the rows that wait only for `loop-contract` to merge. It can
run as soon as that merge happens, whether or not M1a has finished. If the
`loop-contract` design changes before it merges (the steps, the profile's
terms, the rule format, where the contract is), task 10 changes with it
and nothing in M1a does: M1a builds the substance, and task 10 gives it
the contract's form.

**What adopting does not include: a queue.** There is one queue, on the
main repository's `workflow` branch, for work in every repository, and a
component has none of its own (`loop-contract`'s a18). This repository's
work becomes items in that queue which name
`buildwarden/buildwarden-relay`. That is not a step of LOOP-08. It is what
P1's later items owe before the loop's gates run here, and each brings a
part:

| P1 item | State on 2026-11-14 | What it brings for this repository | Until then |
|---|---|---|---|
| `loop-contract` | In its design review | The contract on `main`, so task 10 can run | M1a builds the substance |
| `alters-slot` | In implementation | Nothing here: this design alters no relationship | |
| `loop-parallel` | Not yet filed | The queue records the repositories an item names. What is still open of M1 is recorded as an item that names this repository, tracked and not gated (a17) | M1a is outside the queue, attended, with the **Design review** entry as its gate |
| `loop-native-lead` | Not yet filed | A native machine may lead an item from its first step, so the MacBook could lead work that rests on a VZ boot | The VZ boots are attended sessions that Jeff starts |
| `loop-repository` | Queued, not designed | `wf`'s gates, branches, pull requests and checks in this repository, with `wf` reading its profile; a checkout of it and its toolchain on the native machines; the rule for what a private repository's work shows in the public queue. From then on each relay task is an item `wf` gates, and the first to complete is the relay half of P1's done-when (a26). The two tracked native gaps go on the queue's native-gap backlog | Each task is a pull request worked by hand (a17) |
| The move to the loop repository | Not yet filed; P1's last item | The link of step 1 changes, once | Links to the contract point at the main repository |

What each of those items does is its own design's to settle. The third
column is this design's reading of the `loop-contract` design's hand-off
and of the change proposal, and it promises nothing on their behalf.

**Routing and reconciliation**, where the contract differs from Jeff's
draft and from this design as first drafted:

- *Routing.* The profile lists host names. Which machine serves a host
  name is the one host table's to say, beside the queue, not a
  component's (`loop-contract`'s a15, parts a and c). Jeff's draft,
  section 5, sends Hyper-V, Windows and Linux-host work to the Windows
  desktop; the host table has `qemu-any` on the MacBook, and the table
  wins. Work that any capable machine can do goes to whichever capable
  worker next takes steps, under a lease that can be renewed (part b of
  that question, as Jeff answered it; the mechanism arrives with a later
  P1 item). M1's one native need is `macos-vz`.
- *Reconciliation.* Moving the `[conformance]` pin to a new specifications
  release, or the fork pins to a new Hermit tag, is what the contract
  calls a reconciliation item ("adopt X at version Y"). Once the queue
  holds this repository's work, each is a feature item that FLOW-05 ranks
  with the fixes (`loop-contract`'s a5, as Jeff answered it). Task 12
  sets the first pin by hand.

**What waits for S1**, and is not adoption:

| Work | Needs | When |
|---|---|---|
| The conformance pin | A release of `buildwarden-specs` (`seam-specs`) | M1b, task 12 |
| A conformance target that must pass | A relay | M2 |

Until P1's later items land, M1a's work is done as a17 says. Nothing in
M1a waits for P1 or S1. Whether that is what the umbrella's "S1 comes
before M1's real work" allows is a19: this design reads it as binding
relay behaviour, which M1 has none of, and the conformance pin, which
waits for S1's release.

### Going public

Decision 16 puts this in M1; the umbrella's a11 says who acts. The list is
run once, in order, and its results are recorded in the pull request that
closes M1a (task 9's last, docs-only pull request). "Agent" means a session prepares or checks; "Jeff" means only
he, or an attended session on his word in that session, does it.

Before the change:

1. **Secrets, in every commit** (agent, then Jeff reads the result). The
   visibility change publishes every commit reachable from every ref, and
   pull request 1 was a merge commit, so that is the spike's whole
   history. The scan therefore runs on a mirror clone (`git clone
   --mirror`, which brings every branch and the `refs/pull/*` refs), never
   on a shallow or single-branch clone, and covers every commit, not the
   tips: `gitleaks git --log-opts=--all <mirror>`, at a version the task
   pins and records, followed by the pattern list in a15 for what a secret
   scanner does not look for (home directory paths, private addresses,
   MAC addresses). The output, the tool version and the commit count are
   recorded. On 2026-11-13 the remote has `main`, `spike/vz-hermit`
   (merged as pull request 1), `spike/vz-net-entitlements`, this design's
   branch and `refs/pull/1/head`: 16 commits. The pattern scan made for
   this design covered all of them and found no credential (a15); the
   scanner run has not been made. A finding here stops the list and goes
   back to a15.
2. **Private paths and host details** (Jeff rules, a15). The home path in
   `spike/evidence/vz-norng-console.log`; the host details on
   `spike/vz-net-entitlements`; the author addresses in commit metadata
   and in the old patch files' headers.
3. **Pull request and issue text** (Jeff). Pull request 1's description and
   comments become public with the repository, as do existing Actions logs.
4. **Branches** (Jeff). Merged branches are deleted (FLOW-16):
   `spike/vz-hermit`, merged as pull request 1 before the deletion
   setting was on, by hand; the task branches by the setting. The vznet
   branch is resolved per a15. If that is option A, the redaction pull
   request merges first; Jeff then keeps the branch's two commits
   privately and deletes it, on the reading of FLOW-16 he confirmed in
   a25, or after the process item that question names if he did not; and
   before step 10 he confirms that those commits no longer resolve on the
   remote by ID, or has the host remove them. No agent deletes a remote
   branch.
5. **Licence and notices** (agent, Jeff confirms a14). `LICENSE` is
   Apache-2.0. `NOTICE` matches the main repository's. No template text is
   left: `README.md` describes the relay and its state; `CONTRIBUTING.md`
   is this repository's; `SECURITY.md` exists; `CODE_OF_CONDUCT.md` is as
   a14 decides.
6. **Planning documents** (Jeff, a21). The kickoff and the decisions table
   are either in `docs/planning/` in the form he approved, or recorded
   here as staying private.
7. **Session records** (agent). `.entire/settings.json` names the private
   sessions repository; `tools/flow18-check.sh origin` passes; the remote
   carries no `entire/` ref.
8. **Secrets and access in settings** (Jeff). No configured Actions
   secret is needed by any M1 workflow: each job uses only its own token,
   with the permissions **CI** lists. Deploy keys, webhooks and
   collaborators are as intended.
9. **CI** (agent). `ci-ok` and `sessions-private` are green on `main`.
   While the repository is private, `sessions-private` passes only because
   its checkout keeps the job's token, and `images` and `images-rebuild`
   pull the builder image, whose package is still private, with the job's
   token (**CI**).

The change, in one sitting (Jeff):

10. Change the visibility.
11. Protect `main`: pull request required, `ci-ok` and `sessions-private`
    required, no force-push, no deletion. This is the first moment the
    host offers it: on the current plan a private repository's branches
    cannot be protected (a16). "Automatically delete head branches" is
    already on, from before task 0 merged.
12. Turn on code scanning (a12), secret scanning with push protection,
    dependency alerts and private vulnerability reporting.
13. Actions: the default token read-only; workflows from first-time
    contributors need approval.
14. Make the `relay-builder` package public, and confirm the three Hermit
    forks are public, so that a third party can rerun a build. Read with
    `gh api` on 2026-11-14, all three forks are public, so cargo's fetch
    of the `hermit-rs` fork and `xtask fetch` need no credential. The
    pull request that follows removes the registry login from the jobs
    that pull the builder (**CI**).

After:

15. `v0.0.1` (a13), once task 9's release workflow has merged and the VZ
    boot of the tagged commit's `aarch64-vz` form is recorded (task 7).
16. The main repository's book and README link here, and the umbrella's
    pointer to the VZ networking report is corrected if a15 was confirmed
    as A (it names a branch that no longer exists). Both are changes in
    the main repository, made by the item a28 describes. This design
    files no item; the step is done when that one exists.

### Conformance

S1's harness tests a relay from outside. M1 has no relay, and must not wait
for S1. So M1a builds the place the harness plugs in, and nothing that
depends on the harness existing:

- `pins.toml` has a `[conformance]` table with an empty `version`.
- `conformance/targets/` exists, with a README that says target files in
  S1's format go there.
- `cargo xtask conformance` exists and is tested without a harness: with
  an empty `version` it reports "not pinned" and runs nothing; with a
  pin whose download fails or whose hash differs it is an error, never a
  skip; with a pin and an empty `conformance/targets/`, which is the state
  between M1b and M2, it downloads and verifies the harness and reports
  that there are no targets. `--target <file>` runs exactly that file and
  none from the directory.
- `ci.yml` has the `conformance` job. It needs `images`, so what it tests
  is the bytes that would ship. With an empty `version` it prints
  `conformance: not pinned` and is skipped, which `ci-ok` accepts. With a
  version, `cargo xtask conformance` downloads the harness named by
  `[conformance].url`, checks it against `[conformance].sha256` (the hash
  is in this repository, so the release page is not trusted on its own),
  and runs it once for each file in `conformance/targets/`.

The S1 design (**Releases and how they are consumed**) says the relay
repository consumes a release with its own target files, "through the
module if its CI has Go or through the release binary and its checksum",
and that this wiring is M1's, in the relay repository. Until the queue
can hold an item that names this repository, that is task 12 (a17). This
design takes the binary: the relay's CI has no Go toolchain and needs
none. The S1 design does not yet fix the binaries' names or URLs, so the
URL is a pinned value, not a pattern in code.

M1b, once `buildwarden-specs` has its first release: set the three values,
and prove the wiring once, by hand, by running the harness from this
repository's CI against the Go relay's published image with the main
repository's target file for it. The S1 design keeps that file in the main
repository, at `tools/conformance/targets/relay-oci.toml`, and this
repository does not copy it. A separate workflow,
`conformance-dispatch.yml`, runs on `workflow_dispatch` only and takes
three inputs: the main repository commit to read the target file from, the
file's SHA-256, and the digest of the Go relay's published image. It
fetches the file at that commit and checks the hash. The S1 design's
target file names the image that the main repository's `make conformance`
builds locally (`buildwarden-relay:conformance`, under **The harness**),
not the published one, so the workflow pulls `ghcr.io/buildwarden/relay`
at the given digest and gives it the name the target file uses. Then it
runs `cargo xtask conformance --target <file>`. That run gates nothing and
adds no target here; it shows that download, verification and execution
work before M2 depends on them. The S1 design's relay targets run on
Linux, in a sandbox the launcher builds from namespaces; what that needs
of a hosted runner is found by task 12's run.

M2 adds the first targets that must pass (`relay-native` through the `exec`
launcher, the OCI image through the `oci` launcher). M3 adds the unikernel,
which needs a launcher for VM images, and host mode over `frames`. The S1
design (its a6) builds no VM launcher itself and leaves it to whichever
item first has an image and a CI that boots it: the relay's M2 or M3 item,
or seam 8's.

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
| The `relay` stub, after the banner, parks forever when it is process 1 and exits 0 when it is not | Process 1 is the appliance's init and a container's main process. An init that exits panics the kernel, and a relay container that exits at once would look like a crash. Anywhere else a stub has nothing to wait for | None. The stub decides by its process ID alone, not by a flag. The smoke test ends a parked stub itself: it stops the VM or removes the container once the banner is seen. M2 replaces the stub and this behaviour |
| The aarch64 QEMU smoke boots are emulated, with a named CPU | The same command on any runner, and no accelerator is assumed (a18) | None in M1; no accelerator is detected |
| The `conformance` job is skipped while `[conformance].version` is empty | There is nothing to run | Setting the pin. A pin whose download or hash fails is an error, never a skip |

Fallbacks: none at run time. A failed pin check, fetch, hash, build, boot or
comparison stops and says which input failed. The one retry is a bounded
one: a download is tried three times, each attempt reported (GLOBAL-11).
Moving the aarch64 legs to an x86_64 runner (a18, option B) is a change to
the workflow file if arm runners prove unavailable, not something a run
falls back to. The Firecracker leg is in `smoke` or it is not, by what the
task 5 trial found (a23); a run does not skip it.

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
| firecracker | unikernel or appliance | unikernel on x86_64 only if the a23 trial boots it; the appliance needs M2's kernel form |

## Security note

**Boundary:** environment to relay. M1 adds no code on it: the binaries are
stubs that print one line. It is declared because every change to the relay
is high-severity (GLOBAL-06), and because M1 sets up what later guards the
boundary.

**How the posture changes:**

- **The relay's invariants become mechanical.** No `unsafe`, no filesystem
  API, no process API, no unreviewed C dependency, and no unknown source,
  in this workspace's code and its dependency graph. Before M1 they are
  sentences in a planning document. The guarantee stops at the workspace's
  edge: the Hermit kernel and loader that ship in the unikernel are built
  from the forks, with their own dependency graphs, which include two git
  dependencies outside the fork set (a22). Those are pinned, by the forks'
  lock files, but not checked by `cargo deny` here.
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
  carried kernel, and its manifest already lists the virtio entropy
  device. `relay-hermit` cannot be built against upstream's kernel by
  accident.
- **No image carries a network value** (BOOT-06). The stubs configure no
  network, and the build cannot compile one into the kernel.
- **The first release has no security-suite run**, if Jeff confirms a24's
  recommended option. It contains no boundary code. Under that option the
  first release with relay behaviour, M2's, is inside the relay's
  invariant; the suite does not exist and its item is behind the freeze,
  so M2's design has to settle how its release gets one, and this design
  does not promise it.
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
banner under QEMU (KVM for x86_64, emulation for aarch64) or a container
runtime. The x86_64 unikernel on Firecracker is added if its trial passes
(a23).

**Tier 2 (native):** the stub unikernel's VZ form boots on the MacBook
(`macos-vz`), recorded with its console log. It is blocking for two things
(FLOW-09): the pull request that changes the loader's toolchain pin, and
the `v0.0.1` tag, and each time it is the bytes in question that boot
(task 7). For every other change it is a tracked gap. Hyper-V is a tracked
gap until M2. While the queue has no step for this repository, a blocking
boot is an attended session Jeff starts, and the gaps are recorded as a17
says.

**Done when**, for M1a: `ci-ok` and `sessions-private` are green on `main`
with all of the above in place; the a4 and a23 trials are each recorded,
passed, failed or unfinished; the repository is public with its checklist
recorded; the tagged commit's `aarch64-vz` form has booted on VZ, and the
hashes recorded at the boot equal the published ones; `v0.0.1` is
published and a rebuild from its commit on another machine gives the
published manifest. For M1b: the README and `AGENTS.md` link to the Loop
Contract, the profile, the rules and the design template are in its form,
and the consumables are declared (LOOP-08's steps as merged); the
conformance pin is set and the dispatch run against the Go relay's image
has passed. A relay item completing through `wf`'s gates is P1's
done-when, not M1's (a26).

**Not validated by M1, and said so:** that the reproducibility method holds
for a real relay with a TLS stack and an async runtime (M2 and M3 find
out, with the `repro` job already in place); throughput of anything;
macOS binaries' reproducibility.

## Implementation plan

No task starts before the design review has approved this design and
recorded it under **Design review** (FLOW-19, FLOW-07; see **Blocking**).
After that, each task is one pull request to `main` unless it says
otherwise, on its own feature branch, merged by Jeff (FLOW-08). Task 0
comes first. Tasks 1 to 3 can then start together; the rest follow the
order given. Every task is worked outside the queue, in an attended
session, until the queue can hold it (a17); from `loop-repository` on,
each task still open is an item `wf` gates.

**M1a: nothing here waits for another program item.**

0. **This design reaches `main`.** `docs/design/m1-foundation.md` exists
   only on `feat/m1-foundation`, and every other task branches from
   `main`. Once the review's entry is recorded in it on that branch, the
   branch's pull request is opened: this one file, nothing else. Jeff
   first turns on "Automatically delete head branches" (a16), then
   merges. Every later task can then read the design on `main`, and the
   ones with a result to record (5, 6, 9) edit it in their own pull
   request. No CI exists yet, so nothing gates this pull request but the
   review it records. Rules: FLOW-03, FLOW-08, FLOW-16, FLOW-19.
1. **Housekeeping** (documents and the session guard). `README.md`,
   `CONTRIBUTING.md` (set-up, the commands in this design, the pull request
   flow, and the main repository's standards by link), `SECURITY.md`,
   `CODE_OF_CONDUCT.md` per a14, the pull request template,
   `.entire/settings.json`, `tools/flow18-check.sh`, `flow18.yml`, a root
   `.gitignore`, `docs/invariants.md` (the rules table, with the relay's
   security-testing invariant as a24 is answered, and the two tracked
   native gaps), and, if a21 is confirmed as A, `docs/planning/` with the
   kickoff and the decisions table. Rules: FLOW-18, GLOBAL-06, TEST-03.
   It builds on a14's, a21's and a24's answers, which the design review
   gives before any task starts.
2. **Workspace, lints and the first CI.** `Cargo.toml`, the three relay
   crates as stubs, `tests/lint-fixtures`, `xtask` with `check-pins`,
   `lint-sources`, `fetch`, `build` and `conformance`;
   `rust-toolchain.toml`, `pins.toml` (toolchains, forks at `-bw.1`,
   Linux, an empty `[conformance]`; no builder yet), `clippy.toml`,
   `deny.toml`, `rustfmt.toml`, `conformance/targets/README.md`; `ci.yml`
   with `changes`, `fmt`, `pins`, `clippy`, `test`,
   `test-hermit-toolchain`, `native`, `hermit`, `deny`, the inactive
   `conformance` and `ci-ok`; `audit.yml`. Tests: `check-pins` and
   `lint-sources` as in the Validation plan; `xtask conformance` for the
   not-pinned, failed-download, failed-hash and no-targets cases. Three
   things are checked here before they are relied on: `cargo deny check`
   passes on the stub workspace with the `deny.toml` above; the order in
   which cargo runs the `hermit` and `relay-hermit` build scripts; and
   that the Hermit nightly's cargo accepts the committed `Cargo.lock`
   under `--locked`. Rules: GLOBAL-01, GLOBAL-02, GLOBAL-03, GLOBAL-04,
   GLOBAL-07, GLOBAL-08, GLOBAL-10, GLOBAL-11, RELAY-07, TEST-01.
3. **The kernel fork's commit** (in `buildwarden/hermit-kernel`, a pull
   request to `bw/v0.13.2`; D12): `src/fs/mod.rs`, `Cargo.toml`,
   `Cargo.lock` and `CARRIED.md`. Jeff merges and tags `v0.13.2-bw.2`
   (a10). Rules: GLOBAL-05, GLOBAL-06, FLOW-08; the umbrella's Decision 15.
4. **The builder image** (after 2). `images/builder/Containerfile` and
   `builder.yml`. After the merge the workflow pushes the image and prints
   its digest. Rules: GLOBAL-05, GLOBAL-06.
5. **Image tooling** (after 3 and 4). `xtask images`, `repro-compare` and
   `smoke`; the kernel configurations; the manifest; `pins.toml` gains the
   builder digest and moves the kernel fork to `-bw.2`; `ci.yml` gains
   `images`, `images-rebuild`, `repro` and `smoke`; `docs/building.md`.
   It includes the Firecracker trial (a23): the result is recorded under
   **Rollback notes** in this design, in the same pull request, and the
   Firecracker leg is added to `smoke` only if the boot passed. Rules: GLOBAL-05, BOOT-06, TEST-02, TEST-04. If a form
   cannot be made to reproduce, that is a return to this design (FLOW-06),
   not a form left out of `repro`.
6. **The loader toolchain trial** (after 5; a4). Build the loader with
   stable `1.97.1` and run every smoke boot. The pin changes only if those
   pass and the VZ boot of the `aarch64-vz` form built with `1.97.1` has
   passed on the MacBook (task 7, boot b); that boot blocks this pull
   request (FLOW-09). If no MacBook session has run, the pull request is
   closed with the pin unchanged. Either way the result is recorded under
   **Rollback notes**: in this pull request if it merges, otherwise in
   the next pull request that edits this design. Rules: GLOBAL-05,
   FLOW-09, TEST-04.
7. **VZ boots of the stub** (native, MacBook; attended sessions Jeff
   starts, a17). Not a pull request. Each boot takes the `dist/` that a
   named run of the `images` job uploaded, checks the two files against
   that run's manifest, boots `hermit-loader-aarch64-vz.Image` with
   `relay-hermit-aarch64` using the spike's `vzrun`, and records the
   console log with the commit, the run and the SHA-256 of both files.
   The MacBook builds nothing: only a linux/amd64 build is canonical.
   There are three boots, because each commit builds different bytes for
   this form (a13):
   - *(a) Task 5's build*, from the `images` run on task 5's pull request
     or on `main` after it merges. It blocks nothing, and if no session
     has run it is skipped; boot (c) is then the first. It is worth
     having because it is the first time the cross-built loader and the
     `-bw.2` kernel boot as a pair, and a failure found here is a return
     to this design before the repository goes public. Its log goes into
     task 5's pull request, or into task 8's if task 5 has merged.
   - *(b) Task 6's build*, from the `images` run on task 6's pull
     request head, where the loader is built with `1.97.1`. It blocks
     task 6's merge and nothing else. Its log goes into that pull
     request.
   - *(c) The release build*, from the `images` run on `main` at the
     commit that will be tagged, which is at or after task 9's merge. It
     blocks the `v0.0.1` tag and nothing else. Its log and the two hashes
     go into task 9's closing pull request.

   Rules: FLOW-09, TEST-02, TEST-03.
8. **Going public** (after 0, 1, 2 and 5 have merged). The checklist, with
   the full-history scan of step 1; the redaction pull request for the
   vznet material if a15 is confirmed as A; the branch deletion as a25 is
   answered; then Jeff's steps 10 to 14, and the pull request that
   removes the registry login. Rules: FLOW-16, FLOW-17, FLOW-18,
   GLOBAL-06; the umbrella's Decision 16 and a11.
9. **Release workflow and the stub pre-release** (after 8). Three steps.
   First, the pull request that adds `release.yml`. Second, after it has
   merged: boot (c) of task 7 on the commit to be tagged; then Jeff
   pushes `v0.0.1`, with a13's three acceptances in the design review;
   the release task compares the published hashes of the two booted
   files with the ones recorded at the boot, and a rebuild elsewhere is
   compared with the published manifest. Third, the pull request that
   closes M1a, docs only: it records the **Going public** checklist, boot
   (c) and the two comparisons, and fills **Consolidation** and the
   **Archive summary** for M1a. Rules: FLOW-08, FLOW-09, GLOBAL-05; the
   relay's security-testing invariant as a24 is answered.

**M1b: each task names what it waits for.**

10. *Waits for `loop-contract` to merge in the main repository; does not
    wait for any later P1 item or for M1a to finish.* LOOP-08's steps as
    merged, in the form **The Loop Contract adopted** gives them:
    `AGENTS.md`, and the link to the contract from it and from the README;
    the profile, which names this repository's rule prefix, its host
    names and what it releases and consumes; `docs/invariants.md`
    rewritten as rules in LINT-01's format under that prefix;
    `docs/design/TEMPLATE.md`. Nothing is registered in the contract and
    nothing in the main repository changes. Rules: the contract's LOOP-01
    and LOOP-08 as merged; LINT-01.
11. **This repository's work in the one queue.** Not part of M1's
    done-when (a26), and not a pull request here until its last part. It
    is listed so that what a17 defers has a place.
    - *When `loop-parallel` has landed:* what is still open of M1 is
      filed, at intake with Jeff, as an item that names this repository,
      tracked and not gated. If M1 is done by then, there is nothing to
      file.
    - *When `loop-repository` has landed:* whatever its design asks of a
      second repository is added here; the two tracked native gaps are
      filed on the queue's native-gap backlog; and the relay work that is
      next at that time (task 10 or 12 if either is still open, otherwise
      M2's first item) is the first item `wf` gates here. Its completion
      is the relay half of P1's done-when.

    Rules: the contract's rules for an item and its repositories, as
    merged; TEST-03.
12. *Waits for the first release of `buildwarden-specs`.* Set
    `[conformance]`; add `conformance-dispatch.yml`; run it against the Go
    relay's image with the main repository's `relay-oci` target file;
    record the run. Rules: GLOBAL-08, TEST-05.

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
  netfilter), its init and boot channel, and its disk forms and whether any
  derived form is hashed (a6). The boot channel has two cases M2 must
  cover (BOOT-06, RELAY-08). Reading the kernel command line is a
  filesystem read, which the relay crates may not do. And on Hyper-V
  there is no per-boot command line at all: the Go relay's VM reads its
  pre-claim values from a per-build seed ISO, which needs a block device
  and an ISO 9660 driver in the appliance kernel and a mount in its init.
  M2 decides whether a separate init does these or the lint changes by
  design; the stub kernel's lack of a block layer does not carry over.
- The seam 8 specification, by whichever item Jeff assigns (a20), before
  M2's release forms are consumed by anything.
- How M2's first release meets the relay's security-testing invariant
  (a24). M2 is wave 2, the suite does not exist, and its item is closed
  until after the freeze, which ends no earlier than wave 4. M2's design
  settles that with Jeff before M2 tags anything; M1 does not promise a
  suite by then.
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
- Which loader forms ship; Firecracker on aarch64; and, if the a23 trial
  failed, how the unikernel boots on Firecracker on x86_64.

**M5:** truststore endpoints. **M6:** adoption by each driver; RELAY-04
restated; the Go relay retired; then, and not before, anything raised with
`hermit-os`.

## Risks

- **Reproducibility is shown for one piece.** A hello-world unikernel
  application on one target, built with a path dependency and the default
  release profile. The loader, aarch64, the workspace's release profile
  (LTO, one codegen unit, stripping), the Linux kernel build and the
  hand-written cpio and OCI writers are designed to reproduce and have not
  been seen to. Task 5 is where that is found out, and `repro` is the
  test.
- **Three boots in the plan have no precedent in the sources.** The
  `acpi` and `pci` stub on x86_64 at all (upstream's demo application
  with those features is the nearest thing, on QEMU); the same stub on Firecracker (a23); and the
  spike's aarch64 loader and kernel under emulation instead of HVF. Task 5
  finds out. A failure of the first or third is a return to this design.
- **The builder may be short of what a Linux kernel build needs.** The
  package list is the main repository's, which runs on a full hosted
  runner image, not on `trixie-slim`. Task 4 or 5 finds any missing
  package, and it is added to the Containerfile.
- **Only the builder's output is canonical.** A build outside it, or with
  CI variables in its environment, gives different bytes. A contributor who
  compares a local cargo build with a published hash will see a mismatch;
  `docs/building.md` has to say so plainly.
- **A pinned input can disappear.** Dated nightlies, a Debian snapshot, a
  kernel.org tarball and the forks are all fetched at build time. The
  toolchains are also inside the builder image, which the organization
  hosts. Two inputs are weaker than the rest: the Hermit kernel depends on
  `hermit-os/async-executor` and on `hermit-os/safe-mmio` by branch, each
  held to a commit only by the kernel's `Cargo.lock`; if either branch is
  rewritten upstream, its commit may stop being fetchable. Forks of both,
  or the source bundle deferred to M2, close this (a22).
- **Some facts here are true only at the pinned commits.** The `hermit`
  crate's build script removes every `CARGO*` and `RUST*` variable at
  `d73a481`; upstream's `main` now keeps `CARGO_HOME` and `RUSTUP_HOME`.
  The builder's "toolchains at the default locations" rule and the path
  reasoning are rechecked at each Hermit bump.
- **The public manifest may be read as stable.** It is version 0 and
  marked unstable. It takes K1's provisional names where the two name the
  same thing, and still differs from K1 on what a unikernel's files are
  (a20). Until seam 8 is written, each side can drift.
- **The unikernel's compiler is nine months old and the lag will grow.**
  It moves only when BuildWarden replays its carried commits onto a newer
  Hermit release. The MSRV of 1.94 follows from it and can hold back a
  dependency's fixed version.
- **Two compilers build `relay-core`.** The tests run under both; the
  optimized unikernel is still only exercised by booting it.
- **Pushing `unsafe` out of the workspace pushes work into the forks**
  (a2), where review is harder and upstreaming is on hold.
- **The S1, P1 and K1 designs are not merged, and P1's later items are
  not designed.** M1b absorbs the final shape of the first two; M1a is
  built not to depend on it. What this design says each later P1 item
  brings (**The Loop Contract adopted**) is a reading, and those items'
  designs may decide otherwise.
- **CI time.** About twenty minutes for a code change, most of it building
  images twice. If that proves too slow, the rebuild can move to `main` and
  the weekly run, which trades merge-time certainty for speed and needs a
  decision.
- **Hosted arm runners** may not be available to this repository (a18).
- **One person** approves this design, merges the fork change, tags it,
  starts the MacBook sessions, changes the visibility, and pushes the
  release tag. Each is a point where M1a waits. The release boot adds
  one: it can only happen after the release workflow has merged, on the
  commit that will be tagged.
- **No tool enforces the order of work** until `wf` can gate work in this
  repository (a17). The design review entry and the task preconditions
  are kept by the sessions that do the work and by Jeff's merges.
- **Nothing but the rule keeps `main` while the repository is private.**
  Its host offers no branch protection on the current plan, so FLOW-08
  and FLOW-17 are held by the sessions' settings until the visibility
  change (a16).

## Design review

(None yet. The revision of 2026-11-14 was made before any review and is
described at the end of **Prior art**; it is not a review entry.)

There is no queue file, so the entry written here is the record of the
approval and the gate for the implementation plan. An approval names
`approved at <sha>` and, by ID, each assumption it confirms or changes. It
gives Jeff's explicit word on a14, a15, a21, a24 and a25, and on the three
acceptances in a13.

## Consolidation

(Filled in by the pull request that closes M1a, the last step of task 9:
what landed in this repository and in the main repository since this
design was written, terminology aligned with the S1, P1 and K1 designs as
merged, and the duplication and dead-code sweep.)

## Rollback notes

(None yet. The results of the loader toolchain trial, a4, and of the
Firecracker trial, a23, are recorded here, by tasks 6 and 5.)

## Archive summary

(Filled in by the pull request that closes M1a, the last step of task 9.)
