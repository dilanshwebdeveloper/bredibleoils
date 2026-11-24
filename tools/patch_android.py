# Adds the Android permissions the app needs (internet + location) to the generated manifest.
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()
perms = ''.join('<uses-permission android:name="android.permission.%s"/>' % x for x in
                ['INTERNET', 'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION', 'FOREGROUND_SERVICE',
                 'FOREGROUND_SERVICE_LOCATION'])
if 'ACCESS_FINE_LOCATION' not in s:
    s = s.replace('<application', perms + '<application', 1)
    open(p, 'w', encoding='utf-8').write(s)
print('manifest patched')
