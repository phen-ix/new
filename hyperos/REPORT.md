# DOOM Kernel × HyperOS Port — تحليل التوافق وتقرير الخطة
### الجهاز: Redmi Note 9 Pro (miatoll, atoll/SM7125) · النواة: Linux 4.14-openela · الروم الهدف: `HyperOS_Miatoll_20261107_@iputobject_OS3.0.3.0.VLCCNXM_15.zip`

**تاريخ التقرير:** 2026-11-12 · **الفرع:** `arena/ec72f3eb-new` · **الأساس:** `7bc580b93`

---

## 0. ملخص تنفيذي

| المرحلة | الحالة | ما تم فعليًا |
|---|---|---|
| **A — ROM Inspection** | ⛔ **محجوبة** | تعذّر تنزيل الروم (قيود شبكة الساندبوكس). تم التأكد من البيانات الوصفية والـ sha256 وفهرس الأرشيف فقط. أُنتج سكربت استخراج جاهز للتنفيذ على جهازك (`hyperos/tools/rom-evidence.sh`). |
| **B — Kernel Inspection** | ✅ **مكتملة** | فحص كامل للمصدر: الإصدار، الالتزامات، ما هو موجود فعلًا وما هو **غير موجود** (KernelSU وBBRv3 **ليسا في هذه الشجرة**)، المُجدوِل، CPUFreq، GPU، Thermal، الذاكرة، I/O، الشبكة. كل نتيجة مع مرجع `ملف:سطر`. |
| **C — Compatibility Audit** | 🟡 **جزئية** | مصفوفة كاملة بين واجهات النواة وما يحتاجه userspace حديث + فجوات مثبتة من المصدر (EROFS، TMPFS_XATTR، غياب واجهة `thermal_message`، اعتماد DT على الروم). البند المتبقي: ما يطلبه الروم تحديدًا. |
| **D — Performance Diagnosis** | 🟡 **مُجهَّزة** | 7 فرضيات قابلة للإثبات/النفي، لكل واحدة قياس يثبتها وأداة تقيسها. **لم تُنفَّذ أي قياسات** (لا يوجد جهاز في هذه البيئة). |
| **E — Optimization Plan** | ✅ **الجدول جاهز** | 36 بندًا مع القيمة الحالية المثبتة من المصدر، والهدف، والحدود، وبوابة الدليل. **جميع الأهداف `PENDING`** لأن قاعدة المشروع تمنع تغيير قيمة بلا دليل. |
| **F — Implementation** | ✅ **البنية التحتية مُنفَّذة** | محرّك بروفايل قابل للتفعيل/الإلغاء مع backup/revert وتحقق read-back، ملف بروفايل، موديول KSU، وfragment توافق منفصل. **صفر تغييرات سلوكية في النواة** — بقرار مقصود ومُعلَّل. |
| **G — Validation** | 🟡 **بروتوكول + أدوات** | منصة قياس (launch/UI jank/idle/soak) + أداة مقارنة ترفض الاستنتاج تحت حدّ الدلالة. **لم تُنفَّذ أي اختبارات على جهاز.** |

> **أهم ثلاث نتائج يجب أن تعرفها قبل أي شيء آخر:**
>
> 1. **الشجرة التي بين يدي ليست نواة DOOM كما وُصفت.** لا يوجد KernelSU ولا BBRv3 ولا حتى `CONFIG_TCP_CONG_BBR` في إعدادات miatoll، والإصدار `4.14.356-openela-rc1` وليس `.357`. الشجرة تحتوي التزامًا واحدًا فقط (KCAL). راجع §2.2 — هذا يعني أن كل بناء من هذه الشجرة لن يحمل xxKSU ولا BBRv3.
> 2. **التقطيع لا يمكن نسبته للنواة قبل الروم.** لكن من المصدر يمكن إثبات أن **سلوك CPU/GPU/thermal في هذه النواة يحدده DT القادم من الروم** (`boot.img`/`dtbo.img`)، لأن شجرة النواة لا تحتوي أي DTS لـ miatoll. أي "tuning" ثابت في النواة سيكون أعمى.
> 3. **لم أطبّق أي قيمة أداء.** البروفايل مُهيَّأ لكنه no-op حتى تصبح بنوده `READY`؛ هذا هو التطبيق الحرفي لقاعدتك "إذا لم يوجد دليل كافٍ اتركها كما هي".

---

## 1. المرحلة A — فحص الروم

### 1.1 ما تم التحقق منه فعليًا

محاولة الوصول المباشر من الساندبوكس فشلت بشكل قابل للتكرار:

```
$ curl -sS -I -L https://pixeldrain.com/u/ENFhkYH5
curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to pixeldrain.com:443
$ curl -sS -o /dev/null -w "%{http_code}" https://api.github.com   →  200
```

أي أن الشبكة مسموحة فقط لقائمة مضيفين محددة. تم استخدام أداة قراءة صفحات (لا تنزّل الملف) للحصول على البيانات الوصفية وفهرس الأرشيف:

| الحقل | القيمة |
|---|---|
| الاسم | `HyperOS_Miatoll_20261107_@iputobject_OS3.0.3.0.VLCCNXM_15.zip` |
| الحجم | `3,551,449,452` بايت |
| sha256 | `783ad4f7be1330483aedab39344921a1ca9df9d3ca519634352db0430a60264c` |
| mime | `application/zip` |
| الرفع | 2026-11-07T12:05:52Z |
| محتوى الأرشيف | `META-INF/` 19.4 MB · `boot.img` 134 MB · `dtbo.img` 1.05 MB · `super.img.zst` 3.52 GB |

### 1.2 ما يمكن استنتاجه بأمان من الفهرس (وحده)

