"""Frozen behavior of the pinned format writers, including lossy command mappings."""
import base64
import csv
import io
import unittest
from unittest.mock import patch
import pyembroidery as e
from format_helper import export
from test_format_helper import fixture

FORMATS = ('pes','pec','dst','exp','jef','vp3','xxx')

class FormatMatrixTests(unittest.TestCase):
    def test_all_formats_preserve_asymmetric_needles(self):
        for fmt in FORMATS:
            with self.subTest(format=fmt):
                request=fixture();request['format']=fmt
                result=export(request)
                self.assertEqual(result['stitchCount'],31)
                self.assertEqual((result['width'],result['height']),(32,25))
                self.assertEqual(result['format'],fmt)
                self.assertTrue(result['warnings'])

    def test_repeated_colors_and_consecutive_stops(self):
        for fmt in FORMATS:
            with self.subTest(format=fmt):
                request=fixture();request['format']=fmt
                request['plan']['threads'].append({'hex':0xdc6552,'name':'Coral'})
                commands=request['plan']['commands'];commands.pop()
                for op,thread in [('stop',0),('stitch',0),('colorChange',1),('stitch',1),('colorChange',0),('stitch',0),('stop',0),('stop',0),('end',0)]:
                    commands.append({'op':op,'point':{'x':12,'y':15},'thread':thread})
                result=export(request)
                rows=list(csv.reader(io.StringIO(result['threadCSV'])))
                self.assertEqual(len(rows),7) # header + six sewing blocks
                self.assertEqual(rows[3][2],'#DC6552')
                self.assertTrue(any('Stops' in w for w in result['warnings']))

    def test_vp3_block_starting_on_an_axis_after_travel_exports(self):
        # An imported block can end with a jump; the next colour change then sits at the jump's
        # destination. VP3 drops jumps and records that point as the next block's start, which
        # the pinned reader skips when x or y is 0, so valid files used to fail verification.
        for x,y in [(0,5),(5,0),(0,0)]:
            with self.subTest(start=(x,y)):
                commands=[{'op':'jump','point':{'x':-20,'y':-10},'thread':0}]
                commands+=[{'op':'stitch','point':{'x':-20+i,'y':-10+i},'thread':0} for i in range(8)]
                commands+=[{'op':'jump','point':{'x':x,'y':y},'thread':0},{'op':'colorChange','point':{'x':x,'y':y},'thread':1}]
                commands+=[{'op':'stitch','point':{'x':x+i,'y':y+i},'thread':1} for i in range(6)]
                commands.append({'op':'end','point':{'x':x+5,'y':y+5},'thread':1})
                request={'version':1,'format':'vp3','hoop':{'width':100,'height':100,'oval':False},
                         'plan':{'commands':commands,'threads':[{'hex':0x167c80,'name':'Ocean'},{'hex':0xdc6552,'name':'Coral'}]}}
                data=base64.b64decode(export(request)['bytes'])
                legacy=e.read_vp3(io.BytesIO(data))
                legacy_last=[(px,py) for px,py,op in legacy.stitches if op&e.COMMAND_MASK==e.STITCH][-1]
                self.assertNotEqual(legacy_last,((x+5)*10,-(y+5)*10),'Fixture must expose the pinned reader axis-placement bug')

    def test_travel_never_becomes_a_sewn_connection(self):
        for fmt in FORMATS:
            with self.subTest(format=fmt):
                request=fixture();request['format']=fmt
                commands=request['plan']['commands'];commands.pop()
                for op in ['jump','stitch','end']:
                    commands.append({'op':op,'point':{'x':-24,'y':-20},'thread':0})
                result=export(request)
                decoded=getattr(e,'read_'+fmt)(io.BytesIO(base64.b64decode(result['bytes'])))
                last_needle=max(i for i,s in enumerate(decoded.stitches) if s[2]&255==e.STITCH)
                preceding=decoded.stitches[last_needle-1][2]&255
                self.assertIn(preceding,(e.JUMP,e.TRIM))
                self.assertEqual(result['stitchCount'],32)

    def test_color_mapping_csv(self):
        for fmt in FORMATS:
            with self.subTest(format=fmt):
                result=export(dict(fixture(),format=fmt))
                row=list(csv.reader(io.StringIO(result['threadCSV'])))[1]
                self.assertEqual(row[2],'#167C80')
                if fmt in ('dst','exp'):self.assertEqual(row[3],'not stored')
                elif fmt in ('vp3','xxx','pes'):self.assertEqual(row[3],row[2])
                else:self.assertNotEqual(row[3],row[2])

    def test_xxx_thread_block_limit(self):
        request=fixture();request['format']='xxx'
        commands=request['plan']['commands'];commands.pop()
        for _ in range(21):commands.append({'op':'stop','point':{'x':12,'y':15},'thread':0})
        commands.append({'op':'end','point':{'x':12,'y':15},'thread':0})
        with self.assertRaisesRegex(ValueError,'21 thread blocks'):export(request)

    def test_jef_header_contains_offset_placement(self):
        request=fixture();request['format']='jef';request['hoop']['width']=200
        for c in request['plan']['commands']:c['point']['x']+=60
        with self.assertRaisesRegex(ValueError,'encoded JEF hoop'):export(request)

    def test_rounded_encoded_moves_respect_hoop(self):
        for fmt in FORMATS:
            request=fixture();request['format']=fmt;request['hoop']['width']=20
            with self.subTest(format=fmt),self.assertRaisesRegex(ValueError,'outside'):export(request)

    def test_corrupt_needle_output_is_rejected(self):
        for fmt in FORMATS:
            original=getattr(e,'write_'+fmt)
            def corrupt(pattern,stream,settings):
                altered=pattern.copy()
                for s in altered.stitches:
                    if s[2]&255==e.STITCH:s[0]+=5;break
                original(altered,stream,settings)
            with self.subTest(format=fmt),patch.object(e,'write_'+fmt,side_effect=corrupt),self.assertRaisesRegex(ValueError,'needle positions'):
                export(dict(fixture(),format=fmt))

    def test_missing_color_boundary_is_rejected(self):
        request=fixture();request['plan']['threads'].append({'hex':0xff0000,'name':'Red'})
        request['plan']['commands'][2]['thread']=1
        with self.assertRaisesRegex(ValueError,'explicit color-change'):export(request)

    def test_csv_names_cannot_be_spreadsheet_formulas(self):
        request=fixture();request['plan']['threads'][0]['name']='=1+2'
        row=list(csv.reader(io.StringIO(export(request)['threadCSV'])))[1]
        self.assertEqual(row[1],"'=1+2")

    def test_unicode_thread_names_preserved_in_csv(self):
        request=fixture();request['format']='vp3';request['plan']['threads'][0]['name']='Océan 藍'
        row=list(csv.reader(io.StringIO(export(request)['threadCSV'])))[1]
        self.assertEqual(row[1],'Océan 藍')

    def test_thread_brand_and_code_reach_csv_and_pes(self):
        request=fixture();request['plan']['threads'][0].update(brand='Madeira Polyneon',code='1610')
        result=export(request)
        header,row=list(csv.reader(io.StringIO(result['threadCSV'])))[:2]
        self.assertEqual(header[-2:],['Brand','Code']);self.assertEqual(row[-2:],['Madeira Polyneon','1610'])
        decoded=e.read_pes(io.BytesIO(base64.b64decode(result['bytes'])))
        self.assertEqual((decoded.threadlist[0].brand,decoded.threadlist[0].catalog_number),('Madeira Polyneon','1610'))
        plain=export(fixture())
        self.assertEqual(list(csv.reader(io.StringIO(plain['threadCSV'])))[1][-2:],['',''])
        request['plan']['threads'][0]['code']=5
        with self.assertRaisesRegex(ValueError,'brand or code'):export(request)

    def test_pes_for_a_larger_hoop_records_its_size(self):
        from format_helper import pes_hoop
        request=fixture();request['hoop'].update(width=130,height=180)
        for c in request['plan']['commands']:c['point']['y']+=60   # beyond the old 50 mm limit, inside a 5x7 hoop
        result=export(request);data=base64.b64decode(result['bytes'])
        self.assertEqual(pes_hoop(data),(130,180))
        self.assertTrue(any('larger than 100' in w for w in result['warnings']))
        self.assertEqual(pes_hoop(base64.b64decode(export(fixture())['bytes'])),(100,100))
        self.assertFalse(any('larger than 100' in w for w in export(fixture())['warnings']))
        request['hoop']['height']=100
        with self.assertRaisesRegex(ValueError,'outside'):export(request)

    def test_pes6_csv_distinguishes_embedded_palette(self):
        row=list(csv.reader(io.StringIO(export(fixture())['threadCSV'])))[1]
        self.assertEqual(row[2],row[3]);self.assertNotEqual(row[3],row[4])

    def test_same_rgb_different_names_reports_palette_changes(self):
        for fmt in ('jef',):
            request=fixture();request['format']=fmt
            request['plan']['threads'].append({'hex':0x167c80,'name':'Different name'})
            commands=request['plan']['commands'];commands.pop()
            for op in ('colorChange','stitch','end'):
                commands.append({'op':op,'point':{'x':12,'y':15},'thread':1})
            self.assertTrue(any('identical requested RGB' in w for w in export(request)['warnings']))

    def test_leading_control_is_explicitly_rejected(self):
        for op in ('stop','trim','colorChange'):
            request=fixture();request['plan']['commands'][0]['op']=op
            with self.assertRaisesRegex(ValueError,'must begin'):export(request)

    def test_dst_trim_near_edge_is_conservatively_rejected(self):
        request=fixture();request['format']='dst'
        commands=request['plan']['commands'];commands.pop()
        for op in ('jump','stitch','trim','end'):
            commands.append({'op':op,'point':{'x':50,'y':0},'thread':0})
        with self.assertRaisesRegex(ValueError,'Encoded movement'):export(request)

    def test_unknown_format_and_early_end_rejected(self):
        with self.assertRaisesRegex(ValueError,'Unsupported export'):export(dict(fixture(),format='bogus'))
        request=fixture();request['plan']['commands'][2]['op']='end'
        with self.assertRaisesRegex(ValueError,'final END'):export(request)
