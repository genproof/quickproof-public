#!/usr/bin/env python3
"""quickproof tools/link_units.py CONFIG: the units each law links under per-law linking (LINK=per-law).

CONFIG is a project's quickproof.conf (tools/clight.sh); run tools/clight.sh first.  Prints, per harness, the
library units of its program and the globals the program declares without defining.  tools/new_contract.py
imports this module to write the per-law contracts.

The units of a law are the closure of its harness unit under references, at unit granularity: a unit is linked
when it defines (a function with a body, or a variable with an initialiser) a global that a linked unit
references (an Evar in a function body, an Init_addrof in a variable's initialiser) without defining it itself;
every unit that defines such a global is linked.  The harness counts as a unit.  Whole units: a linked unit
brings all its definitions, and their references are followed too.  So the per-law program is closed: every
global it references is resolved exactly as in the program of all units, and it declares without defining
exactly the globals that no unit of the project defines.  (docs/LINKING.md: why this is the soundness
condition, and why the unit set is not part of the trusted base.)

quickproof.conf may fix a law's units, `UNITS_<law>=(out/dir ...)` (the units' output directories, as in
UNITS): the list must be closed in the same sense and contain the computed units, otherwise the contract is not
written (an override may add units, never drop one that the program needs).

Everything here reads clightgen's output (code.v), never the C source: the analysis sees the program the
theorem is about.  It is deterministic (sorted output, no time or host).
"""
import os
import re
import subprocess
import sys

# The functions of the honest environment (QuickProof.Env.env_specs): externals by design, never defined by a unit.
ENV = ('quickproof_free', 'quickproof_malloc', 'gp_assert', 'gp_assume', 'nondet_bytes', 'nondet_size', 'nondet_u32',
       'nondet_u8')


class Unit:
    """One unit's globals, from its code.v: what it defines, what it only declares, and what each definition
    references."""

    def __init__(self, src, out, path):
        self.src, self.out, self.path = src, out, path
        text = open(path).read()
        # ident constants: Definition _x : ident := $"x".
        self.name = dict(re.findall(r'^Definition (\w+) : ident := \$"([^"]*)"\.$', text, re.M))
        chunks = {}
        for m in re.finditer(r'^Definition (\w+)(?: :[^=]*)? :=(.*?)(?=^Definition |^Module |^End |^Global |^Local |\Z)',
                             text, re.M | re.S):
            chunks[m.group(1)] = m.group(2)
        gd = chunks.get('global_definitions')
        if gd is None or 'prog' not in chunks:
            raise ValueError('%s: not clightgen output (no global_definitions)' % path)
        self.defined, self.declared, self.refs, self.deftext = set(), set(), {}, {}
        entries = re.findall(r'\((_\w+),\s*(Gfun\s*\(\s*Internal\s+(\w+)\s*\)|Gvar\s+(\w+)|Gfun\s*\(\s*External\s*\(\s*(EF_\w+))', gd)
        if len(entries) != len(re.findall(r'\(_\w+,\s*G(?:fun|var)\b', gd)):
            raise ValueError('%s: unrecognised entry in global_definitions' % path)
        self.builtins = set()
        for ident, _, fbody, vbody, ef in entries:
            g = self.global_name(ident)
            if fbody:
                self.defined.add(g)
                self.refs[g] = self.body_refs(chunks[fbody])
                self.deftext[g] = chunks[fbody]
            elif vbody:
                init = re.search(r'gvar_init\s*:=(.*?);\s*gvar_readonly', chunks[vbody], re.S)
                if init is None:
                    raise ValueError('%s: no gvar_init in %s' % (path, vbody))
                if init.group(1).strip() == 'nil':
                    self.declared.add(g)          # extern variable: declared, defined elsewhere (or nowhere)
                else:
                    self.defined.add(g)
                    self.deftext[g] = chunks[vbody]
                    self.refs[g] = {self.global_name(i) for i in re.findall(r'Init_addrof\s+(_\w+)', init.group(1))}
            elif ef in ('EF_builtin', 'EF_runtime'):
                self.builtins.add(g)              # CompCert's builtins: QP.prog_builtins, not prog_defs
            else:
                self.declared.add(g)              # an external function (EF_external)
        self.declared -= self.defined

    def global_name(self, ident):
        if ident not in self.name:
            raise ValueError('%s: no ident constant for %s' % (self.path, ident))
        return self.name[ident]

    def body_refs(self, body):
        """Globals a function body names: every Evar except the function's addressable locals (fn_vars)."""
        local = set()
        m = re.search(r'fn_vars\s*:=(.*?);\s*fn_temps', body, re.S)
        if m:
            local = set(re.findall(r'\((_\w+),', m.group(1)))
        return {self.global_name(i) for i in set(re.findall(r'\(Evar\s+(_\w+)', body)) - local}

    def needs(self):
        """Globals this unit references or declares and does not define (clightgen declares exactly the
        globals a unit uses, and __builtin_debug)."""
        out = set(self.declared)
        for r in self.refs.values():
            out |= r
        return out - self.defined