- **لا يوجد `vendor_boot.img` ولا `vendor.img` مستقل ولا `recovery.img`** داخل الأرشيف ⇒ الأقسام الديناميكية كلها داخل `super.img.zst`، والـ `boot.img` هو boot كلاسيكي (kernel + ramdisk + DTB محتمل).
- `META-INF` بحجم 19.4 MB أكبر بكثير من مُثبِّت AOSP العادي (~1 MB) ⇒ مُثبِّت مخصص (نمط Magisk/AnyKernel أو updater-binary ضخم). لا يمكن الجزم بالمحتوى.
- `dtbo.img` بحجم 1.05 MB ⇒ يحتوي overlays فعلية. **هذا الملف هو مصدر الحقيقة لـ thermal trips وCPU/GPU tables وcore_ctl على هذا الجهاز**، لأن شجرة النواة خالية من DTS لـ miatoll (§2.7).
- `boot.img` بحجم 134 MB أكبر من المعتاد لهذا الـ SoC ⇒ يحتوي عناصر إضافية (DTB مضمّن و/أو ramdisk كبير). **لا يمكن الجزم** دون فك الترويسة.

### 1.3 ما لم يتم — بوضوح

لم يتم فحص: بنية `super.img`، أنواع الملفات، `vendor` blobs، `build.prop`، خدمـات Power/Thermal HAL، `init.rc`، `fstab`، power profiles، overlays، أي إعداد خاص بالبورت. أي رقم في بقية التقرير لا يستند إلى محتوى الروم.

**الأداة التي تُغلق هذه المرحلة:** `hyperos/tools/rom-evidence.sh` (§8)، وتُنتج مجلدًا نصيًا صغيرًا يمكن إرساله. كما أن `hyperos/evidence/EVIDENCE-REQUIRED.md` يسرد كل بند مطلوب والقرار الذي يفتحه.

---

## 2. المرحلة B — فحص النواة (مكتملة، بأدلة)

### 2.1 الهوية والإصدار

| البند | القيمة الفعلية | الدليل |
|---|---|---|
| إصدار النواة | `4.14.356-openela-rc1` | `Makefile:2-5` |
| المعماريّة | arm64، `CONFIG_ARCH_ATOLL=y`, `CONFIG_ARCH_SDMMAGPIE=y` | `arch/arm64/configs/vendor/xiaomi/miatoll_defconfig` |
| عدد المعالجات | `CONFIG_NR_CPUS=8`، بنية 2+6 | `miatoll_defconfig` |
| سجل الالتزامات | **التزام واحد** `7bc580b93 drm/msm/sde: add KCAL color control` يحتوي الشجرة كاملة | `git rev-list --count HEAD` = 1 |
| الحُزم | `CONFIG_PREEMPT=y`, `CONFIG_HZ_300`, `CONFIG_NO_HZ=y` | miatoll_defconfig |

> **تنبيه هوية (مُحدَّث):** الشجرة الحقيقية لنواة DOOM هي **`phen-ix/kernel`، فرع
> `arena/c39745c5-kernel`** (4.14.357، `CONFIG_LOCALVERSION="-DOOM"`، xxKSU 32714،
> `CONFIG_TCP_CONG_BBR3=y`, `CONFIG_EROFS_FS=y`). الشجرة التي فُحصت هنا
> (`phen-ix/new` @ `7bc580b93`) هي قاعدة CAF 4.14.356-rc1 + KCAL فقط. لذلك
> الحقائق الخاصة بالتهيئة (KSU/BBRv3/الحاكم الافتراضي/EROFS) تنطبق على شجرة
> القاعدة لا على شجرة DOOM — والتصحيح الكامل في
> [`evidence/KERNEL-TREE.md`](evidence/KERNEL-TREE.md).

### 2.2 KernelSU و BBRv3 — غير موجودين في هذه الشجرة

| الادعاء | الواقع في المصدر | الدليل |
|---|---|---|
| xxKSU | **لا وجود لأي أثر** لـ KernelSU | `grep -ril kernelsu` → لا نتائج · `find -iname "*ksu*"` → لا نتائج · لا `CONFIG_KSU` في أي defconfig |
| BBRv3 | **لا وجود** لـ BBRv3، ولا حتى BBR مُفعَّل | `net/ipv4/tcp_bbr.c` خالٍ من بصمات BBRv3 (`bbr_policer`/`bw_hi`/`bbr3`) · `CONFIG_TCP_CONG_BBR` غير موجود في أي من إعدادات atoll/miatoll؛ يظهر فقط في `arch/arm64/configs/stock_defconfig:891` (BBRv1) · **إعدادات atoll/miatoll لا تفعّل BBR إطلاقًا** ⇒ خوارزمية الاحتقان الافتراضية في البناء `cubic` |
| وظائف DOOM الأخرى | لا توجد تعديلات سوى KCAL | سجل الالتزامات |

**الأثر العملي:** إن كنت تبني من هذه الشجرة، فلن تحصل على xxKSU ولا BBRv3. يجب تحديد الفرع/الشجرة الصحيحة قبل أي تحسين أداء — وإلا فكل قياس سيُبنى على نواة ليست نواة المشروع.

### 2.3 المُجدوِل: WALT + schedtune + EAS + core_ctl (لا uclamp)

| الميزة | الحالة | الدليل |
|---|---|---|
| WALT | مفعّل | `miatoll_defconfig:11 CONFIG_SCHED_WALT=y` |
| schedtune | مفعّل | `miatoll_defconfig:32`، الكود `kernel/sched/tune.c` (attrs: `boost`, `prefer_idle`, `colocate`, `sched_boost_no_override`) |
| EAS | مفعّل | `CONFIG_DEFAULT_USE_ENERGY_AWARE=y` (miatoll:39, atoll-perf:33) + `kernel/sched/energy.c` |
| core_ctl | موجود | `kernel/sched/core_ctl.c:1283` → `kobject_add(&cluster->kobj, &dev->kobj, "core_ctl")` ⇒ `/sys/devices/system/cpu/cpuN/core_ctl/` |
| **UCLAMP** | **غير موجود** | `grep -rn CONFIG_UCLAMP_TASK` في `kernel/ inherit/include/` → لا نتائج |
| WALT sysctls | موجودة | `kernel/sysctl.c:380` (`sched_group_upmigrate`), `:397` (`sched_boost`), وأيضًا `sched_conservative_pl`, `sched_many_wakeup_threshold`, `sched_min_task_util_for_*`, `sched_little_cluster_coloc_fmin_khz` |

