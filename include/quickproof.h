/* quickproof.h: the environment of a harness.
 *
 * A harness is a C `main` that draws every input from these functions and reaches undefined
 * behaviour when a check fails.  They have no body: in the theorem (QuickProof.Contract.harness_safe)
 * they are specified by QuickProof.Env, where each may return any value.  For native runs
 * (fuzzing, replay) runtime/ implements them.
 *
 * TRUSTED: together with coq/QuickProof/Env.v and coq/QuickProof/Contract.v this header is part of the
 * meaning of every theorem.  The declarations must match the specifications in Env.v.
 */
#ifndef QUICKPROOF_H
#define QUICKPROOF_H

#include <stddef.h>
#include <stdint.h>

extern uint8_t  nondet_u8(void);                        /* any 8-bit value */
extern uint32_t nondet_u32(void);                       /* any 32-bit value */
extern size_t   nondet_size(void);                      /* any size_t value */
extern void     nondet_bytes(uint8_t *buf, size_t n);   /* buf[0..n-1] := any bytes; buf writable, or NULL if n == 0 */

/* qp_assert(cond): cond must be nonzero.  In the theorem (QuickProof.Env.gp_assert_spec) this is the
 * PREcondition, hence a proof obligation at every call site: a proved harness never fails a check.
 * qp_assume(cond): restrict the run to executions where cond is nonzero; in the theorem
 * (gp_assume_spec) cond != 0 is the POSTcondition, handed to the proof after the call.  An always-false
 * assume makes the rest of the harness vacuous (sound but useless): see docs/HARNESSES.md.
 * `cond` is an `int`: pass a comparison or 0/1, never a wider value -- a long/size_t/pointer difference is
 * truncated to int, so a nonzero value whose low 32 bits are 0 becomes 0 (a spurious failure for assert, a
 * silently dropped restriction for assume).  Write `qp_assert(x != 0)`, not `qp_assert(x)`.
 *   qp_assert and qp_assume are the names to write.  They are macros for the functions gp_assert and
 * gp_assume, the names the Clight, the theorems and earlier harnesses use; both spellings give the same
 * Clight. */
extern void     gp_assert(int cond);
extern void     gp_assume(int cond);
#define qp_assert gp_assert
#define qp_assume gp_assume

/* pick(x): set the lvalue x to an arbitrary value of its type, on top of nondet_bytes.  Supported for
 * the integer scalar types whose EVERY bit pattern is a valid value, and byte buffers (unsigned char[])
 * (both via &x and sizeof x).  NOT _Bool, enums, floats, or padded structs, whose bit patterns need not
 * be valid values; an ARRAY of multi-byte scalars is not proof-backed as a whole -- pick its elements
 * one at a time.
 *   For a byte buffer (unsigned char []) there is nothing to reinterpret: nondet_bytes already leaves
 * "any bytes".  For an integer SCALAR the bytes nondet_bytes leaves are reinterpreted as an arbitrary
 * value of the type -- a helper the harness reader never sees.  That reinterpretation is a real,
 * Qed'd VST lemma (QuickProof.Pick, coq/QuickProof/Pick.v), and
 * it is proved WITHOUT enlarging the trusted base -- it is derived from nondet_bytes_spec, adds no
 * axiom, and Env.v is untouched.  The backed scalar types are exactly:
 *     unsigned char, unsigned short, int, unsigned int, long, unsigned long
 *     (so uint8/16/32/64_t, int32/64_t, size_t all work; QuickProof.Pick.pick_t{uchar,ushort,uint,int,
 *      ulong,long}).
 * NOT backed -- do NOT pick these as scalars: signed char and (signed) short.  A signed sub-word load
 * sign-extends, so the stored value is not the value the bytes decode to; the reinterpretation lemma
 * would need a separate sign-extension argument, which is not provided (picking them stays STUCK in
 * the VST proof, so do not claim them).
 *   Do NOT pick a pointer: it fabricates a wild address (undefined to use); pick its pointee instead. */
#define pick(x)  nondet_bytes((unsigned char *)&(x), sizeof (x))

#endif /* QUICKPROOF_H */
