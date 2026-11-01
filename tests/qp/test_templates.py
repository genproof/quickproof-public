#!/usr/bin/env python3
"""tests/qp/test_templates.py: a test of what `qp assemble --templates DIR` writes into a proof repository.

`qp assemble` writes no such files of its own; given a template directory (--templates or QP_TEMPLATES) it copies
every file of it to the same path in the repository, with the {KEY}s of qp's template_values filled.  The test
checks, on a small repository in a temporary directory:
  - contract_decls of a LINK=all and of a LINK=per-law contract: Harness, CS, qp, the links, whole_prog (and
    whole_prog_undefined), in that order;
  - the files of the template directory land at the same paths (a nested one, a binary one byte for byte, the
    mode of an executable one kept), with PROJECT, LOGICAL, THEOREMS (the first comment of each harness), CODE and
    NOT_COVERED (notes.md's sections), UNITS, FROZEN_CONTRACTS (valid JSON once embedded), UNIT_FILES and FRAMEWORK
    filled, and a value from a QP_TEMPLATE_<KEY> environment variable;
  - a placeholder that qp does not know is left as it is.
Needs coqc in PATH (or in the opam switch QP_OPAM_SWITCH) for the toolchain's paths.  Exit 0 = pass."""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
loader = importlib.machinery.SourceFileLoader('qp', os.path.join(ROOT, 'tools', 'qp'))
spec = importlib.util.spec_from_loader('qp', loader)
qp = importlib.util.module_from_spec(spec)
loader.exec_module(qp)

ALL = """Require Import VST.floyd.proofauto.
Require Import Demo.units.
Require Demo.harness.law.code.

Module Harness.
  #[local] Instance CS : compspecs. make_compspecs Demo.harness.law.code.prog. Defined.
  Definition qp := ltac:(QPprog Demo.harness.law.code.prog).
End Harness.

(* The link must succeed (`Errors.OK`); the order is irrelevant. *)
Definition link_Libc := ltac:(QPlink_progs Libc.qp A.qp).
Definition whole_prog := ltac:(QPlink_progs Harness.qp link_Libc).

Theorem law : harness_safe whole_prog.
Proof.
Admitted.
"""

PER_LAW = """Require QuickProof.Link.
Require Demo.units.A.

Module Harness.
  #[local] Instance CS : compspecs. make_compspecs Demo.harness.law.code.prog. Defined.
  Definition qp := ltac:(QPprog Demo.harness.law.code.prog).
End Harness.

Definition link_Libc := ltac:(QPlink_progs Libc.qp A.qp).
Definition whole_prog := ltac:(QPlink_progs Harness.qp link_Libc).

Local Open Scope string_scope.
Lemma whole_prog_undefined : QuickProof.Link.undefined_globals_are whole_prog
  [
  ]%list = true.
Proof. vm_compute. reflexivity. Qed.

Theorem law : harness_safe whole_prog.
Proof.
Admitted.
"""

NOTES = """# {PROJECT} ({LOGICAL}, framework in {FRAMEWORK}/)

Laws:
{THEOREMS}

Code: {CODE}

Not covered:
{NOT_COVERED}

Units: {UNITS}; unit files: {UNIT_FILES}; extra: {EXTRA}; unknown: {UNKNOWN}
"""

FROZEN = """{"frozen": {"src/x.v": []{FROZEN_CONTRACTS}}}
"""


class P:
    """The parts of a qp Project that template_values reads."""
    def __init__(self, d):
        self.name, self.dir, self.logical, self.code = 'demo', d, 'Demo', ['lib']