القيم الافتراضية المثبتة من المصدر: `sched_group_upmigrate=100`, `sched_group_downmigrate=95` (`walt.c:2504,2512`), `sched_min_task_util_for_boost=51` و`..._for_colocation=35` (`fair.c:207,209`), `sched_many_wakeup_threshold=1000`, `sched_conservative_pl=0`, `sched_little_cluster_coloc_fmin_khz=1000000` (`walt.c:3084`).

> **نتيجة مهمة:** أي "UCLAMP tweak" من الإنترنت **غير قابل للتطبيق أصلًا** على هذا الجهاز — الواجهة غير موجودة. هذا مثال ملموس على قيمة الفحص قبل النسخ.

### 2.4 CPUFreq

| البند | القيمة | الدليل |
|---|---|---|
| السائق | `drivers/cpufreq/qcom-cpufreq.c` (لا يوجد `qcom-cpufreq-hw.c` في هذه الشجرة) | `ls drivers/cpufreq` |
| جداول التردد | من الـ DT: `qcom,cpufreq-table-0` و`-6` | `arch/arm64/boot/dts/qcom/atoll.dtsi:2018,2030` |
| policy0 (CPUs 0-5) | 300 / 576 / 768 / 1017.6 / 1248 / 1324.8 / 1516.8 / 1612.8 / 1708.8 / **1804.8 MHz** | نفس المرجع (10 مستويات) |
| policy6 (CPUs 6-7) | 652.8 / 825.6 / 979.2 / 1113.6 / 1267.2 / 1555.2 / 1708.8 / 1843.2 / 1900.8 / 1996.8 / 2112 / 2208 / **2323.2 MHz** | نفس المرجع (13 مستوى) |
| الحاكم الافتراضي عند الإقلاع | **performance** (اختيار Kconfig الافتراضي، لم يُغيَّر في أي من الإعدادين) | `drivers/cpufreq/Kconfig` (choice default) |
| schedutil | مفعّل | `miatoll_defconfig` + `kernel/sched/cpufreq_schedutil.c` |
| `up_rate_limit_us` | **500 µs** | `miatoll_defconfig:115 CONFIG_SCHEDUTIL_UP_RATE_LIMIT=500` |
| `down_rate_limit_us` | **1000 µs** (الافتراضي؛ غير مُتجاوَز) | `drivers/cpufreq/Kconfig` (`SCHEDUTIL_DOWN_RATE_LIMIT default 1000`) |
| `iowait_boost_enable` | **0** (مثبت في الكود) | `cpufreq_schedutil.c:785` |
| عقد sysfs | `.../policyX/schedutil/{up_rate_limit_us,down_rate_limit_us,iowait_boost_enable}` | `cpufreq_schedutil.c:589-591` |

> **ملاحظة تخصّ البورت:** بما أن الحاكم الافتراضي في النواة هو `performance`، فإن الروم هو من يبدّله إلى `schedutil` في بداية الإقلاع. عقد `schedutil/*` **لا توجد قبل ذلك**. لهذا السبب ينتظر `service.sh` في موديول البروفايل `sys.boot_completed` ولا يكتب في `post-fs-data`.

### 2.5 CPU_BOOST (input boost داخل النواة)

مفعّل: `CONFIG_CPU_BOOST=y` (`atoll-perf:100`, و`miatoll`). الواجهة:

```
/sys/module/cpu_boost/parameters/input_boost_ms         = 40     (drivers/cpufreq/cpu-boost.c:39)
/sys/module/cpu_boost/parameters/sched_boost_on_input   = 0      (cpu-boost.c:42)
/sys/module/cpu_boost/parameters/input_boost_freq        = per-CPU، يأتي من الـ DT (cpu-boost.c:116)
```

هذا هو **أهم تقاطع محتمل** بين النواة وHyperOS: الروم (PowerHAL / perf service) قد يرفع الترددات أيضًا عند اللمس. ازدواج الـ boost يظهر كاستهلاك وحرارة زائدين بدون تحسّن في زمن الاستجابة. لا يمكن إثبات ذلك إلا بقياس (الفرضية H2، المعرّف E-08).

### 2.6 msm_performance — واجهة PowerHAL

`drivers/soc/qcom/msm_performance.c`:

```
/sys/module/msm_performance/parameters/cpu_min_freq   (0644)   (msm_performance.c:130)
/sys/module/msm_performance/parameters/cpu_max_freq   (0644)   (msm_performance.c:198)
/sys/module/msm_performance/parameters/core_ctl_register       (msm_performance.c:444)
notify kobjects: cpu_hotplug, aggr_big_nr, aggr_top_load
```

هذه هي الواجهة التي يكتب عليها PowerHAL (Qualcomm/Xiaomi) لتثبيت حدود التردد أثناء التفاعل. أي بروفايل يكتب على `scaling_max_freq` مباشرة سيتصارع معها. لذلك البروفايل **لا يلمس** حدود التردد إطلاقًا.

### 2.7 الاعتماد على DT القادم من الروم (نتيجة معمارية حاسمة)

```
$ grep -rl miatoll arch/arm64/boot/dts/     →  (لا نتائج)
$ ls arch/arm64/boot/dts/qcom/atoll*        →  لوحات مرجعية فقط (idp/qrd/atp)
```

