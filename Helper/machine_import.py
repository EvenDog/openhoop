"""Bounded stitch-file decoding. No source path or external color companion is read."""
import base64
import io
import math
import pyembroidery as e
import strict_vp3

FORMATS = ('pes', 'pec', 'dst', 'exp', 'jef', 'vp3', 'xxx')
OPS = {e.STITCH:'stitch', e.JUMP:'jump', e.TRIM:'trim', e.STOP:'stop', e.COLOR_CHANGE:'colorChange', e.END:'end'}

class BoundedPattern(e.EmbPattern):
    def add_stitch_absolute(self, cmd, x=0, y=0):
        if len(self.stitches) >= 100_000:
            raise ValueError('Machine import is limited to 100,000 commands. Split the source design.')
        super().add_stitch_absolute(cmd, x, y)

    def add_thread(self, thread):
        if len(self.threadlist) >= 1000:
            raise ValueError('Machine import is limited to 1,000 thread blocks.')
        super().add_thread(thread)

    def interpolate_duplicate_color_as_stop(self):
        # Repeated color boundaries can also be intentional thread changes.
        # Retain the source boundary rather than infer a STOP from matching RGB.
        pass


def check_pec_stream(data, start):
    # PEC layout offsets are relative to the LA: block after the signature (or PES offset).
    if start+528 > len(data):raise ValueError('Truncated PEC stitch header.')
    size=int.from_bytes(data[start+514:start+517],'little')
    end=start+512+size
    if size<17 or end>len(data):raise ValueError('Invalid or truncated PEC stitch block.')
    i=start+528
    while i<end:
        a=data[i];i+=1
        if a==0xff:
            if i<len(data) and data[i]==0 and all(b==0 for b in data[i:end]):return
            raise ValueError('Invalid PEC end record.')
        if i>=end:raise ValueError('Truncated PEC movement.')
        b=data[i];i+=1
        if a==0xfe and b==0xb0:
            if i>=end:raise ValueError('Truncated PEC color change.')
            i+=1;continue
        if a&0x80:
            if a&0x40:raise ValueError('Unsupported PEC movement flags.')
            if i>=end:raise ValueError('Truncated PEC extended movement.')
            b=data[i];i+=1
        if b&0x80:
            if b&0x40:raise ValueError('Unsupported PEC movement flags.')
            if i>=end:raise ValueError('Truncated PEC extended movement.')
            i+=1
    raise ValueError('PEC end record missing; file may be truncated.')


def preflight(data, fmt):
    if not data or len(data) > 5_000_000:
        raise ValueError('Choose a nonempty machine file under 5 MB.')
    if fmt == 'pes':
        if not data.startswith(b'#PES') or len(data) < 12:
            raise ValueError('The file does not have a PES header.')
        offset = int.from_bytes(data[8:12], 'little')
        if offset < 12 or offset + 512 >= len(data):
            raise ValueError('The PES stitch-block offset is invalid or truncated.')
        check_pec_stream(data,offset)
    elif fmt == 'pec':
        if not data.startswith(b'#PEC0001') or len(data) < 540:
            raise ValueError('The PEC header is invalid or truncated.')
        check_pec_stream(data,8)
    elif fmt == 'dst':
        if len(data) < 515 or not data.startswith(b'LA:'):
            raise ValueError('The DST header is invalid or truncated.')
        if not any(data[i+2] & 0xf3 == 0xf3 for i in range(512, len(data)-2, 3)):
            raise ValueError('The DST end record is missing; the file may be truncated.')
    elif fmt == 'exp':
        i = 0
        while i < len(data):
            if i+2 > len(data):
                raise ValueError('Truncated EXP movement record.')
            if data[i] == 0x80:
                if data[i+1] not in (0x80, 0x02, 0x04, 0x01):
                    raise ValueError('Unsupported EXP control record.')
                if i+4 > len(data):
                    raise ValueError('Truncated EXP control record.')
                # The pinned EXP writer emits 07 00 as a fixed trim payload, not displacement.
                if data[i+1]==0x80 and data[i+2:i+4]!=b'\x07\x00':
                    raise ValueError('Unsupported EXP trim payload; expected 07 00.')
                i += 4
            else:
                i += 2
    elif fmt == 'vp3':
        if len(data) < 20 or not data.startswith(b'%vsm%'):
            raise ValueError('The VP3 header is invalid or truncated.')
    elif fmt == 'jef':
        if len(data) < 116:
            raise ValueError('Truncated JEF header.')
        offset = int.from_bytes(data[:4], 'little')
        colors = int.from_bytes(data[24:28], 'little')
        if not 1 <= colors <= 1000 or not 116+4*colors <= offset < len(data):
            raise ValueError('Invalid JEF stitch offset or thread count.')
        palette=[int.from_bytes(data[j:j+4],'little',signed=True) for j in range(116,116+4*colors,4)]
        color_index=1
        i=offset;ended=False
        while i < len(data):
            if i+2 > len(data):raise ValueError('Truncated JEF movement.')
            if data[i] != 0x80:i+=2;continue
            code=data[i+1]
            if code==0x10:ended=True;break
            if code not in (1,2):raise ValueError('Unsupported JEF control record.')
            if i+4>len(data):raise ValueError('Truncated JEF control record.')
            if code==1:
                if data[i+2:i+4] != b'\x00\x00':raise ValueError('A JEF color record also moves the needle; unsupported.')
                if color_index>=len(palette):raise ValueError('JEF has more color changes than its thread table.')
                if palette[color_index]==0:palette.pop(color_index)
                else:color_index+=1
            i+=4
        if not ended:raise ValueError('JEF end record missing; file may be truncated.')
    elif fmt == 'xxx':
        if len(data) < 260 or not 1 <= int.from_bytes(data[0x27:0x29], 'little') <= 1000:
            raise ValueError('The XXX header is invalid or truncated.')
        i=256;ended=False
        while i < len(data):
            if i+2>len(data):raise ValueError('Truncated XXX movement.')
            if data[i] in (0x7d,0x7e):size=5
            elif data[i] != 0x7f:size=2
            else:
                size=4;code=data[i+1]
                if code not in (1,3,8,0x7f,0x18) and not 0x0a<=code<=0x17:raise ValueError('Unsupported XXX control record.')
                if code in (0x7f,0x18):ended=True
                if (code==8 or 0x0a<=code<=0x17) and data[i+2:i+4]!=b'\x00\x00':raise ValueError('A XXX color record also moves the needle; unsupported.')
            if i+size>len(data):raise ValueError('Truncated XXX record.')
            i+=size
            if ended:break
        if not ended:raise ValueError('XXX end record missing; file may be truncated.')


