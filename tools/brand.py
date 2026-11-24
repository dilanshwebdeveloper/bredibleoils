# 1) Sets the app name to "B.R. Edible Oils".
# 2) Windows: stops compiler warnings from being treated as errors (firebase_auth plugin needs this).
# 3) Android: makes every plugin compile against Android 36 (file_picker etc. need it).
import os, re

NAME = 'B.R. Edible Oils'

def edit(path, fn):
    if os.path.exists(path):
        s = open(path, encoding='utf-8').read()
        n = fn(s)
        if n != s:
            open(path, 'w', encoding='utf-8').write(n)
            print('patched', path)

edit('android/app/src/main/AndroidManifest.xml',
     lambda s: re.sub(r'android:label="[^"]*"', 'android:label="%s"' % NAME, s, count=1))
edit('windows/runner/main.cpp',
     lambda s: re.sub(r'window\.Create\(L"[^"]*"', 'window.Create(L"%s"' % NAME, s, count=1))
edit('web/index.html',
     lambda s: re.sub(r'(apple-mobile-web-app-title" content=")[^"]*', r'\g<1>' + NAME,
                      re.sub(r'<title>[^<]*</title>', '<title>%s</title>' % NAME, s)))
edit('web/manifest.json',
     lambda s: re.sub(r'"short_name":\s*"[^"]*"', '"short_name": "%s"' % NAME,
                      re.sub(r'"name":\s*"[^"]*"', '"name": "B.R. Edible Oils ERP"', s, count=1)))

# Windows: remove "treat warnings as errors"
edit('windows/CMakeLists.txt', lambda s: s.replace('/WX', ''))

# Android: Gradle init script (runs for every project in the build)
if os.path.isdir('android'):
    init = os.path.expanduser('~/.gradle/init.d/force-compile-sdk.gradle')
    os.makedirs(os.path.dirname(init), exist_ok=True)
    open(init, 'w').write("""allprojects {
    afterEvaluate { p ->
        def a = p.extensions.findByName('android')
        if (a != null) {
            try { a.compileSdk = 36 } catch (Throwable t1) {
                try { a.compileSdkVersion(36) } catch (Throwable t2) { }
            }
        }
    }
}
""")
    print('wrote', init)

# Android: use the package name registered in Firebase (matches google-services.json)
for gf in ('android/app/build.gradle.kts', 'android/app/build.gradle'):
    edit(gf, lambda s: re.sub(r'applicationId\s*=?\s*"[^"]*"', 'applicationId = "com.bredible_erp"', s, count=1))