def check_conf(config):
    """Exit unless the quickproof.conf `config` is data, assignments only (tools/conf.py): it is sourced next."""
    sys.dont_write_bytecode = True
    sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
    import conf
    try:
        conf.check(open(config).read())
    except conf.Bad as e:
        sys.exit('%s: refused: %s' % (config, e))


def units_of(config):
    """[(src, out)] of a quickproof.conf, as tools/clight.sh sources it."""
    check_conf(config)
    gp = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    out = subprocess.run(['bash', '-c', 'cd "$(dirname "$1")"; GP="$2"; INC=(); DEFS=(); UNITS=(); '
                          'source "$1"; printf "%s\\n" "${UNITS[@]}"', '_', os.path.realpath(config), gp],
                         check=True, capture_output=True, text=True).stdout
    return [line.split('=', 1) for line in out.splitlines() if line]


def conf_values(config, names):
    """{name: [values]} of bash arrays/variables set by a quickproof.conf (missing ones: None)."""
    check_conf(config)
    gp = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    script = ('cd "$(dirname "$1")"; GP="$2"; INC=(); DEFS=(); UNITS=(); source "$1" >/dev/null; shift 2\n'
              'for n in "$@"; do if declare -p "$n" >/dev/null 2>&1; then eval \'a=("${\'"$n"\'[@]}")\'; '
              'printf "%s\\0" "${a[@]}"; printf "\\001\\0"; else printf "\\002\\0"; fi; done')
    out = subprocess.run(['bash', '-c', script, '_', os.path.realpath(config), gp] + list(names),
                         capture_output=True, text=True, check=True).stdout
    vals, cur = [], []
    for item in out.split('\0')[:-1]:
        if item == '\x02':
            vals.append(None)
        elif item == '\x01':
            vals.append([x for x in cur if x != '']); cur = []
        else:
            cur.append(item)
    return dict(zip(names, vals))


def is_harness(out):
    return out.startswith('src/harness/')


def law_name(out):
    return os.path.basename(out.rstrip('/'))


