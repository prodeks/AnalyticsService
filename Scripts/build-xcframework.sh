#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXPECTED_XCODE="Xcode 26.6"
EXPECTED_BUILD="17F109"
EXPECTED_SWIFT="6.3.3"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0-Release.Candidate.app/Contents/Developer}"

xcode_version="$(xcodebuild -version)"
echo "$xcode_version" | grep -q "$EXPECTED_XCODE" || { echo "Wrong Xcode: expected $EXPECTED_XCODE"; echo "$xcode_version"; exit 1; }
echo "$xcode_version" | grep -q "$EXPECTED_BUILD" || { echo "Wrong Xcode build: expected $EXPECTED_BUILD"; echo "$xcode_version"; exit 1; }
swift_version="$(xcrun swift --version)"
echo "$swift_version" | grep -q "$EXPECTED_SWIFT" || { echo "Wrong Swift: expected $EXPECTED_SWIFT"; echo "$swift_version"; exit 1; }

rm -rf build

archive() {
  local destination="$1"
  local name="$2"
  xcodebuild archive \
    -project AnalyticsKit.xcodeproj \
    -scheme AnalyticsKit \
    -destination "$destination" \
    -archivePath "build/${name}.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
}

# libtool merges linked static SPM products into MACH_O_TYPE=staticlib.
# Keep only this target's objects so dependency symbols resolve once at app link.
strip_foreign_objects() {
  python3 - "$1" "$ROOT/Sources/AnalyticsKit" <<'PY'
import pathlib, shutil, subprocess, sys, tempfile

framework = pathlib.Path(sys.argv[1])
sources = pathlib.Path(sys.argv[2])
binary = framework / "AnalyticsKit"
keep = {"AnalyticsKit_vers.o"}
keep.update(path.with_suffix(".o").name for path in sources.rglob("*.swift"))

info = subprocess.check_output(["lipo", "-info", str(binary)], text=True)
fat = "Non-fat file" not in info
archs = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()

def extract_and_filter(archive_path, dest_archive):
    with tempfile.TemporaryDirectory() as extracted:
        subprocess.check_call(["ar", "x", str(archive_path)], cwd=extracted)
        objects = []
        for name in sorted(keep):
            obj = pathlib.Path(extracted) / name
            if not obj.is_file():
                raise SystemExit(f"Missing object {name} in {archive_path}")
            objects.append(str(obj))
        subprocess.check_call(["libtool", "-static", "-o", str(dest_archive), *objects])

with tempfile.TemporaryDirectory() as tmp:
    tmp_path = pathlib.Path(tmp)
    filtered = []
    for arch in archs:
        thin = tmp_path / f"{arch}.a"
        if fat:
            subprocess.check_call(["lipo", str(binary), "-thin", arch, "-output", str(thin)])
        else:
            shutil.copy2(binary, thin)
        out = tmp_path / f"filtered-{arch}.a"
        extract_and_filter(thin, out)
        filtered.append(out)
    if len(filtered) == 1:
        shutil.copy2(filtered[0], binary)
    else:
        subprocess.check_call(["lipo", "-create", *[str(path) for path in filtered], "-output", str(binary)])
PY
}

archive "generic/platform=iOS" ios
archive "generic/platform=iOS Simulator" sim

ios_fw="build/ios.xcarchive/Products/Library/Frameworks/AnalyticsKit.framework"
sim_fw="build/sim.xcarchive/Products/Library/Frameworks/AnalyticsKit.framework"

[[ -d "$ios_fw" ]] || { echo "Missing device framework at $ios_fw"; exit 1; }
[[ -d "$sim_fw" ]] || { echo "Missing simulator framework at $sim_fw"; exit 1; }

strip_foreign_objects "$ios_fw"
strip_foreign_objects "$sim_fw"

xcodebuild -create-xcframework \
  -framework "$ios_fw" \
  -framework "$sim_fw" \
  -allow-internal-distribution \
  -output build/AnalyticsKit.xcframework

(cd build && zip -qry AnalyticsKit.xcframework.zip AnalyticsKit.xcframework)
xcrun swift package compute-checksum build/AnalyticsKit.xcframework.zip
