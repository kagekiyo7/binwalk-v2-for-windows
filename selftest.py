#!/usr/bin/env python3
"""
Self test for the 7-Zip based binwalk build.

Run it after installation (or straight from the source tree):

    py -3 selftest.py

It checks that
  1. binwalk can be imported and the bundled 7-Zip is found and runs,
  2. a ZIP and a GZIP embedded in a binary blob are extracted through 7-Zip,
  3. a zlib stream is extracted with the python standard library (as in the original binwalk),
  4. a format that has no extractor at all (Motorola S-Record) is silently skipped
     when --extract is used.
"""
import os
import sys
import gzip
import zlib
import shutil
import zipfile
import tempfile
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))

try:
    import binwalk  # installed copy
except ImportError:
    sys.path.insert(0, os.path.join(HERE, "src"))  # portable (not installed) use
    import binwalk

import binwalk.core.sevenzip as sevenzip

PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(binwalk.__file__)))
FAILED = []


def report(ok, text):
    print("[%s] %s" % (" OK " if ok else "NG ", text))
    if not ok:
        FAILED.append(text)


def run_binwalk(args):
    env = dict(os.environ)
    env["PYTHONPATH"] = PKG_PARENT + os.pathsep + env.get("PYTHONPATH", "")
    p = subprocess.run([sys.executable, "-m", "binwalk"] + args, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       universal_newlines=True, errors="replace")
    return p.returncode, p.stdout


def find_file(root, name):
    for d, _dirs, files in os.walk(root):
        if name in files:
            return os.path.join(d, name)
    return None


def main():
    print("binwalk package : %s" % os.path.dirname(os.path.abspath(binwalk.__file__)))
    print("python          : %s (%s)" % (sys.version.split()[0], sys.executable))

    # 1. 7-Zip
    exe = sevenzip.find_7z()
    report(exe is not None, "7-Zip found: %s" % exe)
    if exe is None:
        print("Expected location: %s" % sevenzip.bundled_dir())
        return 1
    try:
        p = subprocess.run([exe, "i"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           stdin=subprocess.DEVNULL, universal_newlines=True, errors="replace")
        banner = [l for l in p.stdout.splitlines() if l.strip().startswith("7-Zip")]
        report(p.returncode == 0, "7-Zip runs: %s" % (banner[0].strip() if banner else "?"))
    except OSError as e:
        report(False, "7-Zip could not be started: %s" % e)
        return 1

    work = tempfile.mkdtemp(prefix="binwalk selftest ")  # contains a space on purpose
    try:
        prefix = bytes(range(256)) * 2
        suffix = bytes(reversed(range(256))) * 2

        # 2a. ZIP embedded in a blob
        zpath = os.path.join(work, "payload.zip")
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("dir/hello.txt", "hello from zip\n" * 20)
        blob_zip = os.path.join(work, "fw_zip.bin")
        with open(blob_zip, "wb") as f:
            f.write(prefix + open(zpath, "rb").read() + suffix)

        out = os.path.join(work, "out_zip")
        rc, text = run_binwalk(["-e", "-C", out, blob_zip])
        got = find_file(out, "hello.txt")
        report(got is not None and "hello from zip" in open(got, errors="replace").read(),
               "ZIP embedded in a binary is extracted through 7-Zip")

        # 2b. GZIP embedded in a blob
        gpath = os.path.join(work, "payload.gz")
        with gzip.open(gpath, "wb") as g:
            g.write(b"hello from gzip\n" * 50)
        blob_gz = os.path.join(work, "fw_gz.bin")
        with open(blob_gz, "wb") as f:
            f.write(prefix + open(gpath, "rb").read() + suffix)

        out = os.path.join(work, "out_gz")
        rc, text = run_binwalk(["-e", "-C", out, blob_gz])
        found = False
        for d, _dirs, files in os.walk(out):
            for fn in files:
                if not fn.lower().endswith(".gz"):
                    if b"hello from gzip" in open(os.path.join(d, fn), "rb").read():
                        found = True
        report(found, "GZIP embedded in a binary is extracted (python gzip, 7-Zip as fallback)")

        # 3. zlib stream: not a 7-Zip format, but the original binwalk extracted it with the
        #    python standard library, so it must still be extracted that way.
        blob_z = os.path.join(work, "fw_zlib.bin")
        data = b"".join(b"line %d of some text that compresses well\n" % i for i in range(400))
        with open(blob_z, "wb") as f:
            f.write(prefix + zlib.compress(data, 9) + suffix)
        out = os.path.join(work, "out_zlib")
        rc, text = run_binwalk(["-e", "-C", out, blob_z])
        found = False
        for d, _dirs, files in os.walk(out):
            for fn in files:
                if not fn.lower().endswith(".zlib"):
                    if open(os.path.join(d, fn), "rb").read() == data:
                        found = True
        report(found, "zlib stream is extracted with the python standard library")

        # 4. a format with neither a 7-Zip handler nor a python extractor
        #    (Motorola S-Record) must be detected but skipped silently.
        def srec(addr, payload):
            body = bytes([len(payload) + 3, (addr >> 8) & 255, addr & 255]) + payload
            return "S1%s%02X" % (body.hex().upper(), (~sum(body)) & 255)
        lines = [srec(i * 16, bytes(range(i, i + 16))) for i in range(8)] + ["S9030000FC"]
        blob_s = os.path.join(work, "fw.srec")
        with open(blob_s, "w") as f:
            f.write("\n".join(lines) + "\n")
        rc, scan_text = run_binwalk([blob_s])
        detected = "s-record" in scan_text.lower()
        out = os.path.join(work, "out_srec")
        rc, text = run_binwalk(["-e", "-C", out, blob_s])
        nothing = (not os.path.exists(out)) or (not os.listdir(out))
        report(detected, "S-Record is still detected by the signature scan")
        report(nothing and "warning" not in text.lower() and "error" not in text.lower(),
               "S-Record (no extractor available) is skipped without output / warning")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print()
    if FAILED:
        print("SELF TEST FAILED (%d problem(s))" % len(FAILED))
        return 1
    print("SELF TEST PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