def main():
    ok = True

    def check(cond, what):
        nonlocal ok
        print('%s  %s' % ('ok  ' if cond else 'FAIL', what))
        ok &= bool(cond)

    want = ['Harness', 'CS', 'qp', 'link_Libc', 'whole_prog']
    check(qp.contract_decls(ALL) == want, 'contract_decls (LINK=all): %s' % qp.contract_decls(ALL))
    check(qp.contract_decls(PER_LAW) == want + ['whole_prog_undefined'],
          'contract_decls (LINK=per-law): %s' % qp.contract_decls(PER_LAW))

    t = tempfile.mkdtemp(prefix='qp-templates-')
    try:
        proj, out, tdir = os.path.join(t, 'project'), os.path.join(t, 'repo'), os.path.join(t, 'templates')
        for d in (proj, os.path.join(out, 'harness'), os.path.join(out, 'src', 'contracts'), os.path.join(tdir, 'run')):
            os.makedirs(d)
        open(os.path.join(proj, 'notes.md'), 'w').write('# demo\n\n## Code\n\nA demo library.\n\n## Not covered\n\n- nothing else;\n')
        os.symlink(qp.FRAMEWORK_HOME, os.path.join(out, qp.FW))
        open(os.path.join(out, qp.CONF), 'w').write(
            'UNITS=(\n  "lib/a.c=src/a"\n  "$GP/libc/libc.c=src/libc"\n  "harness/law.c=src/harness/law"\n)\n')
        open(os.path.join(out, 'harness', 'law.c'), 'w').write('/* Law law: a claim\n   on two lines. */\nint main(void) { return 0; }\n')
        open(os.path.join(out, 'src', 'contracts', 'law.v'), 'w').write(ALL)
        open(os.path.join(out, 'src', 'units.v'), 'w').write('Module Libc.\nEnd Libc.\nModule A.\nEnd A.\n')
        open(os.path.join(tdir, 'NOTES.md'), 'w').write(NOTES)
        open(os.path.join(tdir, 'run', 'frozen.json'), 'w').write(FROZEN)
        open(os.path.join(tdir, 'run', 'go.sh'), 'w').write('#!/bin/sh\necho {PROJECT}\n')
        os.chmod(os.path.join(tdir, 'run', 'go.sh'), 0o755)
        blob = bytes(range(256))
        open(os.path.join(tdir, 'logo.bin'), 'wb').write(blob)
        os.environ['QP_TEMPLATE_EXTRA'] = 'from the environment'
        qp.write_templates(P(proj), out, tdir, ['law'])

        notes = open(os.path.join(out, 'NOTES.md')).read()
        print(notes)
        check(notes.startswith('# demo (Demo, framework in quickproof/)'), 'PROJECT, LOGICAL, FRAMEWORK')
        check('- `law`: a claim on two lines.' in notes, 'THEOREMS: the harness\'s first comment, "Law law:" dropped')
        check('Code: A demo library.' in notes and '\n- nothing else;\n' in notes, 'CODE, NOT_COVERED from notes.md')
        check('Units: `lib/a.c`, `quickproof/libc/libc.c`;' in notes, 'UNITS: library units, the framework\'s by its path')
        check('unit files: `src/units.v`' in notes, 'UNIT_FILES')
        check('extra: from the environment' in notes, 'a QP_TEMPLATE_<KEY> value')
        check('unknown: {UNKNOWN}' in notes, 'an unknown placeholder is left as it is')
        frozen = json.loads(open(os.path.join(out, 'run', 'frozen.json')).read())['frozen']
        check(frozen.get('src/contracts/law.v') == want and frozen.get('src/units.v') == ['Libc', 'A'],
              'FROZEN_CONTRACTS: valid JSON, the contract\'s and the unit file\'s declarations: %s' % frozen)
        go = os.path.join(out, 'run', 'go.sh')
        check(open(go).read() == '#!/bin/sh\necho demo\n' and os.access(go, os.X_OK), 'a nested executable file')
        check(open(os.path.join(out, 'logo.bin'), 'rb').read() == blob, 'a binary file, byte for byte')
    finally:
        shutil.rmtree(t, ignore_errors=True)
    print('PASS' if ok else 'FAILED')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
