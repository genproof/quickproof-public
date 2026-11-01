# Contributing to QuickProof

Issues and pull requests are welcome. Please write them, and commit messages, in English.

## How changes are merged

QuickProof is developed in a private repository and published here one version at a time. An accepted pull
request is applied to our release branch, with you as the author of the commit, and ships with the next version.
We then close the pull request with a note that names the version. Issues are handled the same way.

By sending a contribution you confirm that you have the right to send it, and you grant GenProof a perpetual,
worldwide, non-exclusive, royalty-free and irrevocable licence to use, copy, modify and distribute it, to sublicense
it and to license it under any terms, the licence of this repository ([LICENSE](LICENSE)) and commercial licences
among them, together with a licence under any of your patent claims that the contribution infringes.

## Before you send a change

Install the toolchain as the README describes and run the tests:

```sh
tests/run.sh
```

They end with a check of the examples in `examples/`.

## Properties

New properties are welcome, for a library we already prove or for a new one. A good property states what the
right result is; a property that only checks that nothing crashes says much less
([docs/HARNESSES.md](docs/HARNESSES.md)). Run `tools/qp check` on its harness first, and tell us whether you
expect the property to hold. If it fails and the failure looks like a bug in the library, report the bug as
[SECURITY.md](SECURITY.md) describes before you publish anything.

## Proposing a library

To ask us to prove a library, propose it or vote for it at [genproof.com/quickproof/next](https://genproof.com/quickproof/next).
Say which version, which functions, and what you want to know about them. Maintainers can claim their project
there and tell us how they want to hear about bugs.
