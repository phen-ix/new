# hyperos/ — DOOM Kernel × HyperOS Port Profile (miatoll)

هذا المجلد يحتوي إطار عمل البروفايل الخاص بالروم الهدف
`HyperOS_Miatoll_20261107_@iputobject_OS3.0.3.0.VLCCNXM_15.zip`
(sha256 `783ad4f7be1330483aedab39344921a1ca9df9d3ca519634352db0430a60264c`)،
وأدوات جمع الأدلة والقياس.

**يبدأ كل شيء من:** [`REPORT.md`](REPORT.md) — التقرير الكامل (المراحل A→G).

## الحالة بجملة واحدة

الإطار مُنفَّذ ومُختبَر (في شجرة sysfs وهمية)، لكن **كل قيم الأداء ما زالت
`PENDING`** لأن الروم لم يُفحص (شبكة الساندبوكس تحجب pixeldrain) ولا توجد قياسات
جهاز. تطبيق البروفايل الآن هو **no-op** بحكم التصميم، لا بحكم الإهمال.

## البنية
```
hyperos/
├── REPORT.md                     التقرير الكامل + Git diff + بروتوكول الاختبار
├── README.md                     هذا الملف
├── evidence/EVIDENCE-REQUIRED.md ما هو مطلوب، ولماذا، وأي قرار يفتحه
├── profiles/hyperos-os3.0.3-miatoll.conf   36 بندًا (15 observe-only) مع بوابة دليل
├── tools/
│   ├── doom-profile.sh           --audit | --apply | --revert | --status | --diff
│   ├── rom-evidence.sh           استخراج أدلة الروم على جهاز PC
│   ├── device-metrics.sh         قياسات الجهاز (static/launch/ui/idle/soak)
│   ├── compare.py                مقارنة قبل/بعد بقواعد دلالة صريحة
│   └── sync-module.sh            مزامنة الأدوات إلى موديول KSU
└── ksu-module/miatoll-hyperos-profile/   موديول اختياري (post-fs-data + service)
```

## الاستخدام السريع

```bash
# 1) لقطة read-only لحالة كل العقد على الجهاز (لا كتابة)
adb shell su -c 'sh /data/adb/modules/miatoll_hyperos_profile/bin/doom-profile.sh --audit'

# 2) فحص الروم على الـ PC
./hyperos/tools/rom-evidence.sh --zip HyperOS_Miatoll_..._15.zip --out ./rom-dossier --deep

# 3) قياسات الجهاز (قبل/بعد)
./hyperos/tools/device-metrics.sh baseline --pkg com.miui.home --scenario all --runs 7
python3 hyperos/tools/compare.py metrics/baseline/summary.csv metrics/after/summary.csv --md out.md
```

## قواعد ثابتة في هذا التصميم

1. **لا قيمة بلا دليل.** البند يبقى `PENDING` حتى يوجد دليل من الروم أو النواة أو
   قياس جهاز. `--apply` يتجاهل `PENDING` إلا بتمرير `--allow-pending` صراحةً.
2. **الرجوع مضمون.** كل كتابة تُسبق backup في `/data/adb/doom-profile/` وتُتبع
   بتحقق read-back؛ فشل التحقق ⇒ إرجاع فوري.
3. **لا يُلمس thermal.** لا trips ولا cooling devices ولا `max_pwrlevel`.
4. **لا تعديل على إعدادات كل الرومات.** البروفايل ملف منفصل، و`defconfig`
   الأساسي لم يُعدّل.
5. **لا وهم في النتائج.** `compare.py` يرفض إعلان تحسّن عندما n<5 أو الفرق <3%.

## ما لم يُختبر

- أي شيء على جهاز حقيقي (لا يوجد جهاز في هذه البيئة).
- محتوى الروم (لم يُنزَّل).
- بناء النواة بهذا الـ fragment (لم يُبنَ هنا).

التفاصيل والمخاطر: [`REPORT.md`](REPORT.md) §6.3 و§9.
مخرجات الاختبارات الحقيقية: [`evidence/validation-log.txt`](evidence/validation-log.txt).
