"""Verify installed Fastlane options with stubbed Apple calls; never uploads."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'lib/app/services/ios_release_fastfile.dart').read_text().split(
    "const iosReleaseFastfile = r'''", 1)[1].split("''';", 1)[0]
stub = ROOT / 'test/fixtures/ios_release_fastlane_contract.rb'
fastlane = shutil.which('fastlane')
if not fastlane:
    raise SystemExit('Install Fastlane to run the optional contract smoke test')
with tempfile.TemporaryDirectory(prefix='amc_contract_') as root:
    folder = Path(root) / 'fastlane'
    folder.mkdir()
    (folder / 'Fastfile').write_text('require ' + json.dumps(str(stub)) + '\n' + source)
    (Path(root) / 'key.p8').write_text('fixture')
    (Path(root) / 'app.ipa').write_text('fixture')
    cases = [(action, '') for action in ['query', 'upload', 'distribute', 'draft', 'submit', 'release']]
    cases.append(('query', 'many'))
    cases.extend([('draft', 'automatic'), ('draft', 'explicit-fr'),
                  ('draft', 'no-notes'), ('draft', 'first-release'), ('draft', 'legacy')])
    for action, variant in cases:
        data = dict(action=action, key_id='fixture-key', issuer_id='fixture-issuer',
                    key_filepath=str(Path(root) / 'key.p8'), bundle_id='com.example.demo',
                    version='1.2.3', build_number=12, ipa=str(Path(root) / 'app.ipa'),
                    groups=['Internal'], notes='Notes', locale='vi-VN',
                    use_app_store_locale=False,
                    external_testing=False, automatic_release=False)
        if variant == 'automatic': data['use_app_store_locale'] = True
        if variant == 'explicit-fr': data['locale'] = 'fr-FR'
        if variant == 'no-notes': data['notes'] = ''
        if variant == 'legacy':
            data['locale'] = 'en-US'
            del data['use_app_store_locale']
        inp = Path(root) / 'input.json'
        inp.write_text(json.dumps(data))
        result = subprocess.run(
            [fastlane, 'ios', 'amc_ios', 'input:' + str(inp)], cwd=root,
            env=dict(os.environ, CI='1', FASTLANE_SKIP_UPDATE_CHECK='1',
                     FASTLANE_OPT_OUT_USAGE='1', AMC_TEST_ACTION=action,
                     AMC_TEST_VERSIONS=variant),
            capture_output=True, text=True, timeout=30)
        if result.returncode:
            print(result.stdout[-5000:], result.stderr[-2000:])
            raise SystemExit(result.returncode)
        calls = json.loads(next(line.split('AMC_CONTRACT:', 1)[1]
                               for line in result.stdout.splitlines()
                               if line.startswith('AMC_CONTRACT:')))
        marker = re.search(r'AMC_IOS_RESULT:(\{[^\r\n]*\})', result.stdout)
        assert marker, 'Fastlane did not return AMC_IOS_RESULT'
        store = json.loads(marker.group(1))
        if variant == 'many':
            assert len(store['versions']) == 21
            assert store['versions'][0]['version'] == '2.22.0'
            assert store['versions'][-1]['version'] == '1.2.3'
            assert store['versions'][-1]['buildNumber'] == '12'
        elif variant == 'first-release':
            assert [v['version'] for v in store['versions']] == ['1.2.3']
        else:
            assert [v['version'] for v in store['versions']] == ['2.0.0', '1.2.3', '0.9.0']
        if action in ['draft', 'submit']:
            appstore = next(call for call in calls if call['action'] == 'appstore')
            assert appstore['review'] is (action == 'submit')
            assert appstore['binary'] is True and appstore['skip_metadata'] is True
            assert appstore['release_notes'] is None
            assert appstore['automatic'] is False
            assert next(call for call in calls if call['action'] == 'select_build')['build_id'] == 'build-12'
            notes = [call for call in calls if call['action'] == 'notes']
            if variant in ['no-notes', 'first-release']:
                assert notes == []
            else:
                assert len(notes) == 1
                assert notes[0]['locale'] == ('fr-FR' if variant in ['automatic', 'explicit-fr'] else 'vi')
                assert notes[0]['attributes'] == {'whats_new': 'Notes'}
        if action == 'distribute':
            assert calls[0]['distribute_only'] is True
            assert calls[0]['build'] == '12' and calls[0]['version'] == '1.2.3'
        if action == 'upload':
            assert calls[0]['distribute_only'] is False
        if action == 'release':
            assert calls == [{'action': 'release'}]
        print(action, variant or '', 'passed')

    # Selecting an unconfigured language must not create any localization.
    data.update(action='draft', locale='en-US', use_app_store_locale=False, notes='Notes')
    inp.write_text(json.dumps(data))
    result = subprocess.run(
        [fastlane, 'ios', 'amc_ios', 'input:' + str(inp)], cwd=root,
        env=dict(os.environ, CI='1', FASTLANE_SKIP_UPDATE_CHECK='1',
                 FASTLANE_OPT_OUT_USAGE='1', AMC_TEST_ACTION='draft'),
        capture_output=True, text=True, timeout=30)
    assert result.returncode != 0
    assert 'Locale en-US is not configured' in result.stdout + result.stderr
    print('unconfigured locale rejected: passed')

    # Negative control: reintroducing the original request must fail against
    # the strict endpoint stub, rather than silently passing a permissive mock.
    bad_source = source.replace(
        "app.get_app_store_versions(filter: { platform: 'IOS' }, includes: 'build')",
        "app.get_app_store_versions(filter: { platform: 'IOS' }, includes: 'build', sort: '-createdDate')")
    assert bad_source != source
    (folder / 'Fastfile').write_text('require ' + json.dumps(str(stub)) + '\n' + bad_source)
    data.update(action='query')
    inp.write_text(json.dumps(data))
    result = subprocess.run(
        [fastlane, 'ios', 'amc_ios', 'input:' + str(inp)], cwd=root,
        env=dict(os.environ, CI='1', FASTLANE_SKIP_UPDATE_CHECK='1',
                 FASTLANE_OPT_OUT_USAGE='1', AMC_TEST_ACTION='query'),
        capture_output=True, text=True, timeout=30)
    assert result.returncode != 0
    assert 'rejects sort' in result.stdout + result.stderr
    print('unsupported sort rejected: passed')
