#!/usr/bin/env python3
"""Test the climatology guards with tiny real NetCDF files (requires CDO/ncgen)."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKERS = [ROOT / 'scripts/core' / f'climatology_window_from_{kind}.slurm.sh'
           for kind in ('timeseries', 'monthly_files')]


@unittest.skipUnless(shutil.which('cdo') and shutil.which('ncgen'), 'requires cdo and ncgen')
class MonthlyCoverageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def fixture(self, name, days, calendar='standard'):
        # A three-month field with a CF time axis; no production data are used.
        path = self.root / name
        cdl = '''netcdf fixture {
 dimensions: time = UNLIMITED; lat = 1; lon = 1;
 variables: double time(time); time:units = "days since 2000-01-01";
 time:calendar = "%s"; double lat(lat); lat:units = "degrees_north";
 double lon(lon); lon:units = "degrees_east"; float thetao(time,lat,lon);
 data: time = %s; lat = 0; lon = 0; thetao = %s;
}''' % (calendar, ','.join(map(str, days)), ','.join('1' for _ in days))
        subprocess.run(['ncgen', '-o', str(path)], input=cdl, text=True, check=True)
        return path

    def check_guard(self, paths, success, expected='', start=None, end=None):
        for worker, mode in zip(WORKERS, ('timeseries', 'monthly')):
            with self.subTest(worker=worker.name):
                # Execute the exact embedded guard, not a reimplementation.
                block = worker.read_text().split("<<'PY_MONTHLY_COVERAGE'\n", 1)[1].split('\nPY_MONTHLY_COVERAGE', 1)[0]
                first = start or ('2000-01-01' if mode == 'timeseries' else '200001')
                last = end or ('2000-03-31' if mode == 'timeseries' else '200003')
                result = subprocess.run([sys.executable, '-', first, last, mode, *map(str, paths)],
                                        input=block, text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, success, result.stderr)
                self.assertIn(expected, result.stdout + result.stderr)

    def test_supported_calendars(self):
        for calendar, days in [('standard', [0, 31, 60]), ('noleap', [0, 31, 59]),
                               ('360_day', [29, 59, 89])]:
            with self.subTest(calendar=calendar):
                self.check_guard([self.fixture(calendar+'.nc', days, calendar)], True, '3 months')

    def test_missing_month(self):
        self.check_guard([self.fixture('missing.nc', [0, 60])], False, 'Missing months: 2000-02')

    def test_duplicate_month_different_days(self):
        self.check_guard([self.fixture('duplicate.nc', [0, 31, 45, 60])], False, 'Duplicate month 2000-02')

    def test_overlapping_chunks(self):
        self.check_guard([self.fixture('one.nc', [0, 31]), self.fixture('two.nc', [31, 60])],
                         False, 'Duplicate month 2000-02')

    def test_complete_chunks(self):
        self.check_guard([self.fixture('one.nc', [0, 31]), self.fixture('two.nc', [60])], True)

    def test_unreadable_input(self):
        self.check_guard([self.root/'absent.nc'], False, 'Monthly coverage validation')

    def test_failure_preserves_existing_output_in_both_workers(self):
        self.fixture('thetao_200001.nc', [0])
        self.fixture('thetao_200003.nc', [60])
        for worker, mode in zip(WORKERS, ('timeseries', 'monthly')):
            with self.subTest(worker=worker.name):
                out = self.root / mode
                out.mkdir()
                existing = out / 'fixture_clim_2000-2000.nc'
                existing.write_bytes(b'previous accepted output')
                env = dict(os.environ, VAR='thetao', IN_DIR=str(self.root), IN_FILE='',
                           OUT_DIR=str(out), TMP_DIR=str(out/'tmp'), OUT_PREFIX='fixture',
                           WINDOW_START='2000-01-01' if mode == 'timeseries' else '200001',
                           WINDOW_END='2000-03-31' if mode == 'timeseries' else '200003',
                           FILE_GLOB='thetao_*.nc', MERGE_INPUTS='auto', EXPECTED_N='3')
                result = subprocess.run(['bash', str(worker)], env=env, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Missing months: 2000-02', result.stderr)
                self.assertEqual(existing.read_bytes(), b'previous accepted output')


if __name__ == '__main__':
    unittest.main()
