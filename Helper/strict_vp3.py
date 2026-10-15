"""Narrow VP3 reader corrections for the pinned pyembroidery decoder.

Adapted from pyembroidery Vp3Reader (MIT; see Resources/ThirdPartyNotices.txt).
Retains its layout parsing, fixes axis-aligned block placement, and rejects
unknown/truncated stitch records instead of silently dropping them.
"""
from pyembroidery import Vp3Reader as reader
from pyembroidery.ReadHelper import read_int_16be, read_int_32be


def read(stream, out):
    stream.read(6)
    reader.skip_vp3_string(stream)
    stream.seek(7, 1)
    reader.skip_vp3_string(stream)
    stream.seek(32, 1)
    center_x = reader.signed32(read_int_32be(stream)) / 100
    center_y = -reader.signed32(read_int_32be(stream)) / 100
    stream.seek(27, 1)
    reader.skip_vp3_string(stream)
    stream.seek(24, 1)
    reader.skip_vp3_string(stream)
    count = read_int_16be(stream)
    if count is None or not 1 <= count <= 1000:
        raise ValueError('Invalid VP3 thread count.')
    for i in range(count):
        read_block(stream, out, center_x, center_y)
        if i+1 < count:
            out.color_change()
    out.end()


def read_block(stream, out, center_x, center_y):
    if stream.read(3) != b'\x00\x05\x00':
        raise ValueError('Invalid VP3 color block.')
    length = read_int_32be(stream)
    if length is None:
        raise ValueError('Truncated VP3 block length.')
    end = stream.tell()+length
    if end > len(stream.getbuffer()):
        raise ValueError('Truncated VP3 color block.')
    start_x = reader.signed32(read_int_32be(stream))/100 + center_x
    start_y = -reader.signed32(read_int_32be(stream))/100 + center_y
    # Always honor the absolute block position, including zero on either axis.
    out.move_abs(start_x, start_y)
    out.add_thread(reader.vp3_read_thread(stream))
    stream.seek(15, 1)
    if stream.read(3) != b'\x0a\xf6\x00' or stream.tell() > end:
        raise ValueError('Invalid VP3 stitch block.')
    data = stream.read(end-stream.tell())
    i = 0
    while i < len(data):
        # A final 0 byte is a documented writer block terminator, not a movement.
        if i == len(data)-1 and data[i] == 0:
            break
        if i+2 > len(data):
            raise ValueError('Truncated VP3 movement.')
        a,b=data[i:i+2];i+=2
        if a != 0x80:
            out.stitch(a if a<128 else a-256,b if b<128 else b-256)
        elif b == 1:
            if i+6 > len(data) or data[i+4:i+6] != b'\x80\x02':
                raise ValueError('Invalid VP3 extended movement.')
            x=int.from_bytes(data[i:i+2],'big',signed=True)
            y=int.from_bytes(data[i+2:i+4],'big',signed=True)
            out.stitch(x,y);i+=6
        elif b == 3:
            out.trim()
        else:
            raise ValueError(f'Unsupported VP3 control 0x80 {b:02x}.')
