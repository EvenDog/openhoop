import base64
import unittest
import pyembroidery as e
from machine_import import import_machine, decoded_plan, BoundedPattern
from format_helper import export
from test_format_helper import fixture

FORMATS=('pes','pec','dst','exp','jef','vp3','xxx')

def request(data, fmt):
    return {'version':1,'operation':'import','format':fmt,'bytes':base64.b64encode(data).decode()}

class MachineImportTests(unittest.TestCase):
    def test_all_seven_formats_preserve_needle_positions_and_orientation(self):
        source=fixture()
        expected=[(round(c['point']['x'],1),round(c['point']['y'],1)) for c in source['plan']['commands'] if c['op']=='stitch']
        # Brother files carry no place in the hoop, so they come back centered: the fixture spans x -20…12 and
        # y -10…15, so its middle (-4, 2.5) moves to the hoop center.
        centered=[(x+4,y-2.5) for x,y in expected]
        for fmt in FORMATS:
            with self.subTest(format=fmt):
                encoded=export(dict(source,format=fmt))
                result=import_machine(request(base64.b64decode(encoded['bytes']),fmt))
                actual=[(c['point']['x'],c['point']['y']) for c in result['plan']['commands'] if c['op']=='stitch']
                self.assertEqual(actual,centered if fmt in ('pes','pec') else expected)
                self.assertEqual((result['width'],result['height']),(32,25))
                self.assertEqual(result['stitchCount'],31)

    def test_hand_encoded_exp_preserves_jump_trim_color_and_mm(self):
        # EXP Y is up in its bytes; library exposes Y-down, adapter restores Y-up.
        data=bytes([10,20, 0x80,4,30,0, 0x80,0x80,7,0, 0x80,1,0,0, 5,0])
        result=import_machine(request(data,'exp'))
        commands=result['plan']['commands']
        self.assertEqual([c['op'] for c in commands],['stitch','jump','trim','colorChange','stitch','end'])
        self.assertEqual(commands[0]['point'],{'x':1,'y':2})
        self.assertEqual(commands[-2]['point'],{'x':4.5,'y':2})
        self.assertEqual(len(result['plan']['threads']),2)

    def test_missing_colors_are_deterministic_and_labelled_unknown(self):
        for fmt in ('exp','dst'):
            data=base64.b64decode(export(dict(fixture(),format=fmt))['bytes'])
            first=import_machine(request(data,fmt));second=import_machine(request(data,fmt))
            self.assertEqual(first,second)
            self.assertEqual(first['plan']['threads'][0]['name'],'Unknown thread 1')
            self.assertTrue(any('placeholders' in s for s in first['warnings']))

    def test_repeated_pes_colors_stay_explicit_boundaries(self):
        source=fixture();cmds=source['plan']['commands'];cmds.pop()
        for op in ['stop','stop','stitch','end']:
            cmds.append({'op':op,'point':{'x':12,'y':15},'thread':0})
        data=base64.b64decode(export(source)['bytes'])
        result=import_machine(request(data,'pes'))
        self.assertEqual(sum(c['op']=='colorChange' for c in result['plan']['commands']),2)
        self.assertEqual(sum(c['op']=='stop' for c in result['plan']['commands']),0)
        self.assertEqual(result['stitchCount'],32)

    def test_dst_jump_sequences_are_not_inferred_or_clipped(self):
        # Three zero jumps after a needle could be a trim convention; retain all three.
        data=b'LA:test\r'.ljust(512,b' ')+bytes([1,0,3, 0,0,0x83, 0,0,0x83, 0,0,0x83, 0,0,0xf3])
        result=import_machine(request(data,'dst'))
        self.assertEqual([c['op'] for c in result['plan']['commands']],['stitch','jump','jump','jump','end'])

    def test_unsupported_sequin_rejects_import(self):
        data=b'LA:test\r'.ljust(512,b' ')+bytes([1,0,3, 0,0,0x43, 0,0,0xf3])
        with self.assertRaisesRegex(ValueError,'Unsupported machine command'):
            import_machine(request(data,'dst'))

    def test_truncated_and_unknown_exp_controls_rejected(self):
        for data in [b'\x01',b'\x80\x04\x01',b'\x80\x99\x00\x00']:
            with self.subTest(data=data),self.assertRaises(ValueError):import_machine(request(data,'exp'))

    def test_bad_headers_empty_input_and_oversize_rejected(self):
        for fmt in FORMATS:
            with self.subTest(format=fmt),self.assertRaises(ValueError):import_machine(request(b'',fmt))
        for fmt in ('pes','pec','dst','jef','vp3','xxx'):
            with self.subTest(format=fmt),self.assertRaises(ValueError):import_machine(request(b'not a design',fmt))
        with self.assertRaises(ValueError):import_machine(request(b'\x00'*5_000_001,'exp'))
        with self.assertRaises(ValueError):import_machine({'version':1,'operation':'import','format':'exp','bytes':'??'})

    def test_invalid_protocol_and_format_rejected(self):
        for edit in [{'version':2},{'operation':'delete'},{'format':'emb'}]:
            with self.assertRaises(ValueError):import_machine(dict(request(b'\x01\x00','exp'),**edit))

    def test_decoded_nonfinite_unsupported_flag_and_moving_control_rejected(self):
        for stitches in [[[float('nan'),0,e.STITCH],[0,0,e.END]],[[0,0,e.STITCH|0x100],[0,0,e.END]],[[1,0,e.TRIM],[1,0,e.STITCH],[1,0,e.END]]]:
            pattern=e.EmbPattern();pattern.stitches=stitches
            with self.assertRaises(ValueError):decoded_plan(pattern,'exp')

    def test_decoded_stops_preserved_and_command_budget_enforced(self):
        pattern=BoundedPattern();pattern.stitch(1,2);pattern.stop();pattern.stop();pattern.end()
        result=decoded_plan(pattern,'exp')
        self.assertEqual([c['op'] for c in result['plan']['commands']],['stitch','stop','stop','end'])
        pattern.stitches=[[0,0,e.STITCH]]*100_000
        with self.assertRaisesRegex(ValueError,'100,000'):pattern.stitch(0,0)

    def test_pec_and_pes_truncated_and_reserved_records_rejected(self):
        for fmt in ('pec','pes'):
            original=base64.b64decode(export(dict(fixture(),format=fmt))['bytes'])
            start=8 if fmt=='pec' else int.from_bytes(original[8:12],'little')
            end=start+512+int.from_bytes(original[start+514:start+517],'little')
            for corrupt in [original[:end-1], original[:start+529]]:
                with self.subTest(format=fmt),self.assertRaises(ValueError):import_machine(request(corrupt,fmt))
            corrupt=bytearray(original);corrupt[start+528:start+530]=b'\xc0\x00'
            with self.assertRaisesRegex(ValueError,'Unsupported PEC'):import_machine(request(corrupt,fmt))
            corrupt=bytearray(original);corrupt[end-1]=0
            with self.assertRaises(ValueError):import_machine(request(corrupt,fmt))

    def test_jef_unknown_truncated_moving_and_excess_color_changes_rejected(self):
        data=base64.b64decode(export(dict(fixture(),format='jef'))['bytes'])
        offset=int.from_bytes(data[:4],'little')
        for payload in [b'\x01\x00\x80\x99\x00\x00',b'\x01',b'\x01\x00',b'\x80\x01\x01\x00\x80\x10',b'\x80\x01\x00\x00\x80\x10']:
            with self.subTest(payload=payload),self.assertRaises(ValueError):import_machine(request(data[:offset]+payload,'jef'))

    def test_xxx_unknown_truncated_and_moving_controls_rejected(self):
        data=base64.b64decode(export(dict(fixture(),format='xxx'))['bytes'])
        for payload in [b'\x01',b'\x7f\x99\x00\x00',b'\x7f\x08\x01\x00',b'\x7f\x01\x00',b'\x7d\x00\x00']:
            with self.subTest(payload=payload),self.assertRaises(ValueError):import_machine(request(data[:256]+payload,'xxx'))

    def test_exp_trim_payload_is_fixed_convention(self):
        with self.assertRaisesRegex(ValueError,'trim payload'):
            import_machine(request(b'\x01\x00\x80\x80\x08\x00','exp'))

    def test_vp3_axis_aligned_start_positions_are_preserved(self):
        import io
        for x,y in [(0,100),(100,0),(0,0)]:
            p=e.EmbPattern();p.add_thread('#167c80');p.add_thread('#dc6552')
            p.move_abs(-20,-20);p.stitch_abs(-20,-20);p.stitch_abs(-10,-10)
            # Build an independently placed second color block. High-level normalization
            # would move this boundary back to block 1, hiding the decoder defect.
            p.add_stitch_absolute(e.COLOR_CHANGE,x,y)
            p.move_abs(x,y);p.stitch_abs(x,y);p.stitch_abs(x+10,y+10);p.end()
            from pyembroidery import Vp3Writer
            data=io.BytesIO();Vp3Writer.write(p,data)
            result=import_machine(request(data.getvalue(),'vp3'))
            needles=[c['point'] for c in result['plan']['commands'] if c['op']=='stitch']
            expected=[{'x':x/10,'y':-y/10},{'x':(x+10)/10,'y':-(y+10)/10}]
            self.assertEqual(needles[-2:],expected)
            legacy=e.read_vp3(io.BytesIO(data.getvalue()))
            legacy_needles=[{'x':px/10,'y':-py/10} for px,py,op in legacy.stitches if op==e.STITCH]
            self.assertNotEqual(legacy_needles[-2:],expected,'Fixture must expose the pinned reader axis-placement bug')

    def test_vp3_unknown_and_truncated_control_records_rejected(self):
        data=base64.b64decode(export(dict(fixture(),format='vp3'))['bytes'])
        start=data.index(b'\x0a\xf6\x00')+3
        corrupt=bytearray(data);corrupt[start:start+2]=b'\x80\x77'
        with self.assertRaisesRegex(ValueError,'Unsupported VP3'):import_machine(request(corrupt,'vp3'))
        with self.assertRaises(ValueError):import_machine(request(data[:-4],'vp3'))
