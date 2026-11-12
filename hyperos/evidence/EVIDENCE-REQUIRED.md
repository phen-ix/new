# الملفات والبيانات المطلوبة لاستكمال التحليل
# Evidence required to complete the ROM↔kernel analysis

هذا الملف يحدّد بدقة ما هو مطلوب، ولماذا، وما هو القرار الذي يعتمد عليه كل عنصر.
كل عنصر هنا مرتبط بمعرّف في `hyperos/profiles/hyperos-os3.0.3-miatoll.conf`.

This file lists exactly what is missing, why it matters, and which profile
decision each item unblocks. Nothing is assumed: every row states the decision
that stays frozen until the evidence arrives.

---

## 0. لماذا هذا الملف موجود

بيئة العمل الحالية (ساندبوكس) لا تستطيع تنزيل الروم:

```
$ curl -I https://pixeldrain.com/u/ENFhkYH5
curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL
```

الشبكة الخارجية مسموحة فقط لـ `github.com, codeload.github.com, api.github.com,
registry.npmjs.org, pypi.org, files.pythonhosted.org`. تم التأكد من بيانات
الروم الوصفية فقط عبر أداة قراءة صفحات (بدون تنزيل الملف):

| الحقل | القيمة |
|---|---|
| الاسم | `HyperOS_Miatoll_20261107_@iputobject_OS3.0.3.0.VLCCNXM_15.zip` |
| الحجم | 3,551,449,452 بايت (3.55 GB) |
| sha256 | `783ad4f7be1330483aedab39344921a1ca9df9d3ca519634352db0430a60264c` |
| تاريخ الرفع | 2026-11-07 |
| المحتوى | `META-INF` (19.4 MB), `boot.img` (134 MB), `dtbo.img` (1.05 MB), `super.img.zst` (3.52 GB) |

لذلك: **لم يتم فحص محتوى الروم**، وأي رقم في التقرير لا يدّعي ذلك.

---

## 1. الخيارات الثلاثة للحصول على الأدلة

### الخيار A — تشغيل سكربت الاستخراج على جهازك (الأفضل)

```bash
# Linux host, ~10 GB free
./hyperos/tools/rom-evidence.sh --zip HyperOS_Miatoll_20261107_..._15.zip \
                                --out ./rom-dossier --deep
```

يعطي مجلد `rom-dossier/dossier/` يحتوي ملفات نصية صغيرة. أرسل:
`00-archive.txt, 01-boot.txt, 03-dtbo.txt, 04-dynamic-partitions.txt,
05-props.txt, 06-power-thermal.txt, 07-init-services.txt, 08-filesystems.txt`.

السكربت يتحقق أولًا من `sha256` مقابل القيمة أعلاه، ويفشل بأمان إن كان الملف
مختلفًا، ويكتب `UNKNOWN: <السبب>` بدل التخمين عند غياب أداة.

### الخيار B — رفع الملفات نفسها

المطلوب فقط (بدون الصور الكاملة):

1. `boot.img` (134 MB) — لتحليل cmdline وDTB والـ ramdisk.
2. `dtbo.img` (1.05 MB) — **الأهم**: جداول الترددات، thermal trips، core_ctl،
   مستويات GPU الخاصة بالجهاز (لأن شجرة النواة لا تحتوي DTS لـ miatoll إطلاقًا).
3. من `vendor` (بعد فك super): `build.prop`, `vendor/etc/thermal*`, `vendor/etc/perf*`,
   `vendor/bin/hw/*power*`, `vendor/bin/hw/*thermal*`, `vendor/etc/init/*.rc`,
   `vendor/etc/vintf/manifest.xml`, `vendor/etc/fstab.*`, `vendor/etc/powerhint*.json`.

### الخيار C — تشغيل جامع القياسات على الجهاز (يفتح المرحلة D حتى بدون الروم)

```bash
# root required for some nodes
./hyperos/tools/device-metrics.sh baseline --pkg com.miui.home --scenario all --runs 7
```

