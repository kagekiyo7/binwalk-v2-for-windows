# Helpers for locating and invoking the bundled 7-Zip command line tool.
#
# In this build of binwalk *all* extraction is performed through 7-Zip.
# 7-Zip lives in a "7-Zip" folder inside the binwalk package directory
# (<...>/binwalk/7-Zip/7z.exe on Windows).
#
# extract.conf refers to the executable through the "%7z" placeholder
# because the rule file is colon-delimited and a Windows path ("C:\...")
# cannot be written into it directly.

import os
import sys
import shutil

# Placeholder used in extract.conf / -D rules for the 7-Zip executable.
PLACEHOLDER = '%7z'

# Name of the folder (inside the binwalk package directory) holding 7-Zip.
FOLDER_NAME = '7-Zip'

# Environment variable that can be used to point at a different 7z executable.
ENV_VAR = 'BINWALK_7Z'


def package_dir():
    '''Directory of the binwalk python package (the "binwalk" folder).'''
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def bundled_dir():
    '''Path of the 7-Zip folder that is expected inside the binwalk folder.'''
    return os.path.join(package_dir(), FOLDER_NAME)


def _candidate_names():
    if sys.platform.startswith('win'):
        return ['7z.exe']
    # Non-Windows hosts (only useful for development / testing).
    return ['7zz', '7z', '7za']


def find_7z():
    '''
    Returns the full path of the 7-Zip command line executable,
    or None if it could not be found.

    Search order:
        1. The BINWALK_7Z environment variable
        2. <binwalk package folder>/7-Zip/
        3. (non-Windows only) 7zz / 7z / 7za found in $PATH
    '''
    override = os.environ.get(ENV_VAR)
    if override and os.path.isfile(override):
        return os.path.abspath(override)

    for name in _candidate_names():
        path = os.path.join(bundled_dir(), name)
        if os.path.isfile(path):
            return path

    if not sys.platform.startswith('win'):
        for name in _candidate_names():
            found = shutil.which(name)
            if found:
                return found

    return None


def split_command(command):
    '''
    Splits a command line string into an argument list.

    On Windows, shlex.split() (POSIX mode) treats backslashes as escape
    characters and destroys paths such as C:\\work\\fw.bin, so a simple
    quote-aware splitter without backslash escapes is used instead.
    Both double and single quotes group words; the quotes are removed.
    '''
    if not sys.platform.startswith('win'):
        import shlex
        return shlex.split(command)

    args = []
    current = []
    quote = None
    in_token = False

    for ch in command:
        if quote:
            if ch == quote:
                quote = None
            else:
                current.append(ch)
        elif ch in ('"', "'"):
            quote = ch
            in_token = True
        elif ch.isspace():
            if in_token:
                args.append(''.join(current))
                current = []
                in_token = False
        else:
            current.append(ch)
            in_token = True

    if in_token:
        args.append(''.join(current))

    return args


def resolve_placeholder(args):
    '''
    Replaces the first argument with the real 7-Zip path if it is the
    "%7z" placeholder. Returns None if 7-Zip cannot be found.
    '''
    if args and args[0] == PLACEHOLDER:
        exe = find_7z()
        if exe is None:
            return None
        return [exe] + args[1:]
    return args
