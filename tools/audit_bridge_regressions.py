#!/usr/bin/env python3
"""Regression tests for PyForge commit 3153d80.

Copy to PyForge/tools/audit_bridge_regressions.py, then run:
    python3 tools/audit_bridge_regressions.py

These assert desired behavior, so failures on the reviewed commit are expected.
Optional Git tests require dulwich==0.22.1. No network requests or pushes occur.
"""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
PYTHON_ROOT = ROOT / 'android/app/src/main/python'
if not PYTHON_ROOT.exists():
    raise SystemExit('Copy this file into the repository tools/ directory first.')
sys.path.insert(0, str(PYTHON_ROOT))
from pyforge import bridge


class Callbacks:
    def __init__(self):
        self.outputs = []
        self.calls = 0

    def isCancelled(self):
        return False

    def consumePauseRequest(self):
        return False

    def onOutput(self, run_id, stream, text):
        self.outputs.append((stream, text))
        self.calls += 1

    def requestInput(self, run_id, prompt):
        return 'Ada'

    def debugPause(self, run_id, line, locals_json):
        return 2


class BridgeRegressions(unittest.TestCase):
    def setUp(self):
        self.callbacks = Callbacks()
        bridge.configure(self.callbacks)
        self.path_before = list(sys.path)

    def tearDown(self):
        sys.path[:] = self.path_before

    def test_string_exit_is_serialized_instead_of_raising(self):
        for debug in (False, True):
            with self.subTest(debug=debug):
                if debug:
                    raw = bridge.debug_run('exit', '/tmp/example.py',
                                           "raise SystemExit('goodbye')", '[]')
                else:
                    raw = bridge.run_code('exit', '/tmp/example.py',
                                          "raise SystemExit('goodbye')")
                result = json.loads(raw)
                self.assertEqual(result['exitCode'], 1)

    def test_output_is_coalesced_not_flooded(self):
        # 100 prints must not become 100+ method-channel messages.
        bridge._OUTPUT_FLUSH_SECONDS = 0.5  # keep the whole run in one batch
        try:
            self.callbacks.outputs.clear()
            self.callbacks.calls = 0
            bridge.run_code('flood', '/tmp/flood.py',
                            'for i in range(100):\n    print(i)')
            # Everything is still delivered (flushed before the result).
            text = ''.join(t for _, t in self.callbacks.outputs)
            self.assertIn('99', text)
            self.assertLess(self.callbacks.calls, 20)
        finally:
            bridge._OUTPUT_FLUSH_SECONDS = 0.05

    def test_large_writes_flush_immediately(self):
        # Above the byte cap, no waiting for the timer.
        bridge._OUTPUT_FLUSH_SECONDS = 30  # would hang if the cap is broken
        try:
            self.callbacks.outputs.clear()
            self.callbacks.calls = 0
            bridge.run_code('big', '/tmp/big.py',
                            'for i in range(2000):\n'
                            '    print("x" * 20)')
            text = ''.join(t for _, t in self.callbacks.outputs)
            self.assertEqual(len(text), 2000 * 21)
        finally:
            bridge._OUTPUT_FLUSH_SECONDS = 0.05

    def test_cancel_still_interrupts_between_flushes(self):
        # The Stop check must stay per-write, not per-batch.
        self.callbacks.stop_after = 5

        class StopAfter(Callbacks):
            def isCancelled(self):
                self.stop_after -= 1
                return self.stop_after < 0

        stop = StopAfter()
        stop.stop_after = 5
        bridge.configure(stop)
        result = json.loads(bridge.run_code('stop', '/tmp/s.py',
                                            'while True:\n    print("y")'))
        self.assertTrue(result.get('cancelled'))

    def test_pip_options_are_rejected(self):
        for bad in ('--index-url=http://evil.example', '-r reqs.txt',
                    'requests; os.system("x")', '', 'pkg name'):
            result = json.loads(bridge.try_install_package(bad))
            self.assertFalse(result['ok'], bad)

    def test_pip_names_are_accepted(self):
        for good in ('requests', 'requests==2.31.0', 'numpy',
                     'package-with-dash', 'pkg[extra1,extra2]'):
            result = json.loads(bridge.try_install_package(good))
            # ok=False is fine (no runtime pip on host); it must not be a
            # validation rejection.
            self.assertNotIn('not a valid package name',
                              result.get('message', ''), good)

    def test_syntax_error_has_user_line(self):
        result = json.loads(bridge.run_code('syntax', '/tmp/example.py',
                                            'x = 1\nif x\n    pass\n'))
        self.assertFalse(result['ok'])
        self.assertEqual(result['error']['line'], 2)

    def test_sys_path_is_restored_after_run(self):
        with tempfile.TemporaryDirectory() as directory:
            before = list(sys.path)
            bridge.run_code('path', directory + '/main.py', 'x = 1')
            self.assertEqual(sys.path, before)

    def test_helper_changes_are_seen_on_rerun(self):
        with tempfile.TemporaryDirectory() as directory:
            module = 'audit_helper_' + Path(directory).name.replace('-', '_')
            helper = Path(directory) / (module + '.py')
            # Different sizes prevent timestamp/size bytecode caching ambiguity.
            helper.write_text('VALUE = 1\n')
            program = f'import {module}\nprint({module}.VALUE)'
            bridge.run_code('first', directory + '/main.py', program)
            helper.write_text('VALUE = 222222\n')
            self.callbacks.outputs.clear()
            try:
                bridge.run_code('second', directory + '/main.py', program)
                output = ''.join(text for _, text in self.callbacks.outputs)
                self.assertEqual(output, '222222\n')
            finally:
                sys.modules.pop(module, None)

    def test_infinite_loop_in_challenge_is_aborted(self):
        # Runs in a subprocess so a hang cannot freeze this test runner.
        program = f'''
import sys, json
sys.path.insert(0, {str(PYTHON_ROOT)!r})
from pyforge import bridge
class Idle:
    def isCancelled(self): return False
bridge.configure(Idle())
if hasattr(bridge, 'CHALLENGE_TIME_LIMIT_SECONDS'):
    bridge.CHALLENGE_TIME_LIMIT_SECONDS = 0.3
result = json.loads(bridge.challenge_check('hang', 'while True: pass', 'def test_one(): pass'))
assert result['ok'] is False, result
'''
        try:
            completed = subprocess.run([sys.executable, '-c', program],
                                       capture_output=True, timeout=1.5)
        except subprocess.TimeoutExpired:
            self.fail('challenge_check hangs forever on an infinite loop')
        self.assertEqual(completed.returncode, 0, completed.stderr.decode())

    def test_output_from_tested_function_is_captured(self):
        outside = io.StringIO()
        with contextlib.redirect_stdout(outside):
            result = json.loads(bridge.challenge_check(
                'capture', 'def greet():\n    print("hello")\n',
                'def test_greet():\n    greet()\n'))
        self.assertEqual(result['stdout'], 'hello\n')
        self.assertEqual(outside.getvalue(), '')

    def test_test_setup_errors_return_json(self):
        result = json.loads(bridge.challenge_check(
            'setup', 'x = 1', "raise ValueError('bad test setup')"))
        self.assertFalse(result['ok'])
        self.assertEqual(result['stage'], 'tests')

    def test_cancel_cannot_be_swallowed_by_except_exception(self):
        program = f'''
import sys
sys.path.insert(0, {str(PYTHON_ROOT)!r})
from pyforge import bridge
class Cancel:
    count = 0
    def isCancelled(self):
        self.count += 1
        return self.count > 20
    def onOutput(self, *a): pass
bridge.configure(Cancel())
bridge.run_code('cancel', '/tmp/program.py',
    'try:\\n    while True:\\n        x = 1\\nexcept Exception:\\n    while True:\\n        x = 2\\n')
'''
        try:
            completed = subprocess.run([sys.executable, '-c', program],
                                       capture_output=True, timeout=1.5)
        except subprocess.TimeoutExpired:
            self.fail('except Exception swallowed cancellation; trace was disabled')
        self.assertEqual(completed.returncode, 0, completed.stderr.decode())