⇒ **لا يوجد DTS لـ miatoll في شجرة النواة.** وبالتالي القيم التالية تُحدَّد من `boot.img`/`dtbo.img` الخاصين بالروم، لا من النواة:

- جداول ترددات CPU الفعلية وعدد المستويات
- مستويات GPU (`qcom,gpu-pwrlevels`؛ في DT المرجعي: 825/800/650/565/430/355/267 MHz — 41 مدخل `qcom,gpu-freq` عبر `pwrlevels-0/1` في `atoll.dtsi:3469+`)
- thermal trips وcooling maps (`thermal_zones: thermal-zones {}` فارغة في `atoll.dtsi:2905`، تُملأ من DT اللوحة)
- قيم `core_ctl` (min/max cpus، thresholds، offline delay)
- `input_boost_freq` لكل نواة

**الأثر:** أي إعداد مكتوب في النواة يفترض قيمًا معينة لهذه العناصر هو إعداد أعمى. ولهذا كل بنود `core_ctl` و`input_boost_freq` في البروفايل هي **observe-only** حتى يُفكّ `dtbo.img`.

### 2.8 GPU (KGSL)

| البند | القيمة | الدليل |
|---|---|---|
| السائق | `CONFIG_QCOM_KGSL=y`، `drivers/gpu/msm/` | الإعداد + الشجرة |
| حاكم devfreq | `msm-adreno-tz` | `drivers/devfreq/governor_msm_adreno_tz.c:559` |
| العقد | `/sys/class/kgsl/kgsl-3d0/{devfreq/*, min_pwrlevel, max_pwrlevel, gpu_busy_percentage}` | `drivers/gpu/msm/adreno_sysfs.c` |
| حدود حرارية | `CONFIG_DEVFREQ_THERMAL=y` ⇒ thermal يمكنه تقييد GPU | miatoll_defconfig |

### 2.9 Thermal

| المكوّن | الحالة | الدليل |
|---|---|---|
| نواة thermal | `CONFIG_THERMAL=y` + `CPU_THERMAL` + `DEVFREQ_THERMAL` | miatoll_defconfig |
| **trips قابلة للكتابة** | `CONFIG_THERMAL_WRITABLE_TRIPS=y` | miatoll_defconfig |
| حاكم userspace | `CONFIG_THERMAL_GOV_USER_SPACE=y` + `LOW_LIMITS` | miatoll_defconfig |
| QTI | `QTI_THERMAL_LIMITS_DCVS`, `QTI_VIRTUAL_SENSOR`, `QTI_QMI_COOLING_DEVICE`, `QTI_QMI_SENSOR`, `QTI_BCL_PMIC5`, `QTI_BCL_SOC_DRIVER`, `QTI_ADC_TM` | miatoll_defconfig |
| واجهة Xiaomi `thermal_message` | **غير موجودة** | `grep -rn thermal_message` → لا نتائج |

**نقطتان مهمتان:**
1. وجود `THERMAL_WRITABLE_TRIPS` يعني أن *إمكانية* رفع حدود الحرارة موجودة. البروفايل **لا يستخدمها إطلاقًا**: رفع trip يشتري أداءً قصير المدى على حساب الأداء المستدام وعمر البطارية، وهو عكس الأولوية المطلوبة.
2. غياب `thermal_message` يعني أن أي خدمة في الروم تتوقع هذه الواجهة (نمط `mi_thermald` في بعض بورتات HyperOS) ستجدها مفقودة. **هذا احتمال يجب التحقق منه من الروم** (E-15) — لا أستطيع تأكيده دون `vendor`.

### 2.10 الذاكرة

| البند | الحالة/القيمة | الدليل |
|---|---|---|
| PSI | مفعّل | `atoll-perf:12 CONFIG_PSI=y` + `kernel/sched/psi.c` |
| memcg + swap accounting | مفعّل | `CONFIG_MEMCG=y`, `CONFIG_MEMCG_SWAP=y` (atoll-perf:22) |
| in-kernel LMK | **غير مفعّل** | `drivers/staging/android/Kconfig:26` موجود لكن لا `CONFIG_ANDROID_LOW_MEMORY_KILLER` في الإعدادين ⇒ **lmkd في userspace** هو من يقتل |
| `CONFIG_ANDROID_SIMPLE_LMK` | مذكور في miatoll لكن **الرمز غير موجود في الشجرة** | `drivers/staging/android/` لا يحتوي `simple_lmk.c` ⇒ خيار ميت (يُتجاهل بصمت) |
| swappiness | `85` (وليس 100) | `mm/vmscan.c:160` |
| extra_free_kbytes | `0` | `mm/page_alloc.c:331`، sysctl في `kernel/sysctl.c:1690` |
| watermark_scale_factor | `10` | `mm/page_alloc.c:324` |
| ZRAM | `CONFIG_ZRAM=y`, `ZSMALLOC=y`, `ZRAM_DEDUP=y`، الضاغط الافتراضي `lz4` | `miatoll:284`, `atoll-perf:269`, `drivers/block/zram/zram_drv.c:44` |
| backends | `lzo / lz4 / lz4hc / zstd` | `drivers/block/zram/zcomp.c:22-36` |
| MGLRU | غير موجود (ليس في 4.14) | — |

**الأثر:** ضبط الذاكرة على هذا الروم يمرّ عبر `ro.lmk.*` (userspace، طرف الروم) لا عبر النواة. لذلك بنود LMK في البروفايل **غائبة عمدًا** — لا معنى لضبط قيمة kernel لا يقرأها أحد.

### 2.11 التخزين و I/O

