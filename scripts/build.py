#!/usr/bin/env python3
"""Build a locally signed native macOS WidgetKit app. Optional --install."""
import pathlib, plistlib, shutil, subprocess, sys, os
root = pathlib.Path(__file__).resolve().parents[1]
app = root / 'build/T3 帳號額度 Widget.app'
ext = app / 'Contents/PlugIns/T3Widget.appex'
for folder in (app/'Contents/MacOS', app/'Contents/Resources', ext/'Contents/MacOS'):
    folder.mkdir(parents=True, exist_ok=True)
def run(*args):
    subprocess.run(args, check=True)
run('swiftc', '-target', 'arm64-apple-macos14.0', '-parse-as-library', '-application-extension', str(root/'Sources/Widget.swift'), '-o', str(ext/'Contents/MacOS/T3Widget'), '-framework', 'WidgetKit', '-framework', 'SwiftUI', '-Xlinker', '-e', '-Xlinker', '_NSExtensionMain')
run('swiftc', str(root/'Sources/Host.swift'), '-o', str(app/'Contents/MacOS/T3Host'), '-framework', 'WidgetKit', '-framework', 'AppKit')
shutil.copy2(root/'scripts/reader.py', app/'Contents/Resources/reader.py')
base = dict(CFBundleVersion='7', CFBundleShortVersionString='1.3.0', LSMinimumSystemVersion='14.0', CFBundleSupportedPlatforms=['MacOSX'], DTPlatformName='macosx', DTSDKName='macosx27.0')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(base, CFBundlePackageType='APPL', CFBundleIdentifier='tw.skyhong.t3usage', CFBundleExecutable='T3Host', CFBundleName='T3 帳號額度 Widget', LSUIElement=True)))
(ext/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(base, CFBundlePackageType='XPC!', CFBundleIdentifier='tw.skyhong.t3usage.widget', CFBundleExecutable='T3Widget', CFBundleName='T3 五帳號額度', NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'})))
def sign(bundle, ent):
    run('codesign', '--force', '--sign', '-', '--entitlements', str(root/ent), str(bundle))
sign(ext, 'widget.entitlements'); sign(app, 'host.entitlements')
if '--install' in sys.argv:
    home = pathlib.Path.home(); uid = os.getuid()
    subprocess.run(['launchctl','bootout',f'gui/{uid}/tw.skyhong.t3usage'],capture_output=True)
    subprocess.run(['pkill','-TERM','-x','T3Host'],capture_output=True)
    dest = pathlib.Path('/Applications') / app.name
    # Stop the old extension and unregister both copies before changing versions.
    subprocess.run(['pkill','-TERM','-x','T3Widget'],capture_output=True)
    lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    for bundle in (app, dest):
        subprocess.run(['pluginkit','-r',str(bundle/'Contents/PlugIns/T3Widget.appex')],capture_output=True)
        subprocess.run([lsregister,'-u',str(bundle)],capture_output=True)
    if dest.exists(): shutil.rmtree(dest)
    shutil.copytree(app,dest)
    shared = pathlib.Path('/Users/Shared/T3QuotaWidget'); shared.mkdir(exist_ok=True); shared.chmod(0o700)
    logs = home/'Library/Application Support/T3UsageDesktop'; logs.mkdir(parents=True,exist_ok=True)
    agents = home/'Library/LaunchAgents'; agents.mkdir(parents=True,exist_ok=True)
    agent = agents/'tw.skyhong.t3usage.plist'
    agent.write_bytes(plistlib.dumps({'Label':'tw.skyhong.t3usage','ProgramArguments':[str(dest/'Contents/MacOS/T3Host')],'RunAtLoad':True,'KeepAlive':True,'StandardOutPath':str(logs/'widget.log'),'StandardErrorPath':str(logs/'widget-error.log')}))
    run('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-f',str(dest))
    run('pluginkit','-a',str(dest/'Contents/PlugIns/T3Widget.appex'))
    run('launchctl','bootstrap',f'gui/{uid}',str(agent))
print(app)
