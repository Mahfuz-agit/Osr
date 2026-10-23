import glob
import pathlib
import re
import sys

REQUIRED_COMPILE_SDK = 37  # permission_handler 13.x needs compileSdk 37

# ---------------------------------------------------------------- manifest
path = pathlib.Path("android/app/src/main/AndroidManifest.xml")
if not path.exists():
    sys.exit("AndroidManifest.xml not found. Run flutter create first.")

s = path.read_text(encoding="utf-8")

PERMS = [
    ("android.permission.INTERNET", ""),
    ("android.permission.VIBRATE", ""),
    ("android.permission.READ_MEDIA_VIDEO", ""),
    ("android.permission.READ_EXTERNAL_STORAGE", ' android:maxSdkVersion="32"'),
]

block = ""
for name, extra in PERMS:
    if name not in s:
        block += '    <uses-permission android:name="%s"%s/>\n' % (name, extra)

s = re.sub(r"(<manifest[^>]*>\s*)", lambda m: m.group(1) + block, s, count=1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Personal Feed"', s, count=1)

for attr in (
    'android:usesCleartextTraffic="true"',
    'android:requestLegacyExternalStorage="true"',
):
    key = attr.split("=")[0]
    if key not in s:
        s = s.replace("<application", "<application " + attr, 1)

path.write_text(s, encoding="utf-8")
print("Patched", path)

# ------------------------------------------------------------------ gradle
# Works for both Kotlin DSL (build.gradle.kts) and Groovy (build.gradle).
pattern = re.compile(r"compileSdk(?:Version)?\s*=?\s*(flutter\.compileSdkVersion|\d+)")


def bump(match):
    value = match.group(1)
    if value.isdigit() and int(value) >= REQUIRED_COMPILE_SDK:
        return match.group(0)
    return "compileSdk = %d" % REQUIRED_COMPILE_SDK


patched = False
for g in glob.glob("android/app/build.gradle*"):
    gp = pathlib.Path(g)
    text = gp.read_text(encoding="utf-8")
    new = pattern.sub(bump, text)
    if new != text:
        gp.write_text(new, encoding="utf-8")
        print("compileSdk set to %d in %s" % (REQUIRED_COMPILE_SDK, g))
        patched = True
    elif pattern.search(text):
        print("compileSdk already >= %d in %s" % (REQUIRED_COMPILE_SDK, g))
        patched = True

if not patched:
    print("WARNING: compileSdk line not found. Check the Gradle printout in the log.")
