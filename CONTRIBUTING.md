# Contributing

Thanks for your interest in contributing to `nixos-modules`.

This repository contains opinionated NixOS modules, so the safest changes are small, focused patches that keep existing defaults unchanged unless the change is intentional and documented.

## Getting Started

1. Fork and clone the repository.
2. Install Nix with flakes enabled.
3. Create a branch for your change.

```bash
git clone https://github.com/NuschtOS/nixos-modules.git
cd nixos-modules
git checkout -b your-change
```

## Local Checks

Before opening a pull request, run the same core check that CI runs:

```bash
nix flake check -L --show-trace
```

For a faster evaluation check, you can also run:

```bash
nix eval .#checks.x86_64-linux.no-config -L --show-trace
```

CI also evaluates the modules against multiple `nixpkgs` inputs, including stable and unstable branches. If your change depends on a specific `nixpkgs` behavior, mention that in the pull request.

## Pull Requests

Please keep pull requests focused and include:

- what the change does
- why it is needed
- whether it changes any defaults
- which checks you ran locally

The repository pull request template asks contributors to confirm that no settings are changed by default and that changes were tested on a real-world deployment. If either point does not apply, explain why in the pull request.

## Module Changes

When changing or adding modules:

- avoid changing user-visible defaults unless that is the purpose of the change
- document new options or behavior in the module where appropriate
- prefer small changes that are easy to review and revert
- include enough context for maintainers to evaluate compatibility with stable and unstable `nixpkgs`
