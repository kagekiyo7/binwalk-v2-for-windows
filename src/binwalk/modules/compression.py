# Performs raw decompression of various compression algorithms (currently,
# only deflate).

import os
import zlib
import struct
import binwalk.core.common
from binwalk.core.compat import str2bytes, bytes2str
from binwalk.core.module import Option, Kwarg, Module
try:
    import lzma
except ImportError:
    from backports import lzma


class LZMAHeader(object):

    def __init__(self, **kwargs):
        for (k, v) in kwargs.items():
            setattr(self, k, v)


class LZMA(object):

    DESCRIPTION = "Raw LZMA compression stream"
    COMMON_PROPERTIES = [0x5D, 0x6E]
    MAX_PROP = ((4 * 5 + 4) * 9 + 8)
    BLOCK_SIZE = 32 * 1024

    def __init__(self, module):
        self.module = module
        self.properties = None

        self.build_properties()
        self.build_dictionaries()
        self.build_headers()

        # Add an extraction rule. The extractor below builds a proper LZMA header
        # in front of the raw stream and then hands the result to the normal
        # "lzma compressed data" rules (python lzma module first, 7-Zip fallback).
        if self.module.extractor.enabled:
            self.module.extractor.add_rule(regex='^%s' % self.DESCRIPTION.lower(), extension="lzma", cmd=self.extractor)

    def extractor(self, file_name):
        # Open and read the file containing the raw compressed data.
        # This is not terribly efficient, especially for large files...
        with binwalk.core.common.BlockFile(file_name) as fp:
            compressed_data = str2bytes(fp.read())

        # Re-run self.decompress to detect the properties for this compressed
        # data (stored in self.properties)
        if not self.decompress(bytes2str(compressed_data[:self.BLOCK_SIZE])):
            return False

        # Build an LZMA header on top of the raw compressed data and write it back to disk.
        # Header consists of the detected properties values, the largest possible dictionary size,
        # and a fake output file size field.
        header = str2bytes(chr(self.properties) + self.dictionaries[-1] + ("\xFF" * 8))
        with binwalk.core.common.BlockFile(file_name, "wb") as fp:
            fp.write(header + compressed_data)

        # Try to extract it with all the normal lzma extractors until one works
        for exrule in self.module.extractor.match("lzma compressed data"):
            if self.module.extractor.execute(exrule['cmd'], file_name) == True:
                return True

        return False

    def build_property(self, pb, lp, lc):
        prop = (((pb * 5) + lp) * 9) + lc
        if prop > self.MAX_PROP:
            return None
        return int(prop)

    def parse_property(self, prop):
        prop = int(ord(prop))

        if prop > self.MAX_PROP:
            return None

        pb = prop // (9 * 5)
        prop -= pb * 9 * 5
        lp = prop // 9
        lc = prop - lp * 9

        return (pb, lp, lc)

    def parse_header(self, header):
        (pb, lp, lc) = self.parse_property(header[0])
        dictionary = struct.unpack("<I", str2bytes(header[1:5]))[0]
        return LZMAHeader(pb=pb, lp=lp, lc=lc, dictionary=dictionary)

    def build_properties(self):
        self.properties = set()

        if self.module.partial_scan == True:
            # For partial scans, only check the most common properties values
            for prop in self.COMMON_PROPERTIES:
                self.properties.add(chr(prop))
        else:
            for pb in range(0, 9):
                for lp in range(0, 5):
                    for lc in range(0, 5):
                        prop = self.build_property(pb, lp, lc)
                        if prop is not None:
                            self.properties.add(chr(prop))

    def build_dictionaries(self):
        self.dictionaries = []

        if self.module.partial_scan == True:
            # For partial scans, only use the largest dictionary value
            self.dictionaries.append(bytes2str(struct.pack("<I", 2 ** 25)))
        else:
            for n in range(16, 26):
                self.dictionaries.append(bytes2str(struct.pack("<I", 2 ** n)))

    def build_headers(self):
        self.headers = set()

        for prop in self.properties:
            for dictionary in self.dictionaries:
                self.headers.add(prop + dictionary + ("\xFF" * 8))

    def decompress(self, data):
        result = None
        description = None

        for header in self.headers:
            # The only acceptable exceptions are those indicating that the
            # input data was truncated.
            try:
                final_data = str2bytes(header + data)
                lzma.decompress(final_data)
                result = self.parse_header(header)
                break
            except IOError as e:
                # The Python2 module gives this error on truncated input data.
                if str(e) == "unknown BUF error":
                    result = self.parse_header(header)
                    break
            except Exception as e:
                # The Python3 module gives this error on truncated input data.
                # The inconsistency between modules is a bit worrisome.
                if str(e) == "Compressed data ended before the end-of-stream marker was reached":
                    result = self.parse_header(header)
                    break

        if result is not None:
            self.properties = self.build_property(result.pb, result.lp, result.lc)
            description = "%s, properties: 0x%.2X [pb: %d, lp: %d, lc: %d], dictionary size: %d" % (self.DESCRIPTION,
                                                                                                    self.properties,
                                                                                                    result.pb,
                                                                                                    result.lp,
                                                                                                    result.lc,
                                                                                                    result.dictionary)

        return description