| البند | الحالة | الدليل |
|---|---|---|
| `MQ_IOSCHED_DEADLINE` / `MQ_IOSCHED_KYBER` | **معطّلان صراحة** | `miatoll_defconfig:61-62` |
| CFQ | مبني ومستخدم | `CONFIG_CFQ_GROUP_IOSCHED=y` (`miatoll:60`) |
| BFQ | الكود موجود، **غير مفعّل** | `block/bfq-iosched.c`، `block/Kconfig.iosched:83` |
| UFS | `SCSI_UFSHCD` + `UFS_QCOM` + crypto | miatoll_defconfig |
| F2FS | مفعّل + xattr (افتراضي y) + encryption | miatoll_defconfig، `fs/f2fs/Kconfig:35` |
| EXT4 | مفعّل | miatoll_defconfig |

### 2.12 الشبكة / BBR

كما في §2.2: BBR غير مُجمَّع في إعدادات miatoll/atoll. `net/ipv4/tcp_bbr.c` هو BBRv1/v2-style (لا يحتوي `bbr_policer`، ولا `bw_hi[]`). **لا يمكن "ضبط BBRv3" على بناء لا يحتويه.**

---

## 3. المرحلة C — تدقيق التوافق (مصفوفة)

العمود "متطلب الروم" مصدره التحليل المعماري لواجهات Android الحديثة؛ والعمود "الدليل" يثبت حالة النواة من المصدر. البنود التي تحتاج تأكيدًا من الروم مُعلَّمة ⚠️.

| # | الواجهة/القدرة | حالة النواة | الأثر المحتمل | يحتاج تأكيد الروم |
|---|---|---|---|---|
| C1 | **EROFS** | **مفقود** (الكود موجود، لا إعداد يفعّله) | إن كانت أقسام super من نوع erofs ⇒ استحالة التركيب | ⚠️ E-14 |
| C2 | TMPFS_XATTR | **مفقود** (`fs/Kconfig:177` default n) | overlayfs على tmpfs أو أي label على tmpfs يفشل | ⚠️ |
| C3 | binderfs | ✅ `CONFIG_ANDROID_BINDERFS=y` | OK لأندرويد 10+ | — |
| C4 | PSI + lmkd | ✅ `CONFIG_PSI=y`, LMK في userspace | متوافق مع نموذج Android الحديث | — |
| C5 | sdcardfs + FUSE | ✅ كلاهما | مسارات التخزين القديمة والحديثة متاحة | — |
| C6 | incremental-fs | ✅ `CONFIG_INCREMENTAL_FS=y` | تثبيت/تحديث تطبيقات HyperOS | — |
| C7 | dm-verity / dm-bow | ✅ | AVB + Xiaomi dynamic partitions writeback | — |
| C8 | واجهة Xiaomi `thermal_message` | **مفقودة** | خدمات حرارية تتوقعها ستفشل بصمت | ⚠️ E-15 |
| C9 | `msm_performance` | ✅ | PowerHAL يستطيع كتابة حدود التردد | — |
| C10 | `cpu_boost` | ✅ | احتمال ازدواج boost مع PowerHAL | ⚠️ E-08 |
| C11 | uclamp | **مفقود (غير موجود في 4.14 هنا)** | لا بروفايلات uclamp | — |
| C12 | DT الخاص بالجهاز | **مفقود من الشجرة** ⇒ يأتي من الروم | كل قيم CPU/GPU/thermal من الروم | ⚠️ E-07 |
| C13 | `CONFIG_KEYS` | مفقود (default n) | فقط إن استخدم الروم keyctl | ⚠️ |
| C14 | `CONFIG_USER_NS` | مفقود (default n) | فقط إن احتاج sandbox ذلك | ⚠️ |
| C15 | `PID_NS/UTS_NS/NET_NS` | معطّلة في miatoll | لا يؤثر على sandbox التطبيقات العادي | — |
| C16 | MQ deadline/kyber | معطّلان صراحة | CFQ فقط على UFS | — |

**خلاصة C:** لا يوجد في المصدر تعارض *مثبت* يمنع الإقلاع، لكن هناك **فجوتان قدريتان مؤكدتان** (C1, C2) و**واحدة محتملة** (C8) لا يمكن حسمها دون الروم.

---

## 4. المرحلة D — تشخيص الأداء: فرضيات وأدلة مطلوبة

> **لا توجد قياسات في هذا التقرير.** ما يلي خطة إثبات: كل فرضية مربوطة بمؤشر وأداة.

| # | الفرضية | المؤشر الذي يثبتها | الأداة | البند في البروفايل |
|---|---|---|---|---|
| H1 | تأخير قرارات التردد (`up_rate_limit_us=500`) يسبب jank في التمرير | توزيع `cpu_frequency` مقابل `sched_switch` أثناء scroll؛ نسبة الإطارات التي تجاوزت 16.7ms مع بقاء التردد دون الحد | ftrace / perfetto | E-01 |
| H2 | ازدواج boost (kernel `cpu_boost` + PowerHAL) | مقارنة زمن الإطلاق + التيار + الحرارة مع `input_boost_ms=0` مقابل 40 | device-metrics + compare | E-08 |
| H3 | `core_ctl` يطفئ أنوية كبيرة بسرعة/يؤخر إيقاظها ⇒ تصلب عند تبديل التطبيقات | عدد انتقالات cpu6 online/offline + jank عند app switch | ftrace `cpu_hotplug` | E-07 |
| H4 | lmkd يقتل تطبيقات الخلفية مبكرًا ⇒ إعادة تحميل باردة | عدد `lmkd` kills + معدل الإطلاق البارد | logcat events + metrics | E-09 (طرف الروم) |
| H5 | ضغط zram / swappiness مرتفع ⇒ توقفات page fault | `pswpin/pswpout` لكل ثانية، PSI io/memory، zram mm_stat | device-metrics | E-09/E-11 |
| H6 | خنق حراري من إعداد الروم (QTI) لا من النواة | تغيّر `max_freq` الفعلي مع الوقت + cooling device states + BCL | soak series | E-13 |
| H7 | I/O stall مع CFQ على UFS | PSI io أثناء فتح التطبيقات، block trace، fsync latency | ftrace block / `iostats` | E-12 |

