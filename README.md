# أتعلم مع أخي — نسخة Flutter تجريبية

تطبيق عربي تعليمي أصلي باستخدام Flutter. يتضمن 10 دروس تأسيسية تجريبية، صوتًا عربيًا باستخدام محرك تحويل النص إلى كلام في الجهاز، تمارين تفاعلية، حفظ تقدم محلي، وشاشتي طالب ومعلم منفصلتين.

**مهم:** اختيار صنعاء أو عدن والصفوف 1–6 متاح في الواجهة فقط. لم تُدرج بعد الكتب المدرسية المعتمدة أو الدروس الخاصة بكل منهج وصف. لا يوجد ربط بين أجهزة المعلم والطالب في هذه النسخة.

## التشغيل

1. ثبّت Flutter SDK على جهاز تطوير.
2. نفّذ `flutter create . --platforms=android,ios --project-name atalam_ma_akhi` لإنشاء ملفات Android وiOS الأصلية.
3. نفّذ `flutter pub get` ثم `flutter run`.
4. لإنشاء APK: `flutter build apk --release`.

## GitHub Actions

ارفع **محتويات المجلد** إلى مستودع GitHub بفرع `main`، ثم افتح Actions → Build Android APK → Run workflow. بعد نجاح البناء ستجد APK في Artifacts. يتطلب بناء iPhone إعداد macOS وتوقيع Apple Developer؛ لم يُنجز ذلك بعد.

## ملاحظات

- الصوت يعتمد على توافر صوت عربي في الجهاز، وقد تختلف جودته بين الأجهزة.
- حفظ التقدم محليًا على نفس الجهاز.
- هذه نسخة أولية غير مختبرة على أجهزة فعلية.

## Validation and trial delivery
The Android workflow generates native Android files in a temporary project,
keeps the supplied Dart sources intact, runs static analysis and widget tests,
builds a release APK and publishes it as a downloadable GitHub prerelease.
The APK uses Flutter's default development signing; it is for testing only.
Completed lesson IDs are stored individually, with duplicates and invalid IDs
ignored. Existing legacy progress cannot be safely reconstructed and is reset.
Arabic Material localization and Android TTS discovery are configured.

Status: source review completed; Flutter analysis, tests and APK build must
succeed in GitHub Actions before a binary can be considered verified.
The ten sample lessons are shared across the displayed curriculum and grade
choices. These choices do not provide distinct curricula. Teacher reports are
local to this device; there is no remote classroom service or authentication.
