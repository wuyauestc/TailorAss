#!/usr/bin/env python3
"""Cheap shell/output-route contract; never compiles or repeats the 211 suite."""
from pathlib import Path
import os,shutil,subprocess,tempfile
script=Path(__file__).with_name('run-native-positive-clearance.sh')
subprocess.run(['sh','-n',str(script)],check=True)
source=script.read_text()
start=source.index('if [ -n "${GARMENTCODE_NATIVE_OUTPUT-}" ]')
end=source.index('export GARMENTCODE_NATIVE_OUTPUT="$output_dir"',start)+len('export GARMENTCODE_NATIVE_OUTPUT="$output_dir"')
block=source[start:end]+'\n[ "$output_dir" = "$GARMENTCODE_NATIVE_OUTPUT" ]\nexport GARMENTCODE_NATIVE_OUTPUT\nsh -c \'printf "%s" "$GARMENTCODE_NATIVE_OUTPUT"\'\n'
def route(value=None):
    env=dict(os.environ);env.pop('GARMENTCODE_NATIVE_OUTPUT',None)
    if value is not None:env['GARMENTCODE_NATIVE_OUTPUT']=value
    return subprocess.check_output(['sh','-eu','-c',block],env=env,text=True)
first,second=route(),route()
try:
    assert first!=second and Path(first).is_dir() and Path(second).is_dir()
    assert Path(first).name.startswith('TailorAssNativePositiveClearanceResults.')
    explicit='/private/tmp/explicit positive route with spaces'
    assert route(explicit)==explicit
finally:
    shutil.rmtree(first);shutil.rmtree(second)
print('PASS native positive output: shell syntax; unique default directories; same exported child route; explicit path preserved. No 211 rerun.')