**قاعدة القرار:** لا يُعدَّل أي بند في البروفايل إلا إذا أظهرت المقارنة تغيّرًا يتجاوز 3% مع n≥5 (أو n = عدد الإطارات للـ UI) دون تراجع في الحرارة أو استهلاك الخمول.

---

## 5. المرحلة E — جدول التعديلات المقترحة

**القيم الحالية مثبتة من المصدر (وليس من الجهاز).** العمود "الهدف" فارغ/`PENDING` بقرار: كل هدف يحتاج الدليل المذكور.

| المعرّف | المفتاح | القيمة الحالية | الهدف | حالة البوابة | الدليل المطلوب | لماذا لا نغيّر الآن |
|---|---|---|---|---|---|---|
| E-01 | `policy{0,6}/schedutil/up_rate_limit_us` | 500 µs | — | PENDING | ftrace على الروم | لا دليل على أن القيمة سبب jank؛ تغييرها قد يزيد الحرارة بلا فائدة |
| E-01 | `.../down_rate_limit_us` | 1000 µs | — | PENDING | نفس المرجع | نفس السبب |
| E-02 | `.../iowait_boost_enable` | 0 | — | PENDING | PSI io + trace | تفعيله يرفع التردد عند انتظار I/O؛ قد يزيد الطاقة |
| E-03 | `/proc/sys/kernel/sched_group_upmigrate` | 100 | — | PENDING | trace الهجرة | الهجرة تؤثر مباشرة على الحرارة والتوازن |
| E-03 | `sched_group_downmigrate` | 95 | — | PENDING | نفس المرجع | نفس السبب |
| E-04 | `sched_boost` | 0 | — | PENDING | سلوك الروم (audit) | الروم قد يستخدمه بالفعل |
| E-05 | `sched_conservative_pl` | 0 | — | PENDING | trace wakeups | يغيّر سياسة اختيار التردد جذريًا |
| E-05 | `sched_many_wakeup_threshold` | 1000 | — | PENDING | trace | — |
| E-05 | `sched_min_task_util_for_boost` | 51 | — | PENDING | trace | يؤثر على ترقية المهام الصغيرة |
| E-05 | `sched_min_task_util_for_colocation` | 35 | — | PENDING | trace | يؤثر على التجميع |
| E-06 | `sched_little_cluster_coloc_fmin_khz` | 1000000 | — | PENDING | trace | يحدد أدنى تردد للتجميع على little |
| E-07 | `core_ctl/*` | من DT الروم | observe | PENDING | `dtbo.img` + sysfs | القيم ليست في شجرة النواة |
| E-08 | `cpu_boost/input_boost_ms` | 40 | — | PENDING | مقارنة A/B | قد يكون Boost مزدوجًا؛ يحتاج قياس |
| E-08 | `cpu_boost/sched_boost_on_input` | 0 | — | PENDING | مقارنة A/B | يتقاطع مع schedtune |
| E-08 | `cpu_boost/input_boost_freq` | من DT | observe | PENDING | DT | غير معروف |
| E-09 | `vm/swappiness` | 85 | — | PENDING | PSI + pswp | 85 هو افتراضي Qualcomm؛ تغييره يؤثر على زمن الفتح |
| E-09 | `vm/extra_free_kbytes` | 0 | — | PENDING | meminfo/PSI | يزيد الذاكرة المحجوزة |
| E-09 | `vm/watermark_scale_factor` | 10 | — | PENDING | pgscan/refault | يغيّر توقيت reclaim |
| E-10 | `vm/vfs_cache_pressure` | 100 | — | PENDING | workingset | يؤثر على dentry cache |
| E-11 | `zram0/comp_algorithm` | lz4 | observe | PENDING | init.rc الروم | الروم يضبطه |
| E-12 | `sda/queue/scheduler` | cfq (متوقع) | observe | PENDING | قياس I/O | enum؛ يُغيَّر بقياس فقط |
| E-12 | `sda/queue/read_ahead_kb` | 128 | — | PENDING | قياس | — |
| E-13 | `kgsl-3d0/devfreq/governor` | msm-adreno-tz | observe | PENDING | sysfs | يجب أن يبقى كما هو |
| E-13 | `kgsl-3d0/{min,max}_pwrlevel` | من DT | observe | PENDING | DT + حرارة | تقييد الترددات يضرّ الحوكمة الحرارية |
| E-14 | `CONFIG_EROFS_FS` | معطّل | يفعّل **بعد** تأكيد erofs | PENDING | `super.img` | لا نفعّل بلا دليل نوع FS |
| — | **trips / cooling devices** | — | **لا يُلمس** | — | — | رفعها يخالف شرط الحفاظ على الحماية الحرارية |

**عدد البنود:** 36 في ملف البروفايل، منها 15 observe-only. **عدد البنود القابلة للكتابة الآن: صفر.**

---

## 6. المرحلة F — ما تم تنفيذه فعليًا

### 6.1 المبدأ

لا يمكن تبرير أي قيمة أداء بدليل متاح اليوم. لذلك نُفِّذ **الإطار** (قابل للتفعيل/التعطيل/الرجوع) وبقي **المحتوى** خاملًا عمدًا:

- لا تغيير في `defconfig` الأساسي ⇒ لا تأثير على أي روم آخر.
- البروفايل في ملف منفصل + موديول منفصل ⇒ فصل تام عن الإعدادات العامة.
- كل كتابة تُسبق backup وتُتبع بتحقق read-back، والرجوع ممكن دائمًا.

### 6.2 الملفات المضافة

