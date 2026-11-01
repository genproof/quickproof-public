# Scope

QuickProof suits C libraries with a clear API that work on memory passed to them.

## Code that fits well

Parsers and decoders for untrusted input, compression and encoding code, cryptographic primitives in portable C,
and protocol state machines whose state lives in structures that the API passes around fit well. zlib's core
library, zstd's decoder, OpenSSL's punycode decoder, and the WireGuard handshake, receive checks and primitives in
Linux are of this kind. Such code is plain C99 or C11, and each property involves a few hundred to a few thousand
lines. Its inputs are "any bytes of any length" or "any sequence of calls", and its properties can be written as C
assertions about the results.

## Code that needs extra work

- Idioms that CompCert leaves undefined ([docs/KNOWN-ISSUES.md](KNOWN-ISSUES.md)) or that VST does not
  support, such as `goto`, struct assignment and a `switch` case that falls off the end without `break`, get
  small patches, tested against the original. `qp interp` finds them quickly.
- Calls to operating-system or kernel interfaces, such as locks or clocks, are linked with small models in C.
  The models are trusted, and each project lists them with its idiom patches (for example in a `DEVIATIONS.md`).
- Large state and long sequences of calls make the function specifications grow. Separate specs with shared
  function specifications help ([docs/LINKING.md](LINKING.md)).
- Code with build-time configuration is proved for one configuration at a time.

## Out of reach

- concurrent code;
- assembly and platform-specific code, including SIMD intrinsics;
- substantial floating-point reasoning;
- `setjmp`/`longjmp`, signal handlers, and variadic functions in the code under proof;
- C++, and C that depends on compiler extensions with no portable equivalent;
- termination (VST proves partial correctness);
- properties that C semantics cannot express, such as timing, side channels and performance;
- whole applications or operating systems. QuickProof works on libraries and well-separated components, and
  the rest of the system is represented only by the spec and the models.

## What a project takes

Most human effort goes into choosing the properties and getting the specs right. Idiom patches and models also need
review. The checks before proving take minutes. AI agents write the proofs; for the proofs in the README's Results
they were Claude Opus 5.5 in Claude Code. An agent may not finish a proof: the property may be false, or the agent
may get stuck.
