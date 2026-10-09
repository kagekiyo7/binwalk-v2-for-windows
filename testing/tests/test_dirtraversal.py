import os
import binwalk


def test_dirtraversal():
    '''
    Test: Open dirtraversal.tar, scan for signatures.
    Verify that dangerous symlinks have been sanitized.
    '''
    bad_symlink_file_list = ['foo', 'bar', 'subdir/foo2', 'subdir/bar2']
    good_symlink_file_list = ['subdir/README_link', 'README2_link']

    input_vector_file = os.path.join(os.path.dirname(__file__),
                                     "input-vectors",
                                     "dirtraversal.tar")

    # 7-Zip based extraction places the archive contents in "tar-root".
    output_directory = os.path.join(os.path.dirname(__file__),
                                    "input-vectors",
                                    "_dirtraversal.tar.extracted",
                                    "tar-root")

    scan_result = binwalk.scan(input_vector_file,
                               signature=True,
                               extract=True,
                               quiet=True)[0]

    # Make sure the bad symlinks have been sanitized and the
    # good symlinks have not been sanitized.
    # 7-Zip (25.01+) neutralizes dangerous symlinks itself (absolute / ".." targets are
    # re-rooted inside the output directory or the entry is stored as an empty file), and
    # binwalk's own sanitizer replaces any remaining escaping link with /dev/null.
    # Either way, a bad entry must never resolve to a location outside the extraction directory.
    safe_root = os.path.realpath(output_directory)
    for symlink in bad_symlink_file_list:
        linktarget = os.path.realpath(os.path.join(output_directory, symlink))
        assert linktarget == os.devnull or linktarget.startswith(safe_root + os.path.sep)
    for symlink in good_symlink_file_list:
        linktarget = os.path.realpath(os.path.join(output_directory, symlink))
        assert linktarget != os.devnull
