# The disassembly module (-Y / --disasm) needs the third party "capstone"
# library. It is intentionally not loaded in this build (no extra dependencies).

# Don't load the compression module if the lzma module can't be found
try:
    from binwalk.modules.compression import RawCompression
except ImportError:
    pass

from binwalk.modules.signature import Signature
from binwalk.modules.hexdiff import HexDiff
from binwalk.modules.general import General
from binwalk.modules.extractor import Extractor
from binwalk.modules.entropy import Entropy
