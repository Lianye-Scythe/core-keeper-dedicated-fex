"""Regression checks for the scheduled build decision, with no registry writes."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'image_inputs', Path(__file__).resolve().parents[1] / '.github/scripts/image-inputs.py')
inputs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inputs)


class ImageInputsTests(unittest.TestCase):
    def test_arm_manifest_excludes_other_platforms(self):
        amd, arm = ('sha256:' + c * 64 for c in 'ab')
        manifest = [dict(Descriptor=dict(digest=digest, platform=dict(os='linux', architecture=arch)))
                    for arch, digest in [('amd64', amd), ('arm64', arm)]]
        with patch.object(inputs, 'run', return_value=json.dumps(manifest)):
            self.assertEqual(inputs.arm_reference('ubuntu:26.04'), 'ubuntu@' + arm)

    def test_new_inputs_build_without_pulling_the_baseline(self):
        with patch.object(inputs, 'arm_reference', return_value='image@sha256:old'), \
                patch.object(inputs, 'run', return_value='null') as run:
            self.assertTrue(inputs.build_required('image:fex', 'new', 'mirror=1.2.3.4')[0])
            self.assertEqual(run.call_count, 1)

    def test_same_static_inputs_build_only_if_apt_would_change_packages(self):
        for count in (0, 1):
            plan = f'{count} upgraded, 0 newly installed, 0 to remove and 0 not upgraded.'
            with self.subTest(count=count), \
                    patch.object(inputs, 'arm_reference', return_value='image@sha256:old'), \
                    patch.object(inputs, 'run', side_effect=[json.dumps({inputs.LABEL: 'same'}), plan]) as run:
                self.assertEqual(inputs.build_required('image:fex', 'same', 'mirror=1.2.3.4')[0], bool(count))
                self.assertIn('APT::Update::Error-Mode=any', run.call_args.args[-1])
                self.assertIn('apt-get -s upgrade', run.call_args.args[-1])

    def test_failed_or_unrecognizable_apt_check_cannot_skip_build(self):
        labels = json.dumps({inputs.LABEL: 'same'})
        for result, error in ((subprocess.CalledProcessError(100, 'apt-get'), subprocess.CalledProcessError),
                              ('No plan', ValueError)):
            with self.subTest(result=result), \
                    patch.object(inputs, 'arm_reference', return_value='image@sha256:old'), \
                    patch.object(inputs, 'run', side_effect=[labels, result]), self.assertRaises(error):
                inputs.build_required('image:fex', 'same', 'mirror=1.2.3.4')