class Deflate(object):

    '''
    Finds and extracts raw deflate compression streams.
    '''

    ENABLED = False
    BLOCK_SIZE = 33 * 1024
    DESCRIPTION = "Raw deflate compression stream"

    def __init__(self, module):
        self.module = module

        # Add an extraction rule (python zlib; 7-Zip cannot open raw deflate streams)
        if self.module.extractor.enabled:
            self.module.extractor.add_rule(regex='^%s' % self.DESCRIPTION.lower(), extension="deflate", cmd=self.extractor)

    def extractor(self, file_name):
        in_data = b""
        out_data = b""
        retval = False
        out_file = os.path.splitext(file_name)[0]

        with binwalk.core.common.BlockFile(file_name, 'r') as fp_in:
            while True:
                (data, dlen) = fp_in.read_block()
                if not data or dlen == 0:
                    break
                else:
                    in_data += str2bytes(data[:dlen])

                try:
                    out_data = zlib.decompress(in_data, -15)
                    with binwalk.core.common.BlockFile(out_file, 'wb') as fp_out:
                        fp_out.write(out_data)
                    retval = True
                    break
                except zlib.error as e:
                    pass

        return retval

    def decompress(self, data):
        # Looking for either a valid decompression, or an error indicating
        # truncated input data
        try:
            # Negative window size (e.g., -15) indicates that raw decompression
            # should be performed
            zlib.decompress(str2bytes(data), -15)
        except zlib.error as e:
            if not str(e).startswith("Error -5"):
                # Bad data.
                return None

        return self.DESCRIPTION


class RawCompression(Module):

    TITLE = 'Raw Compression'

    CLI = [
        Option(short='X',
               long='deflate',
               kwargs={'enabled': True, 'scan_for_deflate': True},
               description='Scan for raw deflate compression streams'),
        Option(short='Z',
               long='lzma',
               kwargs={'enabled': True, 'scan_for_lzma': True},
               description='Scan for raw LZMA compression streams'),
        Option(short='P',
               long='partial',
               kwargs={'partial_scan': True},
               description='Perform a superficial, but faster, scan'),
        Option(short='S',
               long='stop',
               kwargs={'stop_on_first_hit': True},
               description='Stop after the first result'),
    ]

    KWARGS = [
        Kwarg(name='enabled', default=False),
        Kwarg(name='partial_scan', default=False),
        Kwarg(name='stop_on_first_hit', default=False),
        Kwarg(name='scan_for_deflate', default=False),
        Kwarg(name='scan_for_lzma', default=False),
    ]

    def init(self):
        self.decompressors = []

        if self.scan_for_deflate:
            self.decompressors.append(Deflate(self))
        if self.scan_for_lzma:
            self.decompressors.append(LZMA(self))

    def run(self):
        for fp in iter(self.next_file, None):

            file_done = False

            self.header()

            while not file_done:
                (data, dlen) = fp.read_block()
                if dlen < 1:
                    break

                for i in range(0, dlen):
                    for decompressor in self.decompressors:
                        description = decompressor.decompress(data[i:i + decompressor.BLOCK_SIZE])
                        if description:
                            self.result(description=description, file=fp, offset=fp.tell() - dlen + i)
                            if self.stop_on_first_hit:
                                file_done = True
                                break

                    if file_done:
                        break

                    self.status.completed += 1

                self.status.completed = fp.tell() - fp.offset

            self.footer()
