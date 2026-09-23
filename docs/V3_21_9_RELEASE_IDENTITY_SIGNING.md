# CELE Topnotcher OS — v3.21.9 Release Identity & Signing Configuration

The product/release brand is now fixed as:

- Product: **CELE Topnotcher OS**
- Publisher brand: **ace**
- Intended public bundle identifier: **`com.ace.celetopnotcher`**

This is a release-configuration decision, not an Authenticode certificate claim.

## Why the identifier changes

The certified engineering foundation still uses the development placeholder:

`local.cele.topnotcher.foundation`

That identifier was appropriate for internal development/certification but should not become the permanent public identity by accident.

The first public release will use:

`com.ace.celetopnotcher`

The certified v3.21.7 branch remains untouched. The final release build applies the identity through a separate Tauri release override config after verifying the exact certified baseline. The certified base tauri.conf.json remains unchanged.

## Migration consequence

No public release has shipped under the old placeholder identity, so there is no supported public-install migration to preserve.

Internal/development installs that used `local.cele.topnotcher.foundation` may keep data under a different application-data location. v3.21.9 deliberately does **not** claim automatic migration from those development installs.

## Publisher brand versus Windows verified publisher

`ace` is the product/publisher brand selected for the application metadata.

Windows' **Verified publisher** value for a signed installer/executable comes from the Authenticode signing certificate. Because no signing certificate or signing service is currently configured, the future certificate subject is not invented here and may not literally be the string `ace`.

The public-release gate therefore requires both:

1. approved product identity; and
2. a real, valid Authenticode signing identity with timestamp evidence.

## Signing state

Current status:

- code-signing certificate: **none**
- signing provider/service: **none configured**
- Authenticode signer identity: **pending**
- unsigned development/release-candidate builds: allowed
- unsigned public release: **not allowed by the release gate**

No signing private key, PFX, password, client secret, or provider credential should ever be committed to this repository.

## Release overlay

Use:

`scripts/apply-release-identity-v3219.py`

against a reconstructed certified source tree. The script:

- verifies the old development identifier before changing it;
- creates src-tauri/tauri.release-ace.conf.json with the public bundle identifier and updates release publisher metadata;
- does not modify the certified base src-tauri/tauri.conf.json;
- does not touch the frozen frontend;
- does not touch the frozen compiler;
- keeps `signed=false` and `publicReleaseApproved=false`;
- refuses to pretend signing is configured.

After the overlay, rerun the release audits and native/manual release gates before publishing anything.
