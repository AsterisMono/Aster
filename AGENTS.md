# Aster — a personal ungoogled-chromium build

This repo is a personal fork of [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium),
tracking upstream normally but adding a small set of custom, always-on UI/behavior
patches plus two bundled extensions. It is for personal use, not intended as a
general-purpose distribution.

## Intentions

1. **Kill the native tab bar in favor of vertical tabs.** Sidebery (a vertical-tabs
   extension originally for Firefox) has been ported to Chromium as MV3 and is used
   as the primary tab UI, hosted in the browser's native Side Panel. The horizontal
   tab strip is hidden — not removed — so `TabStripModel` and all tab
   logic/shortcuts still work; only the on-screen strip is gone.
2. **Make the side panel look native, not like a panel.** No header/titlebar, no
   rounded corners, no border gap between the panel and the frame/page. Docked on
   the **left**. Sidebery auto-opens there on every window launch.
3. **Never lose a session to a crash.** If "continue where you left off" is set,
   the browser restores the previous session even after an unclean/crashed exit,
   and the "Restore pages?" bubble (easy to miss, easy to lose everything by
   ignoring) is suppressed in that case.
4. **Bundle uBlock Origin.** Baked in as a trusted component extension — no
   webstore, no separate install step, works offline like the rest of
   ungoogled-chromium's philosophy.
5. **Everything above is hardcoded on.** No `chrome://flags`, no switches. This is
   a personal build with one intended configuration, not a general feature toggle.
6. **Install the rest of the extension set on first launch.** Chromium Web Store,
   SponsorBlock, 1Password, Refined GitHub, I still don't care about cookies, and
   SteamDB are force-installed from their signed CRX URLs through an Aster-only
   machine policy. The CRX payloads are fetched after launch rather than stored
   in the RPM.

## Where things live

- `patches/extra/aster/` — the patches implementing the intentions above. See its
  `README.md` for a one-line description of each.
- `patches/extra/helium/` — component-extension infrastructure (manifest l10n,
  managed-schema support, an empty-resource fix) reused from
  [Helium](https://github.com/imputnet/helium), another ungoogled-chromium fork,
  under GPL-3.0 with attribution. See its `README.md`. (Helium's own `AGENTS.md`
  bans AI-assisted contributions *to Helium*; that does not restrict reusing its
  GPL-3.0 code in a separate downstream fork such as this one — reuse here is
  intentional and was explicitly authorized.)
- `downloads.ini` — extended with `[ublock]` and `[sidebery]` sections so both
  extensions are fetched into `third_party/` at build time, which is what lets the
  `bundle-*.patch` files bake them into the binary.
- `assets/aster/policies/` — the Aster-only managed policy used to fetch the
  remaining extensions on first launch.
- `build.sh` + `scripts/` — a one-shot, containerized build producing an `.rpm` in
  the repo root. See "Building" below.

## Building

```sh
./build.sh
```

This builds a container image (`scripts/build.Dockerfile`) and runs
`scripts/compile.sh` (source prep + `ninja`) then `scripts/package-rpm.sh` (stage
runtime files + `rpmbuild`) inside it. Requires Docker or Podman on the host —
nothing else.

Notes for whoever (human or agent) runs this:
- **Do not run a full `ninja` build on a memory-constrained machine.** Linking
  Chromium needs well more than 16 GB RAM; use a bigger box or generous swap.
  `JOBS=N ./build.sh` throttles parallelism if you're tight on RAM.
- **On SELinux-enforcing hosts (Rocky/RHEL/Fedora)**, the bind mount needs the
  `:Z` relabel — already wired into `build.sh`'s `-v` flag. If you hand-roll a
  `docker`/`podman run` outside `build.sh`, don't forget it, or you'll see
  "Permission denied" on files that are already `chmod +x` on the host.
- Each heavy stage in `scripts/compile.sh` writes a marker file, so re-running
  `./build.sh` resumes rather than redoing finished work.

## Status

All patches (including the ones added for this fork) pass
`devutils/validate_patches.py` and `devutils/validate_config.py` — they apply
cleanly and are correctly formatted. The full `ninja` compile has **not** yet
been verified end-to-end; the extension-bundling patches in particular (grit
resource-id ranges, component l10n, auto-open timing) are the most likely spots
to need a follow-up fix once a real build is run.
