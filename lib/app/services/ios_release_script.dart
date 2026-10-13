/// Portable terminal entry point. Uses the very same Fastfile as AMC.
const iosReleasePython = r'''
#!/usr/bin/env python3
import argparse, fcntl, hashlib, json, os, pathlib, plistlib, shutil, subprocess, sys, tempfile, zipfile

HERE = pathlib.Path(__file__).resolve().parent
CONFIG = json.loads((HERE / 'config.json').read_text())
SETTINGS = CONFIG['settings']
WORK = HERE / 'runs'

def command(args, cwd=None, env=None):
    result = subprocess.run(args, cwd=cwd or CONFIG['project_path'], env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end='')
    if result.returncode:
        raise RuntimeError('%s exited with %s' % (args[0], result.returncode))
    return result.stdout

def apple(action, run):
    # Credentials are supplied at runtime and never exported by AMC.
    required = ['AMC_KEY_ID', 'AMC_ISSUER_ID', 'AMC_KEY_FILE']
    for key in required:
        if not os.environ.get(key):
            raise RuntimeError('Missing environment variable ' + key)
    with tempfile.TemporaryDirectory(prefix='amc_ios_key_') as temp:
        temp = pathlib.Path(temp)
        (temp / 'fastlane').mkdir()
        shutil.copy(HERE / 'fastlane' / 'Fastfile', temp / 'fastlane' / 'Fastfile')
        data = dict(action=action, key_id=os.environ['AMC_KEY_ID'], issuer_id=os.environ['AMC_ISSUER_ID'],
                    key_filepath=str(pathlib.Path(os.environ['AMC_KEY_FILE']).expanduser().resolve()),
                    bundle_id=CONFIG['bundle_id'], version=run['version'], build_number=run['build_number'],
                    ipa=run.get('ipa'), groups=SETTINGS['groups'], notes=SETTINGS['notes'],
                    locale=SETTINGS.get('locale', 'vi-VN') if 'useAppStoreLocale' in SETTINGS or SETTINGS.get('locale') not in (None, '', 'en-US') else 'vi-VN',
                    use_app_store_locale=SETTINGS.get('useAppStoreLocale', False),
                    external_testing=SETTINGS['externalTesting'],
                    automatic_release=SETTINGS['automaticRelease'])
        file = temp / 'input.json'
        file.write_text(json.dumps(data))
        file.chmod(0o600)
        project = pathlib.Path(CONFIG['project_path'])
        gemfile = next((file for file in [project/'ios/fastlane/Gemfile', project/'ios/Gemfile'] if file.exists()), None)
        executable = ['bundle', 'exec', 'fastlane'] if gemfile else ['fastlane']
        env = dict(os.environ, FASTLANE_SKIP_UPDATE_CHECK='1', FASTLANE_OPT_OUT_USAGE='1', CI='1')
        if gemfile: env['BUNDLE_GEMFILE'] = str(gemfile)
        output = command(executable + ['ios', 'amc_ios', 'input:' + str(file)], str(temp), env)
        import re
        markers = re.findall(r'AMC_IOS_RESULT:(\{[^\r\n]*\})', output)
        if not markers: raise RuntimeError('Missing AMC_IOS_RESULT')
        return json.loads(markers[-1])

def digest(file):
    h = hashlib.sha256()
    with open(file, 'rb') as source:
        for chunk in iter(lambda: source.read(1024*1024), b''): h.update(chunk)
    return h.hexdigest()

def source_digest():
    project = pathlib.Path(CONFIG['project_path'])
    result = subprocess.run(['git','ls-files','-z','--cached','--others','--exclude-standard'], cwd=project, capture_output=True)
    if result.returncode: raise RuntimeError('Cannot inspect release source')
    h = hashlib.sha256()
    for name in sorted(set(result.stdout.decode().split('\0')) - {''}):
        path = project/name
        value = os.readlink(path) if path.is_symlink() else digest(path) if path.is_file() else 'missing'
        h.update(json.dumps([name, value]).encode())
    return h.hexdigest()

def build_settings(output):
    import re
    for match in re.finditer(r'\[\s*\{', output):
        try:
            value, _ = json.JSONDecoder().raw_decode(output[match.start():])
            if value and all(isinstance(entry, dict) and isinstance(entry.get('buildSettings'), dict) for entry in value):
                return value
        except ValueError:
            pass
    raise RuntimeError('Xcode did not return build settings JSON')

def save(path, run):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(run, indent=2))
    tmp.replace(path)

def build_match(state, run):
    return next((b for b in state['builds'] if b['version'] == run['version'] and str(b['number']) == str(run['build_number'])), None)

def main():
    parser = argparse.ArgumentParser(description='AMC iOS release. Explicit steps; no automatic review or publication.')
    parser.add_argument('action', choices=['prepare','build','upload','status','distribute','draft','submit','release'])
    parser.add_argument('--version', help='Marketing version, required for prepare')
    parser.add_argument('--build-number', type=int, help='Existing TestFlight build to reuse during prepare')
    parser.add_argument('--run', help='Run ID printed by prepare')
    parser.add_argument('--confirm', action='store_true', help='Confirm distribution, review or public release')
    parser.add_argument('--retry-verified', action='store_true', help='Upload again only after checking Apple')
    args = parser.parse_args()
    if sys.platform != 'darwin': raise RuntimeError('iOS release requires macOS')
    if args.action in ['submit','release','distribute'] and not args.confirm:
        raise RuntimeError('Review/distribution/release requires --confirm after checking the run manifest')
    locks = pathlib.Path.home()/'.amc'/'ios_locks'
    locks.mkdir(parents=True, exist_ok=True)
    lock_id = hashlib.sha256((SETTINGS['teamId']+'\n'+CONFIG['bundle_id']).encode()).hexdigest()
    with open(locks/(lock_id+'.lock'), 'a+') as lock:
        fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        WORK.mkdir(exist_ok=True)
        if args.action == 'prepare':
            import datetime, re
            if not args.version or not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
                raise RuntimeError('Specify --version 1.2.3')
            if not SETTINGS['teamId']: raise RuntimeError('Configure settings.teamId in config.json')
            run = dict(version=args.version, build_number=args.build_number or 0, upload_attempted=bool(args.build_number),
                       bundle_id=CONFIG['bundle_id'], team_id=SETTINGS['teamId'],
                       commit=command(['git','rev-parse','HEAD']).strip(),
                       dirty=bool(command(['git','status','--porcelain']).strip()), status='prepared', config=CONFIG)
            state = apple('query', run)
            if args.build_number:
                selected = build_match(state, run)
                if not selected or selected['state'] != 'VALID' or selected['expired']:
                    raise RuntimeError('Existing build is not ready')
                run['status'] = 'ready'
            else:
                command([SETTINGS['flutterExecutable'] or 'flutter', 'pub', 'get'])
                source = (pathlib.Path(CONFIG['project_path'])/'pubspec.yaml').read_text()
                local = re.search(r'^\s*version:\s*[^+\s]+\+(\d+)\s*$', source, re.M)
                if not local: raise RuntimeError('pubspec.yaml needs name+build version')
                run['build_number'] = max(int(local.group(1)), max([int(b['number']) for b in state['builds']] or [0])+1)
                run['source_hash'] = source_digest()
            run_id = datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')
            folder = WORK/run_id
            folder.mkdir()
            path = folder/'manifest.json'
            save(path, run)
            print('Run:', run_id, 'Version/build:', run['version'], run['build_number'])
            return
        if not args.run or not args.run.isdigit(): raise RuntimeError('Specify --run <run ID>')
        folder = WORK/args.run
        path = folder/'manifest.json'
        run = json.loads(path.read_text())
        if run.get('config') != CONFIG:
            raise RuntimeError('config.json changed since the preview; prepare again before continuing')
        try:
            if args.action == 'build':
                if run['upload_attempted']: raise RuntimeError('Prepare a new release before rebuilding')
                if command(['git','rev-parse','HEAD']).strip() != run['commit']: raise RuntimeError('Commit changed; prepare again')
                command(['xcodebuild','-version'])
                flutter = SETTINGS['flutterExecutable'] or 'flutter'
                command([flutter,'pub','get'])
                if source_digest() != run.get('source_hash'): raise RuntimeError('Source changed; prepare again')
                identities = command(['security','find-identity','-v','-p','codesigning'])
                if '"Apple Distribution:' not in identities and '"iPhone Distribution:' not in identities:
                    raise RuntimeError('Distribution certificate/private key is missing')
                raw = command(['xcodebuild','-workspace','ios/Runner.xcworkspace','-scheme',SETTINGS['scheme'],
                               '-configuration',SETTINGS['configuration'],'-showBuildSettings','-json'])
                settings = build_settings(raw)
                apps = [s['buildSettings'] for s in settings if s['buildSettings'].get('PRODUCT_TYPE') == 'com.apple.product-type.application']
                if len(apps) != 1 or apps[0]['PRODUCT_BUNDLE_IDENTIFIER'] != CONFIG['bundle_id'] or apps[0]['DEVELOPMENT_TEAM'] != SETTINGS['teamId']:
                    raise RuntimeError('Scheme Bundle ID/Team ID mismatch')
                export = pathlib.Path(SETTINGS['exportOptionsPath']) if SETTINGS['exportOptionsPath'] else folder/'ExportOptions.plist'
                if SETTINGS['exportOptionsPath'] and not export.is_absolute(): export = pathlib.Path(CONFIG['project_path'])/export
                if not SETTINGS['exportOptionsPath']:
                    export.write_bytes(plistlib.dumps(dict(method='app-store-connect', teamID=SETTINGS['teamId'], signingStyle='automatic')))
                import time
                started = time.time()-2
                command([flutter,'build','ipa','--release','--build-name='+run['version'],'--build-number='+str(run['build_number']),
                         '--target='+SETTINGS['entrypoint'],'--export-options-plist='+str(export)] +
                        (['--flavor='+SETTINGS['flavor']] if SETTINGS['flavor'] else []) + SETTINGS['extraBuildArguments'])
                if source_digest() != run.get('source_hash'): raise RuntimeError('Source changed during build')
                ipas = [f for f in (pathlib.Path(CONFIG['project_path'])/'build/ios/ipa').glob('*.ipa') if f.stat().st_mtime >= started]
                if len(ipas) != 1: raise RuntimeError('Expected exactly one new IPA')
                import re
                with zipfile.ZipFile(ipas[0]) as archive:
                    names = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
                    if len(names) != 1: raise RuntimeError('Invalid IPA')
                    info = plistlib.loads(archive.read(names[0]))
                if info['CFBundleIdentifier'] != CONFIG['bundle_id'] or info['CFBundleShortVersionString'] != run['version'] or str(info['CFBundleVersion']) != str(run['build_number']):
                    raise RuntimeError('IPA identity/version mismatch')
                shutil.copy(ipas[0], folder/'app.ipa')
                run.update(ipa=str(folder/'app.ipa'), ipa_hash=digest(folder/'app.ipa'), status='built')
                archives = list((pathlib.Path(CONFIG['project_path'])/'build/ios/archive').glob('*.xcarchive'))
                if len(archives) == 1:
                    destination = folder/'app.xcarchive'
                    if destination.exists(): shutil.rmtree(destination)
                    shutil.copytree(archives[0], destination, symlinks=True)
                    run['archive'] = str(destination)
            elif args.action == 'upload':
                if digest(run['ipa']) != run['ipa_hash']: raise RuntimeError('IPA hash changed')
                state = apple('query', run)
                if build_match(state, run):
                    if not run['upload_attempted']: raise RuntimeError('Another release used this build number; prepare a new run')
                    run.update(status='processing', store=state)
                elif run['upload_attempted'] and not args.retry_verified:
                    raise RuntimeError('Upload already attempted; refresh Apple before --retry-verified')
                else:
                    run.update(upload_attempted=True, status='verificationRequired')
                    save(path, run)
                    run['store'] = apple('upload', run)
                    run['status'] = 'processing'
            elif args.action == 'status':
                state = apple('query', run)
                selected = build_match(state, run)
                run.update(store=state, status=selected['state'] if selected else 'verificationRequired')
            else:
                run['store'] = apple(args.action, run)
                run['status'] = args.action
            save(path, run)
            print('Status:', run['status'])
        except BaseException:
            save(path, run)
            raise

if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
''';
