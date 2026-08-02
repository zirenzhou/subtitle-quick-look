# Official Homebrew distribution roadmap

Subtitle Quick Look is currently distributed through the repository's third-party Homebrew tap. The long-term goal is a one-command installation from an official Homebrew repository.

## Correct official package type

The primary installed artifact is a native macOS `.app` bundle containing a Quick Look extension and Finder Services. Homebrew explicitly excludes formulae whose primary output is a native app bundle from `homebrew/core`; supported app bundles belong in `homebrew/cask`.

The official submission target is therefore **Homebrew/homebrew-cask**, not `homebrew/core`.

## Work required before submission

1. **Publish a prebuilt universal app artifact.** A cask installs an upstream application distribution instead of compiling the app from source on the user's Mac.
2. **Use Apple Developer ID signing and notarization.** The downloadable app must work with Gatekeeper enabled and must not require users to bypass macOS security protections.
3. **Automate release packaging.** Each stable GitHub Release should contain an immutable, versioned archive with a SHA-256 checksum and consistent download URL.
4. **Create and test a cask.** The cask should install the app bundle, register its extension and Services where permitted, and provide complete uninstall and cleanup behavior.
5. **Meet Homebrew's public-interest requirement.** For an owner self-submission, a GitHub project normally needs at least 225 stars, 90 forks, or 90 watchers. A repository less than 30 days old is normally ineligible. Documented exceptions exist but are discretionary.
6. **Submit to Homebrew/homebrew-cask.** Run the official cask audit, style, install, and uninstall tests, then open a non-draft pull request and respond to maintainer review.

## Current status

- Stable releases and immutable checksummed source archives: complete.
- Universal Apple Silicon and Intel build: complete.
- Automated Quick Look and Finder Services registration: complete for the third-party formula.
- Developer ID signing and Apple notarization: not yet implemented.
- Prebuilt cask-ready release archive: not yet published.
- Homebrew public-interest and repository-age thresholds: not yet met as of v1.2.0.

Until those requirements are met, the third-party tap remains the technically correct installation method.

## Official references

- [Adding Software to Homebrew](https://docs.brew.sh/Adding-Software-to-Homebrew)
- [Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)
- [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)
- [Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy)
- [How to Open a Homebrew Pull Request](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request)