class Project:
    """The units of a quickproof.conf after tools/clight.sh (run from the config's directory)."""

    def __init__(self, config):
        self.config = config
        self.pairs = units_of(config)
        self.units = {}
        for src, out in self.pairs:
            path = os.path.join(out, 'code.v')
            if not os.path.exists(path):
                raise ValueError('%s missing: run tools/clight.sh first' % path)
            self.units[out] = Unit(src, out, path)
        self.libs = [out for _, out in self.pairs if not is_harness(out)]
        self.harnesses = [out for _, out in self.pairs if is_harness(out)]
        names = ['LINK'] + ['UNITS_' + law_name(h) for h in self.harnesses if re.fullmatch(r'\w+', law_name(h))]
        self.conf = conf_values(config, names)
        link = self.conf['LINK'] or ['all']
        if len(link) != 1 or link[0] not in ('all', 'per-law'):
            raise ValueError('%s: LINK=%s: all (the default) or per-law' % (config, ' '.join(link)))
        self.mode = link[0]
        overridden = [n for n, v in self.conf.items() if n.startswith('UNITS_') and v is not None]
        if overridden and self.mode != 'per-law':
            raise ValueError('%s: %s without LINK=per-law' % (config, ', '.join(overridden)))

    def definers(self, g, law):
        """The units of law `law`'s full program (all library units + its harness) that define g."""
        return [u for u in self.libs + [law] if g in self.units[u].defined]

    def closure(self, law, start):
        """The library units of the closure of `start` and the harness under what they need, in UNITS order."""
        linked, todo = set(start) | {law}, sorted(set(start) | {law})
        while todo:
            u = todo.pop()
            for g in sorted(self.units[u].needs()):
                for v in self.definers(g, law):
                    if v not in linked:
                        linked.add(v)
                        todo.append(v)
        return [u for u in self.libs if u in linked]

    def law(self, law):
        """(library units, how: 'computed' or 'UNITS_<law>', units not linked, undefined globals) of a law,
        units in the order of UNITS.  Raises ValueError when the law's program of all units defines a global
        twice differently (it would not link), or when UNITS_<law> leaves out a unit the program needs."""
        name = law_name(law)
        full = self.libs + [law]
        env = [(u, g) for u in full for g in ENV if g in self.units[u].defined]
        if env:
            raise ValueError('%s defines %s, a function of the environment: under per-law linking the environment\'s '
                             'names are reserved (docs/LINKING.md)' % env[0])
        for g in sorted(set().union(*(self.units[u].defined for u in full))):
            d = self.definers(g, law)
            if len({self.units[u].deftext[g] for u in d}) > 1:
                raise ValueError('%s: %s is defined differently by %s: the program of all units does not link'
                                 % (name, g, ', '.join(d)))
        computed = self.closure(law, [])
        override = self.conf.get('UNITS_' + name)
        how = 'computed'
        units = computed
        if override is not None:
            unknown = [u for u in override if u not in self.libs]
            if unknown:
                raise ValueError('UNITS_%s: not a library unit of UNITS: %s' % (name, ', '.join(unknown)))
            need = self.closure(law, override)
            missing = [u for u in need if u not in override]
            if missing:
                raise ValueError('UNITS_%s leaves out %s, which the program needs (%s)' % (
                    name, ', '.join(missing), '; '.join(self.why(law, override, m) for m in missing)))
            units = [u for u in self.libs if u in override]
            how = 'UNITS_' + name
        prog = units + [law]
        defined = set().union(*(self.units[u].defined for u in prog))
        # the closure property, checked again on the result: every global a unit of the program needs is
        # defined in the program, or by no unit of the project at all
        for u in prog:
            for g in sorted(self.units[u].needs() - defined):
                d = self.definers(g, law)
                if d:
                    raise ValueError('%s: %s needs %s, defined by %s, which is not linked' % (name, u, g, d[0]))
        # The globals the program declares and does not define, computed without the unit set: those that no
        # unit of the law's program of all units defines.  The contract's Coq check compares them with the
        # linked program, so a unit left out wrongly makes the contract fail to build.
        all_defined = set().union(*(self.units[u].defined for u in full))
        undefined = sorted(set().union(*(self.units[u].declared for u in prog)) - all_defined - set(ENV))
        return units, how, [u for u in self.libs if u not in units], undefined

    def why(self, law, linked, missing):
        for u in [law] + list(linked):
            for g in sorted(self.units[u].needs()):
                if missing in self.definers(g, law):
                    return '%s references %s' % (u, g)
        return '%s needed through another unit' % missing


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('config')
    a = ap.parse_args()
    os.chdir(os.path.dirname(os.path.realpath(a.config)))
    try:
        p = Project(a.config)
        print('LINK=%s' % p.mode)
        for h in p.harnesses:
            units, how, dropped, undefined = p.law(h)
            print('%s: %d of %d library units (%s): %s' % (law_name(h), len(units), len(p.libs), how, ' '.join(units)))
            print('  not linked: %s' % (' '.join(dropped) or '-'))
            print('  declared, defined by no unit (externals outside the environment): %s' % (' '.join(undefined) or '-'))
    except ValueError as e:
        sys.exit('link_units: %s' % e)


if __name__ == '__main__':
    main()