| الملف | الوظيفة |
|---|---|
| `hyperos/tools/doom-profile.sh` | محرّك البروفايل: `--audit`, `--apply`, `--revert`, `--status`, `--diff`؛ يمنع الكتابة على عقدة مفقودة/للقراءة فقط/خارج الحدود/مكرّرة، ويحترم بوابة `READY/PENDING`، ويلفّ العملية بقفل. |
| `hyperos/profiles/hyperos-os3.0.3-miatoll.conf` | 36 بندًا مع الحدود (من معالج sysctl/Kconfig) ومعرّف الدليل لكل بند. |
| `hyperos/ksu-module/miatoll-hyperos-profile/` | `module.prop`, `post-fs-data.sh` (لقطة ما قبل userspace), `service.sh` (ينتظر `sys.boot_completed` ثم audit + apply), `uninstall.sh` (revert). |
| `hyperos/tools/rom-evidence.sh` | استخراج أدلة الروم (تحقق sha256، boot، ramdisk، dtbo، super/lpunpack، props، HAL/thermal/init/fstab). |
| `hyperos/tools/device-metrics.sh` | قياسات الجهاز: static / launch / ui (gfxinfo framestats) / idle / soak. |
| `hyperos/tools/compare.py` | مقارنة قبل/بعد مع قواعد دلالة صريحة (≥3%، n≥5) ورفض الاستنتاج المضخّم. |
| `arch/arm64/configs/vendor/xiaomi/hyperos_compat.config` | fragment توافق **غير مرتبط بأي بناء** (EROFS/TMPFS_XATTR + مرشّحات معطّلة موثّقة). |
| `hyperos/evidence/EVIDENCE-REQUIRED.md` | ما هو مطلوب بالضبط ولماذا. |

### 6.3 ما تم اختباره فعليًا (وما لم يُختبر)

| العنصر | الاختبار | النتيجة |
|---|---|---|
| `doom-profile.sh` | `sh -n` + شجرة sysfs وهمية: audit / apply / revert / status / diff | ✅ يعمل: طبّق بندين وأرجعهما بدقة؛ رفض عقدة مفقودة، عقدة للقراءة فقط، قيمة خارج الحدود، وبندًا مكرّرًا |
| بوابة PENDING | `--apply` على البروفايل الحقيقي | ✅ يخرج بـ no-op مع رسالة صريحة |
| `rom-evidence.sh` | `bash -n` + أرشيف وهمي (boot/dtbo/super) | ✅ يعمل ويهبط بأمان إلى `UNKNOWN` عند غياب الأدوات |
| محلّل frame stats | عيّنة `gfxinfo framestats` بصيغة AOSP | ✅ يحسب frames / jank% / p50 / p90 / p99 (16.7ms → 43ms في العيّنة) |
| `compare.py` | CSV اصطناعي | ✅ يعطي IMPROVED/REGRESSED للقياسات ذات n≥5 وINFO لغيرها |
| **الجهاز** | — | ❌ **لم يُنفَّذ أي شيء على جهاز**؛ لا يوجد جهاز في هذه البيئة |
| **الروم** | — | ❌ لم يُفحص محتواه (شبكة محجوبة) |

> مخرجات كل اختبار أعلاه محفوظة حرفيًا في `hyperos/evidence/validation-log.txt` (96 سطرًا) لإمكانية التحقق، بما فيها ما **لم** يُختبر.

### 6.4 Git Diff

جميع الملفات **جديدة** (لا تعديل على أي ملف قائم في الشجرة)، لذلك الـ diff إضافي بالكامل:

```
$ git status --short          # كل الملفات جديدة (A) — لا ملف قائم عُدّل
A  arch/arm64/configs/vendor/xiaomi/hyperos_compat.config
A  hyperos/README.md
A  hyperos/REPORT.md
A  hyperos/evidence/EVIDENCE-REQUIRED.md
A  hyperos/evidence/validation-log.txt
A  hyperos/ksu-module/miatoll-hyperos-profile/{module.prop,post-fs-data.sh,service.sh,uninstall.sh,bin/*}
A  hyperos/profiles/hyperos-os3.0.3-miatoll.conf
A  hyperos/tools/{doom-profile.sh,rom-evidence.sh,device-metrics.sh,compare.py,sync-module.sh}

$ git diff --stat            # (بعد git add -N لعرض المحتوى)
 .../xiaomi/hyperos_compat.config                   |  75 ++++
 hyperos/README.md                                  |  ...
 hyperos/REPORT.md                                  |  ...
 hyperos/evidence/...                               |  ...
 hyperos/profiles/hyperos-os3.0.3-miatoll.conf      | 179 ++++
 hyperos/tools/compare.py                           | 128 ++++
 hyperos/tools/device-metrics.sh                    | 308 ++++
 hyperos/tools/doom-profile.sh                      | 360 ++++
 hyperos/tools/rom-evidence.sh                      | 443 ++++
 (الإجمالي: 17 ملفًا، 2,878 سطرًا، كلها إضافية)
```

السبب في عدم تعديل أي ملف قائم: أي تعديل في `defconfig` أو في C سيغيّر سلوك النواة
على كل الرومات، وهو ما تمنعه قاعدتك (§6 من طلبك) قبل وجود دليل.

السبب في عدم تعديل أي ملف قائم: أي تعديل في `defconfig` أو في C سيغيّر سلوك النواة على كل الرومات، وهو ما تمنعه قاعدتك (§6 من طلبك) قبل وجود دليل.

---

## 7. المرحلة G — بروتوكول الاختبار

### 7.1 الشروط المسبقة

- نفس جهاز الفيزيائي، نفس نسخة الروم، نفس الحرارة المحيطة (سجّلها)، شاشة بنفس السطوع، وضع طيران موحّد للقياسات الحساسة.
- إعادة إقلاع واحدة قبل كل جلسة، وانتظار 10 دقائق استقرار قبل القياس.
- **n ≥ 7** لكل قياس إطلاق/تمرير؛ تحت ذلك `compare.py` يرفض إعطاء حكم.