def import_machine(request):
    if request.get('version') != 1 or request.get('operation') != 'import':
        raise ValueError('Unsupported import protocol.')
    fmt = request.get('format')
    if fmt not in FORMATS:
        raise ValueError('Unsupported import format.')
    encoded = request.get('bytes')
    if not isinstance(encoded, str) or len(encoded) > 6_666_668:
        raise ValueError('Choose a machine file under 5 MB.')
    data = base64.b64decode(encoded, validate=True)
    preflight(data, fmt)
    pattern = BoundedPattern()
    if fmt == 'vp3':
        strict_vp3.read(io.BytesIO(data),pattern)
    else:
        getattr(e, 'read_'+fmt)(io.BytesIO(data), settings={'trim_at':None, 'trim_distance':None, 'clipping':False, 'trims':False}, pattern=pattern)
    return decoded_plan(pattern, fmt)


def decoded_plan(pattern, fmt):
    warnings = ['Imported needle positions stay at their source size and placement. Scaling changes stitch density; it does not regenerate digitizing objects.',
                'Only decoded stitches and thread colors are imported. Machine setup/header metadata and original digitizing outlines are not retained.']
    if fmt == 'dst':
        warnings.append('DST trim-like jump sequences are kept as jumps; trim behavior depends on the controller. Sequin commands are unsupported.')
    if fmt == 'jef':
        warnings.append('JEF thread-table entries with palette index zero are decoded as stops by the format reader.')
    if fmt in ('pes', 'pec'):
        warnings.append('Repeated same-color boundaries remain color changes. The source may have used them as stops; resume with the intended thread.')
    commands, threads = [], []
    thread = 0
    unknown = False
    colors = (0x167c80, 0xdc6552, 0x293742, 0xcca550, 0x72966b, 0x8774b3, 0xca839c, 0xe8ddcb)
    def ensure_thread(index):
        nonlocal unknown
        if index >= 1000:
            raise ValueError('Machine import is limited to 1,000 thread blocks.')
        while len(threads) <= index:
            i = len(threads)
            color = pattern.threadlist[i] if i < len(pattern.threadlist) else None
            if color is None:
                unknown = True
                threads.append({'name':f'Unknown thread {i+1}', 'hex':colors[i % len(colors)]})
            else:
                threads.append({'name':str(color.description or f'Imported thread {i+1}')[:256], 'hex':color.color & 0xffffff})
    ended = False
    previous = {'x':0.0, 'y':0.0}
    if len(pattern.stitches) > 100_000:
        raise ValueError('Machine import is limited to 100,000 commands.')
    for x, y, code in pattern.stitches:
        if ended:
            raise ValueError('Unexpected commands after END.')
        if code not in OPS:
            raise ValueError(f'Unsupported machine command {code}; import cancelled without dropping it.')
        if not math.isfinite(x) or not math.isfinite(y) or max(abs(x),abs(y)) > 100_000:
            raise ValueError('Invalid or out-of-range machine coordinate.')
        point = {'x':x/10, 'y':-y/10}
        if code in (e.TRIM,e.STOP,e.COLOR_CHANGE,e.END) and point != previous:
            raise ValueError('A source control record also moves the needle. This decoder combination is not supported.')
        if code == e.COLOR_CHANGE:
            thread += 1
        ensure_thread(thread)
        commands.append({'op':OPS[code], 'point':point, 'thread':thread})
        previous = point
        ended = code == e.END
    if not ended or not any(c['op'] == 'stitch' for c in commands):
        raise ValueError('No complete stitch sequence was decoded.')
    if unknown:
        warnings.append('Some thread colors are absent. Deterministic colors labelled Unknown thread are placeholders; assign your actual threads.')
    points = [c['point'] for c in commands if c['op'] in ('stitch','jump')]
    if fmt in ('pes', 'pec'):
        # Brother files measure from the design's corner and carry no place in the hoop (the machine centers the
        # design), so the design is put in the middle of the hoop, where the machine sews it.
        cx = (max(p['x'] for p in points)+min(p['x'] for p in points))/2
        cy = (max(p['y'] for p in points)+min(p['y'] for p in points))/2
        for c in commands: c['point'] = {'x':round(c['point']['x']-cx, 4), 'y':round(c['point']['y']-cy, 4)}
        points = [c['point'] for c in commands if c['op'] in ('stitch','jump')]
        warnings.append('Brother files have no fixed place in the hoop, so the design is placed in the middle, as the machine sews it.')
    width = max(p['x'] for p in points)-min(p['x'] for p in points)
    height = max(p['y'] for p in points)-min(p['y'] for p in points)
    return {'version':1, 'ok':True, 'format':fmt, 'plan':{'commands':commands, 'threads':threads, 'warnings':[]},
            'warnings':warnings, 'width':width, 'height':height, 'stitchCount':sum(c['op']=='stitch' for c in commands)}
