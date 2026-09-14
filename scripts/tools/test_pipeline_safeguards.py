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

    def test_delivery_selection_for_roots_and_subtrees(self):
        names = ('aggregate_ocean_downscaling_products_by_depth_bins.sh',
                 'split_ocean_downscaling_products_by_depth.sh',
                 'export_ocean_downscaling_products_to_parquet.sh',
                 'export_ocean_downscaling_products_to_geotiff.sh',
                 'export_ocean_downscaling_products_bydepth_to_csv.sh')
        for name in names:
            source = (ROOT/'scripts/tools'/name).read_text()
            start = source.index('contains_word() {')
            end = source.index('\n}', source.index('include_relative_path() {')) + 2
            definitions = '\n'.join(line for line in source.splitlines()
                                    if line.startswith(('FUTURE_MODELS=', 'EXCLUDE_FUTURE_MODELS=',
                                                        'read -r -a FUTURE_MODEL_LIST',
                                                        'read -r -a EXCLUDE_FUTURE_MODEL_LIST')))
            # Exercise the production selector without invoking scientific tools.
            shell = definitions + '\n' + source[start:end] + '\ninclude_relative_path "$CASE_PATH"'
            cases = [('baseline/thetao/file.nc', True),
                     ('future/New-CMIP6/r1/file.nc', True),
                     ('future/ensemble/model_mean/file.nc', True),
                     ('future/cesm_f09_g16/001/file.nc', False),
                     ('future/legacy_downscaled_rcp85/legacy/file.nc', False)]
            for relative, accepted in cases:
                for subtree in (False, True):
                    parts = relative.split('/')
                    root = '/products/' + '/'.join(parts[:2]) if subtree else '/products'
                    tail = '/'.join(parts[2:]) if subtree else relative
                    result = subprocess.run(['bash', '-c', shell], env=dict(
                        self.env, FUTURE_MODELS='auto', MODEL_SELECTION_ROOT=root,
                        CASE_PATH=tail), capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, accepted, (name, relative, subtree, result.stderr))
            result = subprocess.run(['bash', '-c', shell], env=dict(
                self.env, FUTURE_MODELS='Selected', MODEL_SELECTION_ROOT='/products',
                CASE_PATH='future/New-CMIP6/r1/file.nc'), capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            for model, exclude, accepted in [('Selected', 'cesm_f09_g16 legacy_downscaled_rcp85', True),
                                             ('cesm_f09_g16', 'cesm_f09_g16 legacy_downscaled_rcp85', False),
                                             ('cesm_f09_g16', '', True)]:
                result = subprocess.run(['bash', '-c', shell], env=dict(
                    self.env, FUTURE_MODELS=model, EXCLUDE_FUTURE_MODELS=exclude,
                    MODEL_SELECTION_ROOT='/products', CASE_PATH=f'future/{model}/r1/file.nc'),
                    capture_output=True)
                self.assertEqual(result.returncode == 0, accepted, (name, model, exclude))

    def test_organizer_default_excludes_retired_models_and_fallback(self):
        downscaled = self.root/'downscaled'
        for model in ('New-CMIP6', 'cesm_f09_g16'):
            source = downscaled/model/'r1/ssp585/thetao/0p05/2050-2060'
            source.mkdir(parents=True); (source/'one.nc').write_bytes(model.encode())
        legacy = self.root/'legacy/thetao/2050-2060'
        legacy.mkdir(parents=True); (legacy/'old.nc').write_bytes(b'legacy')
        products = self.root/'products'
        env = dict(PRODUCT_ROOT=str(products), DOWNSCALED_ROOT=str(downscaled),
                   CESM_LEGACY_DOWNSCALED_ROOT=str(self.root/'legacy'),
                   ORGANIZE_SCOPE='future', VAR='thetao', WINDOW='2050-2060', MODELS='auto', NPROC='1')
        tool = ROOT/'scripts/tools/organize_ocean_downscaling_products.sh'
        result = self.run_script(tool, **env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list((products/'future').iterdir()), [products/'future/New-CMIP6'])
        self.assertEqual(next(products.rglob('one.nc')).read_bytes(), b'New-CMIP6')
        # With no accepted modern source, the existing legacy fallback stays excluded.
        result = self.run_script(tool, **dict(env, DOWNSCALED_ROOT=str(self.root/'absent')))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((products/'future/legacy_downscaled_rcp85').exists())

    def test_product_runners_forward_default_exclusions(self):
        bindir = self.root/'bin'; bindir.mkdir()
        # No cluster directories or jobs are created: intercept only runner setup/submission.
        for name, body in [('mkdir', 'exit 0'), ('sbatch', 'printf "%s\\n" "$@" >> "$CAPTURE"; echo 12345')]:
            stub = bindir/name; stub.write_text('#!/bin/bash\n' + body + '\n'); stub.chmod(0o755)
        # macOS Bash 3 lacks mapfile. Supply only the -t array-reading operation
        # for this submission harness; production still requires Bash 4+.
        startup = self.root/'bash_env'
        startup.write_text(r"""if ! type mapfile >/dev/null 2>&1; then
mapfile() {
    [[ "$1" == "-t" && "$#" == 2 ]] || return 2
    local destination="$2" item index=0
    unset "$destination"
    while IFS= read -r item; do
        eval "$destination[$index]=\"\$item\""
        index=$((index + 1))
    done
    return 0
}
fi
""")
        runners = [p for p in (ROOT/'scripts/runners/products').glob('*.sh')
                   if 'EXCLUDE_FUTURE_MODELS-cesm_f09_g16' in p.read_text()]
        self.assertEqual(len(runners), 10)
        source = self.root/'products'
        (source/'baseline/thetao').mkdir(parents=True)
        (source/'future/New-CMIP6').mkdir(parents=True)
        (source/'future/cesm_f09_g16').mkdir(parents=True)
        bash_major = int(subprocess.check_output(['bash', '-c', 'echo "${BASH_VERSINFO[0]}"'], text=True))
        for runner in runners:
            if bash_major < 4 and '${MAX_DEPTH_M,,}' in runner.read_text():
                # Lowercase expansion cannot be emulated by a function in Bash 3.
                # These two runners are fully exercised on the production Bash 4+.
                with self.subTest(runner=runner.name):
                    self.skipTest('Full runner requires Bash 4+ lowercase expansion')
                continue
            capture = self.root/'submission.txt'
            if capture.exists(): capture.unlink()
            result = self.run_script(runner, PATH=str(bindir)+os.pathsep+self.env['PATH'],
                CAPTURE=str(capture), BASH_ENV=str(startup), SOURCE_ROOT=str(source), IN_ROOT=str(source),
                PRODUCT_ROOT=str(source), FUTURE_MODELS='auto', MODELS='auto',
                VARS='thetao', WINDOWS='2050-2060', EXCLUDE_NODES='fixture-node')
            self.assertEqual(result.returncode, 0, (runner.name, result.stdout, result.stderr))
            submitted = capture.read_text()
            self.assertIn('EXCLUDE_FUTURE_MODELS', submitted, runner.name)
            self.assertIn('cesm_f09_g16 legacy_downscaled_rcp85', submitted, runner.name)

    def daily_field(self, name, year, month, count, calendar='standard', offsets=None):
        import netCDF4
        dates = netCDF4.num2date(np.arange(count) if offsets is None else offsets,
            f'days since {year:04d}-{month:02d}-01', calendar=calendar,
            only_use_cftime_datetimes=True)
        data = xr.DataArray(np.arange(len(dates)*4, dtype=float).reshape(len(dates), 2, 2),
            dims=('time', 'lat', 'lon'), name='thetao',
            coords={'time': dates, 'lat': [-1., 1.], 'lon': [0., 2.]})
        data.lat.attrs['units'] = 'degrees_north'
        data.lon.attrs['units'] = 'degrees_east'
        path = self.root/name
        data.to_netcdf(path)
        return path

    def test_daily_calendar_coverage_and_conflicting_versions(self):
        workers = [ROOT/'scripts/core/temporal_aggregate_regrid.slurm.sh',
                   ROOT/'scripts/bash/download_GLORYS_parallel.sh']
        self.assertEqual(embedded(workers[0], 'PY_DAILY_COVERAGE'),
                         embedded(workers[1], 'PY_DAILY_COVERAGE'))
        for year, month, count, calendar in [(2001, 2, 28, 'standard'),
                (2000, 2, 29, 'standard'), (2001, 4, 30, 'standard'),
                (2001, 1, 31, 'standard'), (2000, 2, 28, 'noleap'),
                (2001, 2, 30, '360_day'), (2001, 2, 29, 'all_leap')]:
            source = self.daily_field('daily.nc', year, month, count, calendar)
            for worker in workers:
                result = subprocess.run([sys.executable, '-', str(year), str(month), str(source)],
                    input=embedded(worker, 'PY_DAILY_COVERAGE'), capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
        for offsets, message in [(range(27), 'Missing days'),
                                 ([0, 0], 'duplicate'), ([28], 'out-of-month')]:
            source = self.daily_field('bad.nc', 2001, 2, 0, offsets=offsets)
            for worker in workers:
                result = subprocess.run([sys.executable, '-', '2001', '2', str(source)],
                    input=embedded(worker, 'PY_DAILY_COVERAGE'), capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
        source = self.daily_field('complete.nc', 2001, 2, 28)
        result = subprocess.run([sys.executable, '-', '2001', '2', str(source), str(source)],
            input=embedded(workers[0], 'PY_DAILY_COVERAGE'), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate', result.stderr)
        import netCDF4
        with netCDF4.Dataset(source, 'a') as ds:
            ds.variables['time'].calendar = 'unknown'
        result = subprocess.run([sys.executable, '-', '2001', '2', str(source)],
            input=embedded(workers[0], 'PY_DAILY_COVERAGE'), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unsupported calendar', result.stderr)
        for paths, message in [([], 'Missing days'), ([str(self.root/'absent.nc')], 'failed')]:
            result = subprocess.run([sys.executable, '-', '2001', '2', *paths],
                input=embedded(workers[0], 'PY_DAILY_COVERAGE'), capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)

    def preparation_shell(self):
        text = (ROOT/'scripts/core/temporal_aggregate_regrid.slurm.sh').read_text()
        helpers = text[text.index('detect_gridtype() {'):text.index('export CDO')]
        # Function harness avoids HPC setup; emulate mapfile -t on macOS Bash 3.
        compat = r'''
if ! type mapfile >/dev/null 2>&1; then
mapfile() {
  local destination="$2" item index=0
  unset "$destination"
  while IFS= read -r item; do
    eval "$destination[$index]=\"\$item\""
    index=$((index + 1))
  done
  return 0
}
fi
'''
        return compat + helpers

    def preparation_env(self):
        import shutil
        (self.root/'parts').mkdir(exist_ok=True)
        grid = self.root/'grid.txt'
        grid.write_text('gridtype = lonlat\nxsize = 2\nysize = 2\nxfirst = 0\nxinc = 2\nyfirst = -1\nyinc = 2\n')
        return dict(self.env, CDO=shutil.which('cdo'), VAR='thetao',
                    PARTS=str(self.root/'parts'), GRIDFILE=str(grid), METHOD='remapbil',
                    DATASET_LABEL='fixture', INPUT_TIMESTEP='daily', FILE_GLOB='*.nc',
                    INROOT=str(self.root/'raw'))

    def test_preparation_real_values_failures_and_output_locks(self):
        import shutil
        env = self.preparation_env()
        source = self.daily_field('source.nc', 2001, 2, 28)
        folder = self.root/'raw/2001/02'
        folder.mkdir(parents=True)
        shutil.copyfile(source, folder/'daily.nc')
        output = self.root/'parts/fixture_thetao_200102.monmean.grid.nc'
        expected = self.root/'expected.nc'
        subprocess.run([env['CDO'], '-s', '-O', 'remapbil,'+env['GRIDFILE'], '-monmean',
                        '-selname,thetao', str(source), str(expected)], check=True, capture_output=True)
        shell = self.preparation_shell() + '\nprocess_month 2001 02'
        result = subprocess.run(['bash', '-c', shell], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        with xr.open_dataset(output) as actual, xr.open_dataset(expected) as reference:
            xr.testing.assert_allclose(actual, reference)
        accepted = output.read_bytes()
        shutil.copyfile(source, folder/'duplicate.nc')
        result = subprocess.run(['bash', '-c', shell], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output.read_bytes(), accepted)
        (folder/'duplicate.nc').unlink()
        lock = Path(str(output)+'.lock')
        lock.mkdir()
        result = subprocess.run(['bash', '-c', shell], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.exists())
        self.assertEqual(output.read_bytes(), accepted)
        lock.rmdir()
        # Hold one actual writer at the remap boundary; a second writer must fail.
        import time
        blocker = self.root/'cdo_block'
        blocker.write_text('#!/bin/bash\nfor arg in "$@"; do case "$arg" in remap*)\n'
            'touch "$READY"\nfor attempt in {1..100}; do\n'
            '[[ -f "$RELEASE" ]] && break\nsleep 0.05\ndone\n'
            '[[ -f "$RELEASE" ]] || exit 88\n;; esac; done\nexec "'+env['CDO']+'" "$@"\n')
        blocker.chmod(0o755)
        ready, release = self.root/'ready', self.root/'release'
        writer = subprocess.Popen(['bash', '-c', shell], env=dict(env,
            CDO=str(blocker), READY=str(ready), RELEASE=str(release)),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and writer.poll() is None and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(ready.exists())
            other = subprocess.run(['bash', '-c', shell], env=env, capture_output=True, text=True)
            self.assertNotEqual(other.returncode, 0)
            self.assertIn('Output locked', other.stderr)
            self.assertEqual(output.read_bytes(), accepted)
        finally:
            release.touch()
            stdout, stderr = writer.communicate(timeout=10)
        self.assertEqual(writer.returncode, 0, stderr)
        accepted = output.read_bytes()
        stub = self.root/'cdo_fail'
        stub.write_text('#!/bin/bash\nfor last; do :; done\n'
            'for arg in "$@"; do case "$arg" in remap*)\n'
            'if [[ "$INVALID" == yes ]]; then printf corrupt > "$last"; exit 0; fi\n'
            'exit 7;; esac; done\nexec "'+env['CDO']+'" "$@"\n')
        stub.chmod(0o755)
        for call, destination in [('process_month 2001 02', output),
                ('process_timeseries_file "$SOURCE"', self.root/'parts/source.grid.nc')]:
            destination.write_bytes(accepted)
            for invalid in ('yes', 'no'):
                result = subprocess.run(['bash', '-c', self.preparation_shell()+'\n'+call],
                    env=dict(env, CDO=str(stub), SOURCE=str(source), INVALID=invalid),
                    capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(destination.read_bytes(), accepted)
        self.assertFalse(list((self.root/'parts').glob('*.lock')))
        self.assertFalse(list((self.root/'parts').glob('*.work.*')))
        # Successful monthly time-series regridding retains the old calculation.
        result = subprocess.run(['bash', '-c', self.preparation_shell()+'\nprocess_timeseries_file "$SOURCE"'],
            env=dict(env, SOURCE=str(source)), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        subprocess.run([env['CDO'], '-s', '-O', 'remapbil,'+env['GRIDFILE'],
                        '-selname,thetao', str(source), str(expected)], check=True, capture_output=True)
        with xr.open_dataset(self.root/'parts/source.grid.nc') as actual, xr.open_dataset(expected) as reference:
            xr.testing.assert_allclose(actual, reference)

    def test_vertical_replacement_and_custom_target(self):
        import shutil
        tool = ROOT/'scripts/core/vertical_interpolate_to_reference.slurm.sh'
        source_dir = self.root/'input'
        source_dir.mkdir()
        source = source_dir/'field.nc'
        field = self.field()
        field.values[:, 0] = 0.
        field.values[:, 1] = 10.
        field.to_netcdf(source)
        target = self.root/'target.txt'
        target.write_text('zaxistype = depth_below_sea\nsize = 1\nname = lev\nunits = m\nlevels = 5\n')
        env = dict(IN_DIR=str(source_dir), OUT_DIR=str(self.root/'vertical'),
                   TARGET_REF_FILE=str(source), TARGET_ZAXIS_FILE=str(target),
                   SHARED_TMP_DIR=str(self.root/'shared'), SOURCE_ZDIM_NAME='lev',
                   SOURCE_UNITS_IN='m', SOURCE_UNITS_OUT='m', MAX_JOBS='2',
                   CDO=shutil.which('cdo'))
        result = self.run_script(tool, **env)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = self.root/'vertical/field_on_reference.nc'
        with xr.open_dataset(output) as data:
            np.testing.assert_allclose(data.thetao.values, 5.)
        accepted = output.read_bytes()
        stub = self.root/'cdo_fail'
        stub.write_text('#!/bin/bash\ncase "$1" in intlevel*) exit 7;; esac\nexec "'+env['CDO']+'" "$@"\n')
        stub.chmod(0o755)
        result = self.run_script(tool, **dict(env, CDO=str(stub)))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('workers failed', result.stderr)
        self.assertEqual(output.read_bytes(), accepted)

    def test_glorys_download_skip_and_postdownload_validation(self):
        text = (ROOT/'scripts/bash/download_GLORYS_parallel.sh').read_text()
        functions = text[text.index('validate_daily_coverage() {'):text.index('# ========= Build per-month tasks')]
        functions += text[text.index('fetch_month() ('):text.index('export -f validate_daily_coverage')]
        source = self.daily_field('daily.nc', 2001, 2, 28)
        folder = self.root/'2001/02'
        folder.mkdir(parents=True)
        client = self.root/'client'
        client.write_text('#!/bin/bash\nprintf called >> "$MARKER"\ncp "$SOURCE" "$DEST/daily.nc"\n')
        client.chmod(0o755)
        env = dict(self.env, CM=str(client), SOURCE=str(source), DEST=str(folder),
                   MARKER=str(self.root/'calls'))
        command = functions+'\nfetch_month dataset regex "$DEST"'
        result = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root/'calls').read_text(), 'called')
        (folder/'daily.nc').unlink()
        source = self.daily_field('incomplete.nc', 2001, 2, 27)
        result = subprocess.run(['bash', '-c', command], env=dict(env, SOURCE=str(source)),
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing days', result.stderr)
        # Duplicate versions stop before invoking the client.
        (folder/'duplicate.nc').write_bytes((folder/'daily.nc').read_bytes())
        calls = (self.root/'calls').read_text()
        result = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate', result.stderr)
        self.assertEqual((self.root/'calls').read_text(), calls)

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
