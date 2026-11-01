# Security policy

## Supported versions

QuickProof is at version 0.1. Fixes go into the next release; older versions do not get backports.

## Reporting a vulnerability

Do not open a public issue for a security problem in QuickProof. Write to vladimir@genproof.com with a
description and the steps to reproduce it. We will acknowledge the report, agree with you on a fix and on a
date to publish it, and credit you unless you ask us not to.

A proof that `qp verify` accepts although its theorem is not the one generated from the harness, or although it
uses an axiom outside the allowed list, counts as a vulnerability. It would make every published result less
trustworthy.

## Bugs that our proofs find in other projects

A property that turns out to be false often points to a bug in the library under test. We report each such bug
to the maintainers of that library first, through the channel the project asks for: its security policy or
private address for anything that may be a vulnerability, its issue tracker otherwise. We publish details only
after a fix is released, or on a date agreed with the maintainers. If you use QuickProof on someone else's code
and find a bug, please do the same.
