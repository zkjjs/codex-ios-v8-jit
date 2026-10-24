import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = set(archive.namelist())
    root = 'Payload/CodexQuota.app/'
    extension = root + 'PlugIns/CodexQuotaWidget.appex/'
    for path in [root + 'CodexQuota', extension + 'CodexQuotaWidget', root + 'Info.plist', extension + 'Info.plist']:
        assert path in names, f'Missing IPA component: {path}'
    app = plistlib.loads(archive.read(root + 'Info.plist'))
    widget = plistlib.loads(archive.read(extension + 'Info.plist'))
    assert app['CFBundleIdentifier'] == 'com.zkjjs.codexquota'
    assert widget['CFBundleIdentifier'].startswith(app['CFBundleIdentifier'] + '.')
    assert app['AppGroupIdentifier'] == widget['AppGroupIdentifier']
    assert widget['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
    print('IPA structure verified: main executable, embedded widget, identifiers and app group.')
