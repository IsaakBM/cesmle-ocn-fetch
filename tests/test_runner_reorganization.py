#!/usr/bin/env python3
"""Compare experimental runners with an immutable main revision; never submit jobs."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = json.loads((ROOT / 'tests/fixtures/reorganization_reference.json').read_text())


class RunnerReorganizationTests(unittest.TestCase):
    def test_defaults_and_submission_blocks_are_unchanged(self):
        for name in REFERENCE['allowed_modified_paths']:
            before = subprocess.check_output(
                ['git', 'show', REFERENCE['reference_commit'] + ':' + name], cwd=ROOT, text=True)
            after = (ROOT / name).read_text()
            with self.subTest(runner=name):
                self.assertEqual(before.split('contains_word() {')[0],
                                 after.split('# shellcheck source=')[0])
                self.assertEqual(before[before.index('echo "Submitting curated'):],
                                 after[after.index('echo "Submitting curated'):])

    def test_original_files_outside_four_runners_are_unchanged(self):
        allowed = set(REFERENCE['allowed_modified_paths'])
        for name, expected in REFERENCE['sha256'].items():
            if name not in allowed:
                with self.subTest(path=name):
                    self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), expected)

    def test_runner_behavior_matches_pinned_main(self):
        bash_major = int(subprocess.check_output(
            ['bash', '-c', 'echo "${BASH_VERSINFO[0]}"'], text=True))
        if bash_major < 4:
            self.skipTest('Runner equivalence requires production Bash 4+ on PATH')
        with tempfile.TemporaryDirectory(prefix='ocean runner comparison ') as directory:
            temp = Path(directory)
            original = temp / 'reference'
            bindir = temp / 'bin'
            bindir.mkdir()
            capture = temp / 'submissions.jsonl'
            # Intercept setup and scheduling only; real find/sort/path handling run.
            (bindir / 'mkdir').write_text('#!/bin/bash\nexit 0\n')
            (bindir / 'sbatch').write_text(
                '#!/usr/bin/env python3\nimport json, os, sys\n'
                'with open(os.environ["CAPTURE"], "a") as f:\n'
                '    f.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                'if os.environ.get("FAIL_SUBMISSION") == "yes":\n'
                '    print("fixture submission failure", file=sys.stderr)\n'
                '    sys.exit(23)\n'
                'print("12345")\n')
            for path in bindir.iterdir():
                path.chmod(0o755)
            source = temp / 'products with spaces'
            for relative in (
                'baseline/thetao', 'baseline/chl', 'baseline/tmp_ignore',
                'future/Model-A/r1i1p1f1/ssp126', 'future/Model-A/r1i1p1f1/ssp585',
                'future/Model-B/r2i1p1f1/ssp245', 'future/Empty-Model',
                'future/cesm_f09_g16/001/rcp85', 'future/legacy_downscaled_rcp85',
                'future/ensemble/model_mean/ssp126', 'future/ensemble/model_sd/ssp585',
                'future/ensemble/model_count/ssp245', 'future/tmp_ignore',
            ):
                (source / relative).mkdir(parents=True)
            empty = temp / 'empty'
            empty.mkdir()
            empty_ensemble = temp / 'empty ensemble'
            (empty_ensemble / 'future/ensemble').mkdir(parents=True)
            cases = {
                'defaults': {},
                'no_baseline': {'INCLUDE_BASELINE': 'no'},
                'selected_models': {'FUTURE_MODELS': 'Model-B ensemble'},
                'exclusion_wins': {'FUTURE_MODELS': 'Model-A', 'EXCLUDE_FUTURE_MODELS': 'Model-A'},
                'clear_exclusions': {'EXCLUDE_FUTURE_MODELS': ''},
                'replace_exclusions': {'EXCLUDE_FUTURE_MODELS': 'Model-A ensemble'},
                'unsplit_ensemble': {'SPLIT_ENSEMBLE_STATS': 'no'},
                'split_scenarios': {'SPLIT_FUTURE_SCENARIOS': 'yes'},
                'split_unsplit_ensemble': {'SPLIT_FUTURE_SCENARIOS': 'yes', 'SPLIT_ENSEMBLE_STATS': 'no'},
                'overrides': {'OVERWRITE': 'yes', 'RESOLUTIONS': '0p05 0p25', 'EXCLUDE_NODES': 'node-a,node-b'},
                'scheduler_exclude_fallback': {'SBATCH_EXCLUDE': 'node-c'},
                'empty_selection': {'FUTURE_MODELS': 'absent', 'INCLUDE_BASELINE': 'no'},
                'missing_source': {'SOURCE_ROOT': str(temp / 'missing')},
                'empty_source': {'SOURCE_ROOT': str(empty)},
                'empty_ensemble_fallback': {'SOURCE_ROOT': str(empty_ensemble), 'SPLIT_FUTURE_SCENARIOS': 'yes'},
                'submission_failure': {'FAIL_SUBMISSION': 'yes'},
            }
            env = dict(os.environ)
            for name in ('SOURCE_ROOT', 'TARGET_ROOT', 'OVERWRITE', 'RESOLUTIONS',
                         'FUTURE_MODELS', 'EXCLUDE_FUTURE_MODELS', 'EXCLUDE_NODES',
                         'SBATCH_EXCLUDE', 'INCLUDE_BASELINE', 'SPLIT_ENSEMBLE_STATS',
                         'SPLIT_FUTURE_SCENARIOS', 'FAIL_SUBMISSION', 'BASH_ENV'):
                env.pop(name, None)
            env.update(PATH=str(bindir) + os.pathsep + env['PATH'],
                       SOURCE_ROOT=str(source), TARGET_ROOT=str(temp / 'output'),
                       CAPTURE=str(capture))

            def run(path, settings):
                capture.unlink(missing_ok=True)
                result = subprocess.run(['bash', str(path)], cwd=temp,
                                        env=dict(env, **settings), capture_output=True, text=True)
                submissions = capture.read_text() if capture.exists() else ''
                def normalize(value):
                    return value.replace(str(original), '<REPO>').replace(str(ROOT), '<REPO>')
                return result.returncode, normalize(result.stdout), normalize(result.stderr), normalize(submissions)

            for name in REFERENCE['allowed_modified_paths']:
                baseline = original / name
                baseline.parent.mkdir(parents=True, exist_ok=True)
                baseline.write_bytes(subprocess.check_output(
                    ['git', 'show', REFERENCE['reference_commit'] + ':' + name], cwd=ROOT))
                fmt = 'parquet' if name.endswith('_parquet.sh') else 'geotiff'
                tool = original / f'scripts/tools/export_ocean_downscaling_products_to_{fmt}.sh'
                tool.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / tool.relative_to(original), tool)
                for label, settings in cases.items():
                    with self.subTest(runner=name, case=label):
                        expected = run(baseline, settings)
                        actual = run(ROOT / name, settings)
                        self.assertEqual(actual, expected)
                        if label in ('missing_source', 'empty_source', 'empty_selection', 'submission_failure'):
                            self.assertNotEqual(expected[0], 0)
                        else:
                            self.assertEqual(expected[0], 0, expected)
                            self.assertTrue(expected[3], 'Expected at least one captured submission')


if __name__ == '__main__':
    unittest.main(verbosity=2)
