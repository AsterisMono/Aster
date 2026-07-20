# Helium-derived patches

Patches in this directory are taken from — or closely adapted from — the
[Helium browser](https://github.com/imputnet/helium), another fork of
ungoogled-chromium. They are used here with attribution and under the terms of
Helium's license.

**Source:** https://github.com/imputnet/helium (`patches/helium/core/`)
**License:** GPL-3.0 (see the Helium repository's `LICENSE`)

Helium's `AGENTS.md` forbids using AI agents to *contribute to the Helium
project*. That restriction concerns contributions to Helium itself; it does not
restrict reuse of Helium's GPL-3.0 source in a separate downstream fork such as
this one. These files are reused as permitted by the GPL-3.0 license.

## Contents

These patches provide the infrastructure to bake third-party MV2/MV3 extensions
into the build as trusted **component extensions** (loaded from the resource
bundle, offline, non-removable):

- `add-component-l10n-support.patch` — allows component extensions to localize
  their `__MSG_*__` manifests by reading `_locales` message catalogs from the
  resource bundle (stock Chromium only does this for ChromeOS component
  extensions).
- `add-component-managed-schema-support.patch` — allows a component extension's
  `storage.managed_schema` manifest key to resolve from the resource bundle
  (required by uBlock Origin's manifest).

These are prerequisites for the `bundle-ublock-origin` and `bundle-sidebery`
patches (see `patches/extra/aster/`).