ثم أرسل `metrics/baseline/summary.csv` + `static.txt` + `frames.txt`.
هذه وحدها تكفي للإجابة عن أسئلة كثيرة: هل الـ PowerHAL يكتب على
`cpu_boost`؟ هل zram مضبوط من الروم؟ هل thermal يخنق الترددات؟

---

## 2. جدول الأدلة ↔ القرارات

| المعرّف | الدليل المطلوب | من أين يُستخرج | القرار الذي يفتحه |
|---|---|---|---|
| E-01 | سلوك schedutil أثناء التمرير: ftrace `cpu_frequency` + `sched_switch` | الجهاز (`perfetto`/ftrace) | `up/down_rate_limit_us` (500/1000 µs) |
| E-02 | هل iowait يخفض التردد فعليًا على هذا الروم | ftrace + PSI io | `iowait_boost_enable` |
| E-03 | حدود الهجرة (upmigrate/downmigrate) الفعلية وسلوك WALT | `/proc/sys/kernel/sched_group_*` + `sched_min_task_util*` | قيم الهجرة |
| E-04 | هل الروم يستخدم `sched_boost` (top-app boost) | service.sh/audit + `dumpsys` | `sched_boost` و schedtune `boost` |
| E-05 | سبب تذبذب الترددات: conservative PL / عدد wakeups المرتفع | ftrace `sched_wakeup` | `sched_conservative_pl`, `sched_many_wakeup_threshold` |
| E-06 | هل المهام الصغيرة تُثبَّت على little cluster | `sched_little_cluster_coloc_fmin_khz` + trace | قيمة colocation |
| E-07 | قيم core_ctl من DT الروم (min/max cpus, thresholds) | `dtbo.img` + `/sys/.../core_ctl/*` | هل hotplug يسبب jank |
| E-08 | تعارض boost: kernel `cpu_boost` مع PowerHAL | `05-props.txt` + `06-power-thermal.txt` + قياس | `input_boost_ms`, `input_boost_freq` |
| E-09 | ضغط الذاكرة: zram size/algorithm, `ro.lmk.*`, PSI | `05-props.txt`, `/proc/pressure`, zram mm_stat | swappiness / extra_free_kbytes |
| E-10 | تكلفة reclaim على dentry/inode | `pgscan*`, `workingset_refault` | `vfs_cache_pressure` |
| E-11 | تفعيل zram من init.rc الروم (الحجم، backend) | `07-init-services.txt` | comp_algorithm (لا نغيّر الحجم) |
| E-12 | الـ I/O scheduler الفعلي على UFS | `/sys/block/*/queue/scheduler` | scheduler / read_ahead_kb |
| E-13 | حوكمة GPU وحدودها الحرارية | `/sys/class/kgsl/...` + dtbo pwrlevels | min/max pwrlevel |
| E-14 | نوع filesystem لأقسام super (erofs/ext4/f2fs) | `08-filesystems.txt` | تفعيل `CONFIG_EROFS_FS` |
| E-15 | وجود HAL/خدمات تتوقع واجهات غير موجودة في النواة | `06/07-*.txt` | أي patch توافق (لا أداء) |

---

## 3. ما سيحدث بعد وصول الأدلة

1. تُحدَّث القيم في `hyperos/profiles/hyperos-os3.0.3-miatoll.conf` من `PENDING`
   إلى `READY` **فقط** للبنود التي يثبتها الدليل، ويُذكر معرّف الدليل في العمود الأخير.
2. `--apply` يصبح فعّالًا لتلك البنود، مع backup/revert مضمون.
3. تُشغَّل دورة القياس (baseline → after) عبر `device-metrics.sh` + `compare.py`،
   ويُقبل التغيير فقط إذا تجاوز حدّ الدلالة المعلن (≥3% و n≥5) دون تراجع حراري
   أو في استهلاك الخمول.

لا توجد أي خطوة في هذا المسار تعتمد على "tweaks جاهزة" أو على تجارب أجهزة أخرى.
