# Binwalk version information.
#
# When binwalk is installed (pip install / setup.py install) the version is
# taken from the installed package metadata.  When it is run straight from the
# source tree (portable mode, no installation) the metadata does not exist, so
# fall back to a fixed string instead of crashing at import time.
FALLBACK_VERSION = "2.4.3"

try:
    from importlib import metadata
    try:
        __version__ = metadata.version("binwalk")
    except metadata.PackageNotFoundError:
        __version__ = FALLBACK_VERSION
except Exception:
    __version__ = FALLBACK_VERSION


def get_version():
    return __version__
