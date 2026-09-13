#!/usr/bin/env python3
"""Small local regression fixtures; no downloads or Slurm submissions are made."""
import ast
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import numpy as np
import xarray as xr

ROOT = Path(__file__).resolve().parents[2]
DELTA = ROOT/'scripts/core/delta_from_climatologies.slurm.sh'
ADD = ROOT/'scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh'
AUDIT = ROOT/'scripts/tools/audit_ocean_downscaling_product_integrity.sh'
SMOKE = ROOT/'scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh'


def embedded(path, marker):
    return path.read_text().split("<<'"+marker+"'\n", 1)[1].split('\n'+marker, 1)[0]


class SafeguardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, PATH=str(Path(sys.executable).parent)+os.pathsep+os.environ['PATH'])

    def run_script(self, path, **env):
        return subprocess.run(['bash', str(path)], cwd=ROOT, env=dict(self.env, **env), capture_output=True, text=True)

    def field(self, value=1., time='2006-01-01'):
        da = xr.DataArray(np.full((1, 2, 2, 2), value), dims=('time', 'lev', 'lat', 'lon'),
                          coords={'time': [np.datetime64(time)], 'lev': [0., 10.], 'lat': [-1., 1.], 'lon': [0., 2.]}, name='thetao')
        for name, unit in [('lev', 'm'), ('lat', 'degrees_north'), ('lon', 'degrees_east')]:
            da[name].attrs['units'] = unit
        da.attrs['units'] = 'degC'
        return da

    def spatial_helper(self, path):
        text = path.read_text()
        start = text.index('def validate_spatial_coordinates(')
        end = text.index('\n\n', text.index('raise ValueError(f"{label}: expected singleton climatology time")', start))
        scope = {'np': np}
        exec(text[start:end], scope)
        return scope['validate_spatial_coordinates']

    def test_spatial_matching_and_different_times(self):
        for path in (DELTA, ADD):
            self.spatial_helper(path)(self.field(), self.field(time='2050-01-01'), 'test')

    def test_reversed_coordinates_and_depth_units_fail(self):
        for path in (DELTA, ADD):
            check = self.spatial_helper(path)
            with self.assertRaisesRegex(ValueError, 'values/order'):
                check(self.field(), self.field().isel(lat=slice(None, None, -1)), 'test')
            candidate = self.field(); candidate.lev.attrs['units'] = 'cm'
            with self.assertRaisesRegex(ValueError, 'units'):
                check(self.field(), candidate, 'test')

    def test_2d_mask_broadcast_only_when_explicit(self):
        for path in (DELTA, ADD):
            check = self.spatial_helper(path)
            mask = self.field().isel(time=0, lev=0, drop=True)
            check(self.field(), mask, 'mask', allow_broadcast=True)
            with self.assertRaises(ValueError):
                check(self.field(), mask, 'anomaly')

    def test_real_delta_calculations(self):
        base = self.root/'base.nc'; future = self.root/'future.nc'
        self.field(2.).to_netcdf(base); self.field(6., '2050-01-01').to_netcdf(future)
        for mode, expected in [('additive', 4.), ('log_ratio', np.log(3.))]:
            out = self.root/mode
            result = self.run_script(DELTA, VAR='thetao', BASELINE_FILE=str(base), FUTURE_FILE=str(future), OUT_DIR=str(out), DELTA_MODE=mode, OUT_PREFIX='fixture', FUTURE_TAG='2050-2060', BASELINE_TAG='2006-2014')
            self.assertEqual(result.returncode, 0, result.stderr)
            with xr.open_dataset(out/'fixture_delta_2050-2060_minus_2006-2014.nc') as ds:
                np.testing.assert_allclose(ds.thetao, expected)

    def test_invalid_delta_preserves_old_output(self):
        base = self.root/'base.nc'; future = self.root/'future.nc'; out = self.root/'out'; out.mkdir()
        self.field().to_netcdf(base); self.field().isel(lat=slice(None, None, -1)).to_netcdf(future)
        old = out/'fixture_delta_future_minus_baseline.nc'; old.write_bytes(b'accepted')
        result = self.run_script(DELTA, VAR='thetao', BASELINE_FILE=str(base), FUTURE_FILE=str(future), OUT_DIR=str(out), OUT_PREFIX='fixture')
        self.assertNotEqual(result.returncode, 0); self.assertEqual(old.read_bytes(), b'accepted')

    def test_real_add_and_mismatch(self):
        base = self.root/'base.nc'; anomaly = self.root/'anomaly.nc'; out = self.root/'out'
        self.field(2.).to_netcdf(base); self.field(4., '2050-01-01').to_netcdf(anomaly)
        env = dict(VAR='thetao', BASELINE_FILE=str(base), ANOMALY_FILE=str(anomaly), OUT_DIR=str(out), OUT_PREFIX='fixture', FUTURE_TAG='2050-2060', COASTAL_FILL='no', FILL_TOP_MISSING='no')
        result = self.run_script(ADD, **env)
        self.assertEqual(result.returncode, 0, result.stderr)
        product = next(out.glob('*.nc'))
        with xr.open_dataset(product) as ds: np.testing.assert_allclose(ds.thetao, 6.)
        original = product.read_bytes()
        self.field().isel(lon=slice(None, None, -1)).to_netcdf(anomaly)
        result = self.run_script(ADD, **env)
        self.assertNotEqual(result.returncode, 0); self.assertEqual(product.read_bytes(), original)

    def test_integrity_rejects_empty_and_missing_time_bounds(self):
        products = self.root/'products'; products.mkdir()
        report = self.root/'audit.csv'
        env = dict(PRODUCT_ROOT=str(products), OUT_FILE=str(report))
        self.assertNotEqual(self.run_script(AUDIT, **env).returncode, 0)
        file = products/'future/Model/r1i1p1f1/ssp585/thetao/2050-2060/0p05/Model_ssp585_thetao_2050-2060_0p05.nc'
        file.parent.mkdir(parents=True); self.field(time='2055-01-01').to_netcdf(file)
        result = self.run_script(AUDIT, **env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing_time_bounds', report.read_text())
        self.assertEqual(self.run_script(AUDIT, **env, FAIL_ON_ISSUE='no').returncode, 0)

    def test_expected_missing_product_is_reported(self):
        products = self.root/'products'; products.mkdir()
        expected = self.root/'expected.txt'; expected.write_text('future/missing.nc\n')
        report = self.root/'report.csv'
        result = self.run_script(AUDIT, PRODUCT_ROOT=str(products), OUT_FILE=str(report), EXPECTED_FILES=str(expected))
        self.assertNotEqual(result.returncode, 0); self.assertIn('missing_product', report.read_text())

    def test_organizer_resumes_missing_files_and_rejects_different_copy(self):
        source = self.root/'downscaled/Model/r1i1p1f1/ssp585/thetao/0p05/2050-2060'; source.mkdir(parents=True)
        (source/'one.nc').write_bytes(b'one'); (source/'two.nc').write_bytes(b'two')
        products = self.root/'products'; target = products/'future/Model/r1i1p1f1/ssp585/thetao/2050-2060/0p05'; target.mkdir(parents=True)
        (target/'one.nc').write_bytes(b'one')
        tool = ROOT/'scripts/tools/organize_ocean_downscaling_products.sh'
        env = dict(PRODUCT_ROOT=str(products), DOWNSCALED_ROOT=str(self.root/'downscaled'), ORGANIZE_SCOPE='future', VAR='thetao', WINDOW='2050-2060', MODELS='Model', NPROC='2')
        result = self.run_script(tool, **env)
        self.assertEqual(result.returncode, 0, result.stderr); self.assertEqual((target/'two.nc').read_bytes(), b'two')
        (target/'one.nc').write_bytes(b'partial')
        result = self.run_script(tool, **env)
        self.assertNotEqual(result.returncode, 0); self.assertEqual((target/'one.nc').read_bytes(), b'partial')

    def test_all_cannot_submit_and_predecessors_checked(self):
        result = self.run_script(SMOKE, RUN='yes', STEP='all')
        self.assertNotEqual(result.returncode, 0); self.assertIn('unsafe', result.stderr)
        block = embedded(SMOKE, 'PY_JOB_STATUS')
        for accounting, status in [('123|COMPLETED|0:0|', 0), ('123|RUNNING|0:0|', 1), ('', 1), ('123|COMPLETED|1:0|', 1)]:
            result = subprocess.run([sys.executable, '-', '123', accounting], input=block, text=True, capture_output=True)
            self.assertEqual(result.returncode, status)

    def test_complete_climatologies_match_committed_calculation(self):
        times = xr.date_range('2000-01-01', periods=3, freq='MS')
        field = self.field().isel(time=0, drop=True).expand_dims(time=times).copy()
        field.values[:] = np.arange(3)[:, None, None, None] + 1
        inputs = self.root/'inputs'; inputs.mkdir()
        series = self.root/'series.nc'; field.to_netcdf(series)
        for i in range(3): field.isel(time=slice(i, i+1)).to_netcdf(inputs/f'thetao_20000{i+1}.nc')
        for kind in ('timeseries', 'monthly_files'):
            worker = ROOT/f'scripts/core/climatology_window_from_{kind}.slurm.sh'
            old = self.root/f'old_{kind}.sh'
            old.write_text(subprocess.check_output(['git', 'show', 'HEAD:'+str(worker.relative_to(ROOT))], cwd=ROOT, text=True))
            outputs = []
            for label, script in [('old', old), ('new', worker)]:
                out = self.root/f'{kind}_{label}'
                env = dict(VAR='thetao', OUT_DIR=str(out), OUT_PREFIX='fixture', FILL_TOP_MISSING='no')
                if kind == 'timeseries': env.update(IN_FILE=str(series), IN_DIR='', WINDOW_START='2000-01-01', WINDOW_END='2000-03-31')
                else: env.update(IN_DIR=str(inputs), WINDOW_START='200001', WINDOW_END='200003', EXPECTED_N='3')
                result = self.run_script(script, **env)
                self.assertEqual(result.returncode, 0, result.stderr)
                with xr.open_dataset(next(out.glob('*.nc'))) as ds: outputs.append(ds.load())
            xr.testing.assert_equal(outputs[0], outputs[1])
            np.testing.assert_allclose(outputs[1].thetao, 2.)

    def test_new_model_input_preflight(self):
        downloads = self.root/'downloads'
        def write_input(experiment, start, periods, member='r1i1p1f1', units='degC'):
            path = downloads/'Model'/member/experiment/'thetao'/f'thetao_Omon_Model_{experiment}_{member}_gn_chunks.nc'
            path.parent.mkdir(parents=True, exist_ok=True)
            field = self.field().isel(time=0, drop=True).expand_dims(time=xr.date_range(start, periods=periods, freq='MS'))
            field.attrs['units'] = units
            field.to_netcdf(path)
            return path
        write_input('historical', '2006-01-01', 108)
        future = write_input('ssp585', '2050-01-01', 12)
        env = dict(STEP='inputs', IPCC_ESGF_ROOT=str(self.root), SMOKE_MODEL='Model', SMOKE_SCENARIO='ssp585', SMOKE_VARS='thetao', SMOKE_WINDOWS='2050-2050')
        result = self.run_script(SMOKE, **env)
        self.assertEqual(result.returncode, 0, result.stderr)
        future.unlink(); future = write_input('ssp585', '2050-01-01', 11)
        result = self.run_script(SMOKE, **env)
        self.assertNotEqual(result.returncode, 0); self.assertIn('2050-12=0', result.stderr)
        future.unlink(); future = write_input('ssp585', '2050-01-01', 12, member='r2i1p1f1')
        result = self.run_script(SMOKE, **env)
        self.assertNotEqual(result.returncode, 0); self.assertIn('members differ', result.stderr)
        future.unlink(); write_input('ssp585', '2050-01-01', 12, units='K')
        result = self.run_script(SMOKE, **env)
        self.assertNotEqual(result.returncode, 0); self.assertIn('source units differ', result.stderr)

    def test_fetch_manifest_conflicts_empty_selection_and_download_failure(self):
        manifest = self.root/'manifest.csv'
        fields = ['filename', 'source_id', 'member_id', 'experiment_id', 'variable_id', 'url', 'checksum_type', 'checksum']
        row = dict(zip(fields, ['thetao_Omon_Model_historical_r1i1p1f1_gn_200601-201412.nc', 'Model', 'r1i1p1f1', 'historical', 'thetao', 'https://example.invalid/fixture.nc', 'sha256', 'a'*64]))
        def write(rows):
            with manifest.open('w') as stream:
                writer = csv.DictWriter(stream, fieldnames=fields); writer.writeheader(); writer.writerows(rows)
        def run(**options):
            env = dict(self.env, MANIFEST=str(manifest), OUT_ROOT=str(self.root/'fetch'), DOWNLOAD='no', MODELS='Model', REPLICA_FALLBACK='no')
            env.update(options)
            return subprocess.run(['Rscript', str(ROOT/'scripts/R/fetch_ipcc_esgf_cmip6_manifest.R')], env=env, capture_output=True, text=True)
        write([row]); self.assertEqual(run().returncode, 0)
        result = run(MODELS='Absent'); self.assertNotEqual(result.returncode, 0); self.assertIn('No manifest rows', result.stderr)
        write([row, dict(row, checksum='b'*64)])
        result = run(LIMIT='1'); self.assertNotEqual(result.returncode, 0); self.assertIn('Conflicting checksums', result.stderr)
        write([row])
        fake_bin = self.root/'bin'; fake_bin.mkdir()
        wget = fake_bin/'wget'; wget.write_text('#!/bin/sh\nexit 1\n'); wget.chmod(0o755)
        result = run(DOWNLOAD='yes', PATH=str(fake_bin)+os.pathsep+self.env['PATH'])
        self.assertNotEqual(result.returncode, 0); self.assertIn('Failed: 1', result.stderr)

    def test_provenance_hashes_and_preserves_record(self):
        settings = self.root/'settings.json'; settings.write_text('{"window":"2050-2060"}')
        product = self.root/'product.nc'; product.write_bytes(b'fixture')
        output = self.root/'release.json'; tool = ROOT/'scripts/tools/record_ocean_pipeline_release.sh'
        args = ['bash', str(tool), str(product)]
        env = dict(self.env, SETTINGS_FILE=str(settings), OUT_FILE=str(output))
        result = subprocess.run(args, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(output.read_text())
        self.assertEqual(record['files'][0]['sha256'], hashlib.sha256(b'fixture').hexdigest())
        self.assertNotEqual(subprocess.run(args, env=env, capture_output=True).returncode, 0)


if __name__ == '__main__': unittest.main()