### 7.2 الأوامر

```bash
# baseline (قبل تفعيل أي بند)
./hyperos/tools/device-metrics.sh baseline --pkg com.miui.home --scenario all --runs 7
./hyperos/tools/device-metrics.sh baseline-game --scenario soak --seconds 900   # أثناء اللعب يدويًا

# بعد تفعيل البروفايل (وحده، بعد وصول الأدلة)
./hyperos/tools/device-metrics.sh after-profile --pkg com.miui.home --scenario all --runs 7
./hyperos/tools/device-metrics.sh after-game  --scenario soak --seconds 900

python3 hyperos/tools/compare.py metrics/baseline/summary.csv metrics/after-profile/summary.csv --md metrics/report.md
```

### 7.3 معايير القبول (تُعلن قبل القياس لا بعده)

| البند | المعيار |
|---|---|
| Boot stability | إقلاع كامل، لا `panic`/`SSR` في dmesg، كل الخدمات `running` |
| UI jank | `scroll_jank_pct` ينخفض ≥10% نسبيًا، أو `p90` ينخفض ≥10% |
| App launch | `totaltime_median` لا يتراجع >3%، ويُفضّل تحسّن ≥5% |
| Thermal | ذروة الحرارة في soak لا تزيد >2°C، ولا انخفاض في التردد المستدام |
| Idle drain | `current_median` في الخمول لا يزيد >5% |
| Memory | لا زيادة في `lmkd` kills، ولا ارتفاع في PSI memory |
| Sustained | لا فرق >5% في ترددات الـ soak بين الدقيقة 1 والدقيقة 15 |

**أي بند يفشل ⇒ يُرجع إلى `PENDING` ويُسجَّل في §9.**

---

## 8. ما أحتاجه منك الآن (خطوة واحدة تفتح كل شيء)

**الخيار الأسرع (بدون رفع الروم):**
```bash
./hyperos/tools/device-metrics.sh baseline --pkg com.miui.home --scenario all --runs 7
# أرسل: metrics/baseline/summary.csv + static.txt + frames.txt
```
هذا يفتح المرحلة D فورًا: يكشف هل الروم نفسه يضبط `cpu_boost`/zram/core_ctl، وهل هناك خنق حراري.

**الخيار الأكمل:**
```bash
./hyperos/tools/rom-evidence.sh --zip HyperOS_Miatoll_20261107_..._15.zip --out ./rom-dossier --deep
# أرسل الملفات النصية الثمانية من rom-dossier/dossier/
```
هذا يفتح المرحلة A/C: نوع أقسام super، هل نحتاج EROFS، ما خدمات Power/Thermal، ما `ro.lmk.*`، ما هو DT الفعلي.

**وقبل ذلك:** أكّد أي شجرة/فرع هي نواة DOOM الحقيقية، لأن الشجرة الحالية لا تحتوي xxKSU ولا BBRv3 (§2.2). أي تحسين يُبنى على هذه الشجرة لن يكون نواة DOOM الموصوفة.

---

## 9. المخاطر والقيود المتبقية

| # | الخطر | الأثر | التخفيف |
|---|---|---|---|
| R1 | شجرة النواة لا تطابق مواصفات المشروع (لا KSU/BBRv3، إصدار أقدم) | كل بناء/قياس قد يكون على نواة غير صحيحة | تأكيد الفرع الصحيح قبل أي عمل |
| R2 | لم يُفحص الروم | قيم البروفايل غير مقرّرة | البروفايل no-op افتراضيًا؛ `EVIDENCE-REQUIRED.md` |
| R3 | DT من الروم وليس من الشجرة | أي قيمة CPU/GPU/thermal مثبتة في النواة قد تكون خاطئة للجهاز | observe-only لهذه البنود |
| R4 | لا قياسات على جهاز | لا يمكن إثبات أي تحسّن | بروتوكول + أدوات جاهزة؛ لن أقدّم أرقامًا وهمية |
| R5 | البروفايل يعتمد على KernelSU لتطبيقه عند الإقلاع | إن كانت النواة بلا KSU فلا يعمل الموديول | يمكن تشغيل المحرّك يدويًا بـ root؛ أو تفعيله من init (خارج نطاق "لا تعدّل الروم") |
| R6 | تعارض محتمل مع خدمات HyperOS (PowerHAL/thermal) | قيم تُكتب ثم يعيد الروم كتابتها ⇒ نتائج غير مستقرة | `service.sh` ينتظر `boot_completed` + 20s؛ و`--audit` يكشف من يكتب ماذا |
| R7 | EROFS/TMPFS_XATTR | إن كان الروم يحتاجهما فالبورت يعتمد على حل خارجي | fragment جاهز لكنه **غير مرتبط** ببناء حتى تأكيد E-14 |
| R8 | `hyperos_compat.config` قد يُنسى تفعيله | بناء لا يركّب أقسام الروم | موثّق في أعلى الملف + في §3 |

---

## 10. خلاصة القرار

- ✅ **فُحصت النواة بالكامل**، والنتائج قابلة للتحقق سطرًا بسطر.
- ⛔ **لم يُفحص الروم** — والسبب موثّق، والأداة جاهزة.
- ✅ **بُني الإطار** الذي يحوّل أي دليل لاحق إلى تعديل محدود، قابل للقياس والرجوع.
- ⛔ **لم تُطبَّق أي قيمة أداء** — التزامًا بقاعدة "إذا لم يوجد دليل كافٍ اتركها كما هي".
- ⚠️ **الشجرة الحالية ليست نواة DOOM الموصوفة** (لا xxKSU، لا BBRv3). هذه أهم نقطة يجب حسمها قبل الاستمرار.
