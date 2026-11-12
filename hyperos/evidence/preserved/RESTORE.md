# نسخ استرجاع المستودعات المحذوفة
# Recovery bundle for the repos being removed (saved before deletion)

أُنشئت قبل محاولة الحذف. كلها صغيرة (≈1.4 MB) وتُستعاد بدون إنترنت خاص.

| الملف | يعوّض | كيف يُستعاد |
|---|---|---|
| `uclamp-erofs/0000-NET-diff-vs-upstream-main.patch` | كل شغل فرع `uclamp-erofs` في `phen-ix/new` (49 ملفًا، +2764/−247) | `git apply` على أي شجرة بُنيت من `rbnj/kernel_xiaomi_miatoll@b07cf54d` |
| `uclamp-erofs/0001..0028-*.patch` | نفس العمل لكن مقسّمًا 28 التزامًا | `git am` أو `git cherry-pick` لكل واحد |
| `hyperos/0001..0003-*.patch` | إطار HyperOS (PR #1) | `git am` على فرع DOOM |
| `nexusbase/4d898c33-nexus-audit.patch` | الالتزام الفريد في `phen-ix/nexusbase` (93 ملفًا) | `git apply` على قاعدة CAF 4.14.265 |
| `AOSP-ROM-Builder.bundle` | مستودع أدوات بورت الروم كاملًا (كل الفروع والوسوم) | `git clone AOSP-ROM-Builder.bundle rom-builder` |
| `sm6250xx-commits.txt` | قائمة 100 التزام من أصل 269 في `kernel_xiaomi_sm6250xx` | **غير كافٍ** — انظر التحذير أدناه |
| `MANIFEST.txt` | بصمات كل الفروع قبل الحذف | مرجع |

## الاستعادة داخل مستودع DOOM (الوحيد الباقي)

```bash
git clone https://github.com/phen-ix/kernel.git doom && cd doom
git checkout arena/c39745c5-kernel

# 1) توافق Android 14-16 + uclamp + EROFS + thermal_message
git apply --3way /path/to/uclamp-erofs/0000-NET-diff-vs-upstream-main.patch
#    أو الأفضل للتاريخ: git am /path/to/uclamp-erofs/00*.patch

# 2) إطار HyperOS
git am /path/to/hyperos/00*.patch

git push origin HEAD:refs/heads/preserved/uclamp-erofs-hyperos
```

## ⚠️ تحذير واحد

`phen-ix/kernel_xiaomi_sm6250xx` فيه **269 التزامًا فريدًا** مقابل أبشريمه (جهاز
sm6250، ليس miatoll). لم أستطع تنزيلها كلها (المستودع 1.4 GB). عند حذفه تفقد
هذه الالتزامات نهائيًا إلا إذا كان عندك نسخة محلية:

```bash
git clone --mirror https://github.com/phen-ix/kernel_xiaomi_sm6250xx.git sm6250xx.git
# احتفظ بالملف؛ أو ادفعه إلى remote خاص قبل الحذف
```