try:
    import dulwich
except ImportError:
    dulwich = None


@unittest.skipIf(dulwich is None, 'Optional: install dulwich==0.22.1')
class GitRegressions(unittest.TestCase):
    def test_commit_contains_workspace_files(self):
        from dulwich.repo import Repo
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'a.py').write_text('print(1)\n')
            Path(directory, 'nested').mkdir()
            Path(directory, 'nested', 'b.py').write_text('x = 1\n')
            self.assertTrue(json.loads(bridge.git_init(directory))['ok'])
            result = json.loads(bridge.git_commit(directory, 'test', 'Audit', 'audit@example.test'))
            self.assertTrue(result['ok'], result)
            with Repo(directory) as repo:
                commit = repo[repo.head()]
                root = repo[commit.tree]
                names = {entry.path for entry in root.items()}
                self.assertIn(b'a.py', names)
                self.assertIn(b'nested', names)

    def test_push_uses_current_branch_not_arbitrary_first_ref(self):
        from dulwich.repo import Repo
        from dulwich import porcelain
        with tempfile.TemporaryDirectory() as directory:
            Repo.init(directory).close()
            Path(directory, 'a.py').write_text('print(1)\n')
            porcelain.add(directory, paths=[str(Path(directory, 'a.py'))])
            porcelain.commit(directory, message=b'test', author=b'Audit <audit@example.test>')
            with Repo(directory) as repo:
                repo.refs[b'refs/heads/other'] = repo.head()
                order = [ref for ref in repo.get_refs() if ref.startswith(b'refs/heads/')]
                current = order[1]
                repo.refs.set_symbolic_ref(b'HEAD', current)
            # Intercept the push; no socket is opened and no remote is changed.
            with patch('dulwich.porcelain.push') as push:
                result = json.loads(bridge.git_push(directory,
                    'https://example.test/repo.git', '', ''))
                self.assertTrue(result['ok'], result)
                self.assertEqual(push.call_args.kwargs['refspecs'], [current.decode()])


if __name__ == '__main__':
    unittest.main(verbosity=2)
