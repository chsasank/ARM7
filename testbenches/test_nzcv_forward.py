#!/usr/bin/env python3
"""Self-checking A32 programs on the real DeepPipeline RTL (Icarus + llvm-mc).

Run this same runner with --source pointing at either revision. Exit 1 means
an architectural mismatch, 2 means a build/tool error. All generated files
go to --output; expected values are specified independently of RTL output.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
FILES = ('alu.v', 'cond.v', 'data_cache.v', 'instr_cache.v', 'instr_decode.v',
         'mult.v', 'register.v', 'shifter.v', 'DeepPipeline.v')


def cases():
    tests = []

    def add(name, body, regs, nzcv, group='regression'):
        tests.append(dict(name=name, body=body, expected={
            **{f'r{k}': f'{v:08x}' for k, v in regs.items()},
            'r12': '0000007e', 'nzcv': f'{nzcv:x}'}, group=group))

    for low in (7, 6):
        for s in ('', 's'):
            add(f'rrx-skip-low{low}-s{int(bool(s))}', [
                'mov r0,#128', f'mov r4,#{low}', 'mov r2,#8', 'mov r3,#2',
                'cmp r4,r0', f'and{s}eq r0,r4,r4,rrx',
                'rscne r1,r3,r2,ror r2'],
                {0: 128, 1: 0x07fffffd, 2: 8, 3: 2, 4: low}, 8,
                'control' if low == 6 else 'regression')

    for negative in (True, False):
        add('ge-negative-non-s-mov' if negative else 'ge-positive-control', [
            'mov r0,#128', 'mov r1,#255', 'mov r3,#0x80000000',
            'orr r3,r3,#6', 'mov r2,#0x55', 'cmp r0,r0',
            'mov r3,r3' if negative else 'mov r1,r1', 'andsge r2,r1,r3,rrx'],
            {0: 128, 1: 255, 2: 3, 3: 0x80000006}, 0,
            'regression' if negative else 'control')

    # Preserve all four flags through different non-S results and multiple
    # consecutive nonwriters, while testing both carry inputs and predicates.
    for carry in (0, 1):
        for value in (0, 1, 0x80000000):
            for gap in (1, 4):
                add(f'non-s-c{carry}-value{value:08x}-gap{gap}', [
                    'mov r0,#5', f'mov r1,#{5 if carry else 6}',
                    'mov r2,#0x55', 'mov r5,#0x55', 'cmp r0,r1',
                    *[f'mov r3,#{value}'] * gap,
                    'adc r4,r0,#1', 'moveq r2,#9', 'movmi r5,#10'],
                    {0: 5, 1: 5 if carry else 6, 2: 9 if carry else 0x55,
                     3: value, 4: 6 + carry, 5: 0x55 if carry else 10},
                    6 if carry else 8)

    # Executed conditional flag writers must still bypass immediately.
    for carry in (0, 1):
        add(f'executed-s-c{carry}', [
            'mov r0,#5', 'mov r1,#6', 'mov r3,#3', 'cmp r0,r1',
            f'movsne r2,#{0x80000000 if carry else 0}', 'adc r4,r3,#0',
            'movcs r5,#11', 'movcc r6,#12'],
            {2: 0x80000000 if carry else 0, 4: 3 + carry,
             5: 11 if carry else 0, 6: 0 if carry else 12},
            0xa if carry else 4, 'control')

    for count, result, carry, flags in ((0, 1, 1, 2), (31, 0x80000000, 0, 8),
                                         (32, 0, 1, 6), (33, 0, 0, 4)):
        add(f'lsl-register-{count}', [
            'mov r0,#5', 'mov r1,#1', f'mov r4,#{count}', 'cmp r0,r0',
            'movs r3,r1,lsl r4', 'mov r2,#0x80000000', 'adc r5,r1,#0'],
            {1: 1, 2: 0x80000000, 3: result, 4: count, 5: 1 + carry}, flags)

    # Signed overflow, and unsigned wraparound: non-S arithmetic must not
    # erase V/C. Both computations themselves must still write their result.
    add('overflow-preserved', [
        'mvn r0,#0x80000000', 'mov r1,#1', 'adds r3,r0,r1',
        'add r4,r1,r1', 'movvs r2,#9', 'movge r5,#10', 'movvc r6,#11'],
        {0: 0x7fffffff, 2: 9, 3: 0x80000000, 4: 2, 5: 10, 6: 0}, 9)
    add('unsigned-wrap-preserved', [
        'mvn r0,#0', 'mov r1,#1', 'adds r3,r0,r1',
        'add r4,r1,r1', 'adc r2,r1,#0', 'moveq r5,#10', 'movne r6,#11'],
        {0: 0xffffffff, 2: 2, 3: 0, 4: 2, 5: 10, 6: 0}, 6)

    # Compare/test opcodes write flags even though they preserve destinations.
    for op, flags in (('cmp r0,r0', 6), ('cmn r0,r1', 0),
                      ('tst r0,r1', 2), ('teq r0,r0', 6)):
        add(f'flag-writer-{op[:3]}', [
            'mov r0,#5', 'mov r1,#1', 'cmp r0,r0', op,
            'adc r2,r1,#0'], {0: 5, 1: 1, 2: 1 + ((flags >> 1) & 1)},
            flags, 'control')

    # False predicate on an S=1 producer must preserve its destination too.
    add('skipped-s-preserves-zero', [
        'mov r0,#5', 'mov r2,#0x55', 'cmp r0,r0',
        'addsne r2,r0,#1', 'moveq r3,#9', 'adc r4,r0,#0'],
        {0: 5, 2: 0x55, 3: 9, 4: 6}, 6)
    add('load-bit20-is-not-s', [
        'mov r0,#0', 'mov r1,#42', 'str r1,[r0]',
        *['mov r9,r9'] * 4, 'mov r4,#5', 'cmp r4,r4',
        'ldr r2,[r0]', 'adc r3,r4,#0', 'moveq r5,#9'],
        {0: 0, 1: 42, 2: 42, 3: 6, 5: 9}, 6)
    add('store-preserves-flags', [
        'mov r0,#0', 'mov r1,#42', 'mov r4,#5', 'cmp r4,r4',
        'str r1,[r0]', 'adc r3,r4,#0', 'moveq r5,#9'],
        {0: 0, 1: 42, 3: 6, 5: 9}, 6)
    add('skipped-branch-preserves-flags', [
        'mov r0,#5', 'cmp r0,r0', 'bne #0',
        'adc r2,r0,#0', 'moveq r3,#9'], {0: 5, 2: 6, 3: 9}, 6)
    return tests


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', type=Path, default=HERE.parent)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    source, out = args.source.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    report = {'source': str(source), 'scope': 'full native DeepPipeline, A32, PC=4; no CPU state injection',
              'tests': [], 'commands': []}

    def run(cmd, logfile, timeout=30, input_text=None):
        cmd = [str(x) for x in cmd]
        p = subprocess.run(cmd, cwd=out, input=input_text, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        (out / logfile).write_text(p.stdout)
        report['commands'].append({'argv': cmd, 'exit_code': p.returncode,
                                   'log': str(out / logfile)})
        return p

    try:
        iv = os.environ.get('IVERILOG') or shutil.which('iverilog')
        vvp = os.environ.get('VVP') or shutil.which('vvp')
        if not iv or not vvp:
            raise FileNotFoundError('iverilog and vvp must be on PATH or set with IVERILOG and VVP')
        ivcmd = [iv]
        ivl = os.environ.get('IVERILOG_IVL')
        if ivl:
            ivcmd += ['-B', ivl]
        mc = os.environ.get('LLVM_MC', 'llvm-mc')
        report['versions'] = {name: run(cmd, name + '-version.log').stdout.splitlines()[0]
                              for name, cmd in (('iverilog', [*ivcmd, '-V']),
                                                ('vvp', [vvp, '-V']), ('llvm-mc', [mc, '--version']))}
        report['source_sha256'] = {f: hashlib.sha256((source / f).read_bytes()).hexdigest()
                                   for f in FILES}
        report['test_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in (Path(__file__), HERE / 'nzcv_forward_tb.v')}
        p = run([*ivcmd, '-g2005', '-s', 'nzcv_forward_tb', '-o', out / 'probe.vvp',
                 HERE / 'nzcv_forward_tb.v', *[source / f for f in FILES]], 'compile.log')
        if p.returncode:
            raise RuntimeError('RTL compilation failed; see compile.log')
        for case in cases():
            name = case['name']
            assembly = '.syntax unified\n.arm\n' + '\n'.join(case['body'] + ['mov r12,#126']) + '\n'
            (out / (name + '.s')).write_text(assembly)
            p = run([mc, '-triple=armv4t-none-eabi', '-show-encoding'],
                    name + '-assembly.log', input_text=assembly)
            if p.returncode:
                raise RuntimeError(f'{name}: assembly failed')
            encodings = re.findall(r'encoding: \[([^\]]+)\]', p.stdout)
            words = [int.from_bytes(bytes(int(x.strip(), 16) for x in e.split(',')), 'little')
                     for e in encodings]
            if len(words) != len(case['body']) + 1 or len(words) > 250:
                raise RuntimeError(f'{name}: invalid program size')
            image = [0xe1a09009] + words + [0xe1a09009] * (255 - len(words))
            mem = out / (name + '.memh')
            mem.write_text(''.join(f'{w:08x}\n' for w in image))
            cmd = [vvp, out / 'probe.vvp', '+MEM=' + str(mem)]
            p = run(cmd, name + '.log', timeout=10)
            observed = dict(re.findall(r'RESULT (r\d+|nzcv)=([0-9a-fxz]+)', p.stdout))
            def matches(key, expected):
                actual = observed.get(key, '')
                if not actual or any(c in actual for c in 'xz'):
                    return False
                mask = case.get('nzcv_mask', 15) if key == 'nzcv' else 0xffffffff
                return (int(actual, 16) & mask) == (int(expected, 16) & mask)

            diffs = {key: {'expected': val, 'actual': observed.get(key)}
                     for key, val in case['expected'].items() if not matches(key, val)}
            passed = p.returncode == 0 and not diffs
            report['tests'].append({**case, 'words': [f'{w:08x}' for w in words],
                                    'command': [str(x) for x in cmd], 'exit_code': p.returncode,
                                    'observed': observed, 'differences': diffs, 'pass': passed,
                                    'log': str(out / (name + '.log'))})
            print(f'{"PASS" if passed else "FAIL"} {name}: {json.dumps(diffs)}', flush=True)
        report['passed'] = sum(t['pass'] for t in report['tests'])
        report['failed'] = len(report['tests']) - report['passed']
        report['exit_code'] = 1 if report['failed'] else 0
    except Exception as exc:
        report['error'] = str(exc)
        report['exit_code'] = 2
        print(str(exc), flush=True)
    (out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    return report['exit_code']


if __name__ == '__main__':
    raise SystemExit(main())
