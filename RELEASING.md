# Releasing

How a version of this SDK reaches users, what has to be set up once, and the
few commands a release takes. The same shape is intended for every official
Onetime Secret SDK; the Swift-specific parts are called out.

## How Swift packages are published

There is no registry upload. SwiftPM resolves `from: "1.2.0"` by reading git
tags from this repository, and the [Swift Package Index](https://swiftpackageindex.com)
indexes new tags within minutes of them being pushed. Publishing is
therefore:

1. a commit on `main` whose `Version.swift` and `CHANGELOG.md` name the version,
2. an annotated tag `vX.Y.Z` on that commit,
3. a GitHub release for that tag, with notes taken from the changelog.

`.github/workflows/release.yml` does step 3 and refuses to do it unless
steps 1 and 2 are consistent and the tagged commit passes the full CI matrix.
Nothing in the pipeline needs a token beyond the workflow's own
`GITHUB_TOKEN`.

CocoaPods and Carthage are not supported. CocoaPods trunk stops accepting
new podspecs on 2 December 2026 ([announcement](https://blog.cocoapods.org/CocoaPods-Specs-Repo/)),
so a podspec published now would be frozen within weeks; SwiftPM is the only
distribution channel worth maintaining.

## One-time setup for a new SDK repository

Do these once, in order, when the repository is created on GitHub. They are
the "initial setup instructions" for the release process; development setup
is in [CONTRIBUTING.md](CONTRIBUTING.md).

### 1. Repository settings

- **General → Pull Requests**: allow squash merging only; enable
  "Automatically delete head branches".
- **Branches → Add ruleset for `main`**: require a pull request, one
  approval, require the single status check `CI OK` (the `ci-ok` job in
  `ci.yml` fans in every lint, test, build and docs job, so matrix cells can
  change without touching this setting), require branches to be up to date,
  block force pushes. Include administrators.
- **Tags → Add ruleset for `v*`**: restrict creation to maintainers (the
  `delano` user or a release team). This is the control on who can publish.
- **Actions → General**: "Allow GitHub Actions to create and approve pull
  requests" off; workflow permissions "Read repository contents". The
  release workflow asks for `contents: write` explicitly.
- **Pages**: Source = "GitHub Actions". The `Docs` workflow deploys to
  `https://onetimesecret.github.io/onetimesecret-ios/` on every push to
  `main` that touches `Sources/`. It is deliberately not run from the
  release tag: the auto-created `github-pages` environment only accepts
  deployments from the default branch, and the release commit on `main`
  has already triggered it.
- **Code security**: enable Dependabot alerts and security updates;
  `.github/dependabot.yml` already groups the Actions bumps weekly. Enable
  secret scanning with push protection.

### 2. Secrets (optional)

The scheduled `Live API check` and the opt-in `live` CI job run as a guest
with no secrets at all. To exercise the authenticated endpoints too, add
repository secrets for a dedicated test account on the US region:

- `ONETIMESECRET_USERNAME` (the account email or external ID)
- `ONETIMESECRET_API_TOKEN`

Use an account created for CI, not a personal one, so the token can be
rotated without ceremony.

### 3. Swift Package Index

After the first tag exists, open a pull request to
[SwiftPackageIndex/PackageList](https://github.com/SwiftPackageIndex/PackageList)
adding `https://github.com/onetimesecret/onetimesecret-ios.git`. From then on
every tag is indexed automatically, and the index builds the package on
every platform and Swift version it supports; its compatibility badges are a
useful second opinion on the CI matrix. Optional: add a
`.spi.yml` later if documentation should be hosted there rather than on
GitHub Pages.

### 4. First release

Follow the steps below with version `0.1.0`. Pre-1.0 versions signal that the
public API may still change in a minor release; move to `1.0.0` once the
API has survived a few months of real use.

## Cutting a release

Prerequisites: `main` is green, `CHANGELOG.md` has the notes under
`Unreleased`, you are a maintainer with tag permissions, and `gh` is
authenticated.

```sh
# 1. Prepare: branch, bump Version.swift, promote Unreleased in the changelog, commit.
make release-prepare VERSION=1.2.0
git push -u origin release/v1.2.0
gh pr create --fill --title "Release v1.2.0"

# 2. Review and merge the PR like any other (squash).

# 3. Tag the merged commit on main and push the tag.
make release-tag VERSION=1.2.0
```

Pushing the tag starts the `Release` workflow:

1. **Verify tag**: the tag is semver, matches `Version.swift` and has a
   `## [1.2.0] - YYYY-MM-DD` changelog heading; the tagged commit is on `main`.
2. **CI**: the full matrix runs again against the tagged commit.
3. **Create GitHub release**: notes are the changelog section plus the SwiftPM
   snippet. A `-beta.1`-style tag is marked pre-release; anything else
   becomes the latest release.

Watch it with `gh run watch --workflow release.yml`. If verification fails,
nothing has been published; fix `main` with a normal PR, delete the tag
locally and remotely (`git push --delete origin v1.2.0`), and tag again.

### Version numbers

- **Patch**: bug fixes, decoding fixes for API changes, dependency bumps.
- **Minor**: new operations, new optional parameters, new fields on models.
  Adding a field to a public struct is additive for callers but breaks
  anyone who wrote their own `init`; our models expose memberwise `init`s
  only where that is intended, so this stays minor.
- **Major**: anything that makes existing calling code fail to compile or
  changes behaviour callers depend on. Pre-1.0, a minor bump may do this,
  and the changelog must say so under **Changed** or **Removed**.

The SDK version is sent in the `User-Agent` header
(`onetimesecret-ios/1.2.0 (Swift/6.2; iOS)`) and in `X-Onetime-Client`
(`swift:6.2/1.2.0`), the same convention as onetime-ruby, which is how the
service team can tell which clients and versions are in use before
deprecating anything.

### Yanking a release

Tags are immutable once consumers may have resolved them. Do not delete or
move a tag that was ever on GitHub. Ship a patch release and, if the bad
version is dangerous, edit its GitHub release notes to say so and point at
the fix.

## Adapting this for other SDKs

Everything above except the SwiftPM mechanics transfers: a version constant
in source, Keep a Changelog, a two-step `prepare`/`tag` script against a
protected `main`, a tag-triggered workflow that verifies before it publishes,
and a scheduled live check against the real service. For ecosystems with a
registry (RubyGems, npm, PyPI, Maven Central) the `publish` job gains one
step that uploads using trusted publishing (OIDC) rather than a long-lived
token, and the one-time setup gains the registry-side trust configuration.
