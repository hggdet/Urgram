#!/usr/bin/env python3
"""Generate Urgram build codesigning data from Telegram's fake-codesigning templates.

Takes build-system/fake-codesigning (Telegram's own template profiles, signed for
ph.telegra.Telegraph) and produces an equivalent directory whose profiles carry
Urgram's bundle id, app group and team, re-signed with the same bundled
SelfSigned certificate. The Make.py build only *parses* these profiles
(openssl smime -verify -noverify) to harvest entitlements; the shipped IPA is
fake-signed and is re-signed by the distributor's own certificate afterwards.

Usage:
    python3 generate_codesigning.py --out <dir> [--team TEAM] [--bundle BUNDLE_ID]
"""
import argparse
import base64
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone

OLD_TEAM = 'C67CF9S4VU'
OLD_BUNDLE = 'ph.telegra.Telegraph'


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE, **kw).stdout


def deep_replace(obj, pairs):
    if isinstance(obj, str):
        for old, new in pairs:
            obj = obj.replace(old, new)
        return obj
    if isinstance(obj, list):
        return [deep_replace(x, pairs) for x in obj]
    if isinstance(obj, dict):
        return {deep_replace(k, pairs): deep_replace(v, pairs) for k, v in obj.items()}
    return obj


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(here, '..', '..'))
    ap.add_argument('--templates', default=os.path.join(repo_root, 'build-system', 'fake-codesigning'))
    ap.add_argument('--out', required=True)
    ap.add_argument('--team', default='BUMPZKB7FC')
    ap.add_argument('--bundle', default='com.hggdet.urgram')
    args = ap.parse_args()

    pairs = [(OLD_TEAM + '.' + OLD_BUNDLE, args.team + '.' + args.bundle),
             (OLD_BUNDLE, args.bundle),
             (OLD_TEAM, args.team)]

    # --- extract the SelfSigned cert + key from the template p12 -------------
    make_dir = os.path.join(repo_root, 'build-system', 'Make')
    gen_src = open(os.path.join(make_dir, 'GenerateProfiles.py')).read()
    m = re.search(r"""p12_password\s*=\s*['"]([^'"]*)['"]""", gen_src)
    if not m:
        print('Could not find the SelfSigned p12 password in GenerateProfiles.py')
        sys.exit(1)
    p12_password = m.group(1)

    tmp = tempfile.mkdtemp()
    p12_path = os.path.join(args.templates, 'certs', 'SelfSigned.p12')
    pem = run(['openssl', 'pkcs12', '-in', p12_path, '-passin', 'pass:' + p12_password,
               '-nodes', '-legacy'])
    cert_pem_path = os.path.join(tmp, 'cert.pem')
    key_pem_path = os.path.join(tmp, 'key.pem')
    text = pem.decode('utf-8', 'replace')
    cert_block = re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', text, re.S).group(0)
    key_block = re.search(r'-----BEGIN (?:RSA )?PRIVATE KEY-----.*?-----END (?:RSA )?PRIVATE KEY-----', text, re.S).group(0)
    open(cert_pem_path, 'w').write(cert_block)
    open(key_pem_path, 'w').write(key_block)
    cert_der = run(['openssl', 'x509', '-outform', 'DER', '-in', cert_pem_path])

    # --- rewrite + re-sign every template profile ----------------------------
    out_profiles = os.path.join(args.out, 'profiles')
    out_certs = os.path.join(args.out, 'certs')
    os.makedirs(out_profiles, exist_ok=True)
    os.makedirs(out_certs, exist_ok=True)
    shutil.copy(p12_path, os.path.join(out_certs, 'SelfSigned.p12'))
    pub = os.path.join(args.templates, 'certs', 'Public.cer')
    if os.path.exists(pub):
        shutil.copy(pub, os.path.join(out_certs, 'Public.cer'))

    now = datetime.now(timezone.utc).replace(tzinfo=None)
    count = 0
    for name in sorted(os.listdir(os.path.join(args.templates, 'profiles'))):
        if not name.endswith('.mobileprovision'):
            continue
        raw = run(['openssl', 'smime', '-inform', 'der', '-verify', '-noverify',
                   '-in', os.path.join(args.templates, 'profiles', name)])
        profile = plistlib.loads(raw)

        suffix = name.replace('.mobileprovision', '')
        profile['Name'] = 'Urgram ' + suffix
        profile['UUID'] = str(uuid.uuid4()).upper()
        profile['CreationDate'] = now
        profile['ExpirationDate'] = now + timedelta(days=730)
        profile['TeamIdentifier'] = [args.team]
        profile['TeamName'] = 'Urgram'
        profile['DeveloperCertificates'] = [cert_der]
        profile.pop('DER-Encoded-Profile', None)
        profile = deep_replace(profile, pairs)

        plist_path = os.path.join(tmp, name + '.plist')
        with open(plist_path, 'wb') as f:
            plistlib.dump(profile, f, fmt=plistlib.FMT_XML)
        run(['openssl', 'smime', '-sign', '-binary', '-noattr', '-nodetach', '-md', 'sha256',
             '-signer', cert_pem_path, '-inkey', key_pem_path,
             '-in', plist_path, '-outform', 'DER',
             '-out', os.path.join(out_profiles, name)])
        count += 1
        print('generated', name)

    print('Done: {} profiles -> {}'.format(count, args.out))
    if count == 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
