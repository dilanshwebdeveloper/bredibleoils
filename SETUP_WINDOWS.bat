@echo off
REM Run this ONCE from inside the project folder (double-click). Needs Flutter + Node.js installed (see README.md).
echo === 1/6 Creating Android, Windows and Web platform folders ===
call flutter create --platforms=android,windows,web --project-name br_edible_oils_erp .
if exist test\widget_test.dart del test\widget_test.dart
echo === 2/6 Android minimum version fix (needed by Firebase) ===
powershell -Command "foreach($f in 'android\app\build.gradle','android\app\build.gradle.kts'){ if(Test-Path $f){ (Get-Content $f) -replace 'flutter\.minSdkVersion','23' | Set-Content $f } }"
echo === Android permissions (internet + location) ===
powershell -Command "$f='android\app\src\main\AndroidManifest.xml'; $p=''; foreach($n in 'INTERNET','ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION','FOREGROUND_SERVICE','FOREGROUND_SERVICE_LOCATION'){ $p += '<uses-permission android:name=''android.permission.' + $n + '''/>' }; $c=Get-Content $f -Raw; if($c -notmatch 'ACCESS_FINE_LOCATION'){ $c=$c -replace '<application', ($p + '<application'); Set-Content $f $c }"
echo === 3/6 Downloading packages ===
call flutter pub get
echo === App icon + name ===
call dart run flutter_launcher_icons -f icons_android_web.yaml
call dart run flutter_launcher_icons -f icons_windows.yaml
python tools\brand.py
echo === 4/6 Installing Firebase tools ===
call npm install -g firebase-tools
call dart pub global activate flutterfire_cli
echo === 5/6 Log in to Firebase (a browser window opens) ===
call firebase login
echo === 6/6 Connect this app to your Firebase project ===
call flutterfire configure --project=br-industriestonk --platforms=android,windows,web --yes
echo.
echo DONE. Now follow README.md "Step 3" (turn on Email login + Firestore + paste rules), then run:
echo    flutter run -d windows
pause
