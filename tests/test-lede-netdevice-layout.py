"""Pinned header regression; LP64 TX model is not a Linux kernel build."""
import argparse, hashlib, pathlib, re, subprocess, tempfile, shutil, sys
import urllib.request
repo = pathlib.Path(__file__).resolve().parents[1]
if not __debug__:
    sys.exit('Regression requires assertions: unset PYTHONOPTIMIZE and do not use python -O')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source_tree', type=pathlib.Path, help='unmodified pinned LEDE source checkout')
parser.add_argument('header', help='Linux 6.12.114 netdevice.h path, or fetch to download and verify it')
parser.add_argument('--evidence-dir', type=pathlib.Path, default=repo / '.omo/evidence/build-repair')
args = parser.parse_args()
source = args.source_tree.resolve()
evidence = args.evidence_dir.resolve()
for executable in ['patch', 'gcc', 'clang']:
    if not shutil.which(executable):
        sys.exit('Missing regression prerequisite: ' + executable)
folders = ['generic/backport-6.12', 'generic/pending-6.12', 'generic/hack-6.12', 'qualcommax/patches-6.12']
for folder in folders:
    if not (source / 'target/linux' / folder).is_dir():
        sys.exit('Missing pinned LEDE patch directory: ' + str(source / 'target/linux' / folder))
if (source / 'target/linux/qualcommax/patches-6.12/9999-netdevice-nss-flags-layout.patch').exists():
    sys.exit('Pass the unmodified source checkout before running the adapter')
evidence.mkdir(parents=True, exist_ok=True)
if args.header == 'fetch':
    header = evidence / 'netdevice-6.12.114.h'
    urllib.request.urlretrieve('https://raw.githubusercontent.com/gregkh/linux/v6.12.114/include/linux/netdevice.h', header)
else:
    header = pathlib.Path(args.header).resolve()
if not header.is_file():
    sys.exit('Missing Linux 6.12.114 header: ' + str(header))
if hashlib.sha256(header.read_bytes()).hexdigest() != '8f2d524eb955b2ca9ac49f1e717b059b43b7429a0de2a3edc05cfa035b42be1a':
    sys.exit('Linux 6.12.114 netdevice.h SHA256 mismatch')
with tempfile.TemporaryDirectory() as directory:
    work = pathlib.Path(directory)
    target = work / 'include/linux/netdevice.h'
    target.parent.mkdir(parents=True)
    shutil.copyfile(header, target)
    patches = []
    for folder in folders:
        for patch in sorted((source / 'target/linux' / folder).glob('*.patch')):
            text = patch.read_text()
            match = re.search(r'^--- a/include/linux/netdevice.h\n\+\+\+ b/include/linux/netdevice.h\n.*?(?=^--- |\Z)', text, re.M | re.S)
            if match:
                result = subprocess.run(['patch', '-p1', '--batch', '--forward'], input=match[0], text=True, cwd=work, capture_output=True)
                assert result.returncode == 0, (patch, result.stdout, result.stderr)
                patches.append(str(patch.relative_to(source)))
    original = target.read_text()
    def model(text, name):
        group = text.split('__cacheline_group_begin(net_device_read_tx);', 1)[1].split('__cacheline_group_end(net_device_read_tx);', 1)[0]
        group = group.replace('struct_group(priv_flags_fast,', 'struct {').replace('\n\t);', '\n\t};').replace('unsigned long', 'unsigned long long')
        prefix = '''#include <stdint.h>
#define __rcu
#define CONFIG_XPS 1
#define CONFIG_NETFILTER_EGRESS 1
#define CONFIG_NET_XGRESS 1
#define TC_MAX_QUEUE 16
#define XPS_MAPS_MAX 2
typedef uint64_t netdev_features_t;
typedef uint16_t u16;
typedef int16_t s16;
struct netdev_tc_txq { u16 count; u16 offset; };
struct model {
'''
        path = work / (name + '.c')
        path.write_text(prefix + group + '\n};\n_Static_assert(sizeof(struct model) <= 160, "TX group exceeds 160");\n')
        for compiler in ['gcc', 'clang']:
            result = subprocess.run([compiler, '-std=gnu11', '-c', str(path), '-o', str(work / (name + '.o'))], capture_output=True, text=True)
            log = evidence / ('task-1-' + name + '-' + compiler + '.log')
            log.write_text('Invocation: ' + compiler + ' -std=gnu11 -c source-derived model\n' + result.stdout + result.stderr + '\nExit: ' + str(result.returncode))
            assert (result.returncode == 0) == (name == 'green'), log
        shutil.copyfile(path, evidence / ('task-1-' + name + '.c'))
    model(original, 'red')
    patch = repo / 'patches/lede/9999-netdevice-nss-flags-layout.patch'
    result = subprocess.run(['patch', '-p1', '--fuzz=0', '--batch'], input=patch.read_text(), text=True, cwd=work, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    fixed = target.read_text()
    assert fixed.count('unsigned int\t\tpriv_flags_ext;') == 1
    assert fixed.index('unsigned int\t\tpriv_flags_ext;') > fixed.index('__cacheline_group_end(net_device_read_rx);')
    model(fixed, 'green')
    target.write_text(original.replace('__cacheline_group_end(net_device_read_rx);', '__cacheline_group_end(changed);'))
    result = subprocess.run(['patch', '-p1', '--fuzz=0', '--batch', '--dry-run'], input=patch.read_text(), text=True, cwd=work, capture_output=True)
    assert result.returncode != 0
    (evidence / 'task-1-patch-audit.log').write_text('\n'.join(patches) + '\nMalformed RX anchor rejected: ' + result.stdout)
print('PASS: full pinned netdevice patch stack, RED/GREEN GCC and Clang LP64 TX model, unique ungrouped field, malformed RX anchor rejection. Actual ARM64 kernel compilation remains required.')
