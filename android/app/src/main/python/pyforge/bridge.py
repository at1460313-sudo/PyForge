"""pyforge.bridge — Python half of the PyForge native bridge.

Every public function returns a JSON string so results cross the
method channel losslessly. Execution is serialized by the Kotlin side
onto a single worker thread.

The ``_BRIDGE`` object is the Kotlin ``PythonBridge.PyCallbacks`` instance.
"""
import io
import json
import os
import sys
import traceback

_BRIDGE = None
# Absolute path of the user file currently executing (used to attribute errors).
_CURRENT_USER_FILE = None


def configure(callbacks):
    """Called once from Kotlin with the callbacks object."""
    global _BRIDGE
    _BRIDGE = callbacks


# ---------------------------------------------------------------------------
# Exceptions used for control flow
# ---------------------------------------------------------------------------

class _Cancelled(Exception):
    """Raised when the user presses Stop (cooperative cancellation)."""


class _StopDebug(Exception):
    """Raised to unwind out of a debugged program when the user stops it."""


# ---------------------------------------------------------------------------
# Stream redirection: live output + input() support + Stop checks
# ---------------------------------------------------------------------------

class _OutputStream(io.TextIOBase):
    """Forwards writes to Flutter as they happen; aborts on Stop."""

    def __init__(self, run_id, name):
        super().__init__()
        self._run_id = run_id
        self._name = name

    def writable(self):
        return True

    def write(self, text):
        if not text:
            return 0
        if _BRIDGE is not None and _BRIDGE.isCancelled():
            raise _Cancelled()
        if _BRIDGE is not None:
            _BRIDGE.onOutput(self._run_id, self._name, text)
        return len(text)

    def flush(self):
        pass


class _InputStream(io.TextIOBase):
    """``input()`` support: forwards the request to Flutter and blocks."""

    def __init__(self, run_id):
        super().__init__()
        self._run_id = run_id

    def readable(self):
        return True

    def readline(self, size=-1):
        if _BRIDGE is None:
            return "\n"
        if _BRIDGE.isCancelled():
            raise _Cancelled()
        text = _BRIDGE.requestInput(self._run_id, "")
        if not text.endswith("\n"):
            text += "\n"
        return text

    def read(self, size=-1):
        return self.readline()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _safe_locals_json(frame_locals):
    """Snapshot of visible variables (repr'd, bounded) for the explorer."""
    out = {}
    try:
        items = list(frame_locals.items())
    except Exception:
        items = []
    for key, value in items:
        if isinstance(key, str) and key.startswith("__"):
            continue
        try:
            rendered = repr(value)
        except Exception:
            rendered = "<unreprable>"
        out[str(key)] = rendered[:300]
    return json.dumps(out)


def _error_payload():
    exc_type, exc_value, exc_tb = sys.exc_info()
    user_line = None
    tb_cur = exc_tb
    while tb_cur is not None:
        filename = tb_cur.tb_frame.f_code.co_filename
        if _CURRENT_USER_FILE and os.path.abspath(filename) == _CURRENT_USER_FILE:
            user_line = tb_cur.tb_lineno
        tb_cur = tb_cur.tb_next
    return {
        "type": exc_type.__name__ if exc_type else "Error",
        "message": str(exc_value),
        "line": user_line,
        "traceback": "".join(traceback.format_exception(exc_type, exc_value, exc_tb)).strip(),
    }


def _prepare_namespace(file_path):
    directory = os.path.dirname(os.path.abspath(file_path))
    if directory and os.path.isdir(directory):
        try:
            os.chdir(directory)
        except OSError:
            pass
        if directory not in sys.path:
            sys.path.insert(0, directory)
    return {
        "__name__": "__main__",
        "__file__": file_path,
        "__builtins__": __builtins__,
    }


def _restore(old_streams, old_cwd):
    sys.stdout, sys.stderr, sys.stdin = old_streams
    try:
        os.chdir(old_cwd)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# checkSyntax (Error Lens)
# ---------------------------------------------------------------------------

def check_syntax(source):
    """Compile-only check. Returns line/column/message for the editor."""
    try:
        compile(source, "<editor>", "exec")
        return json.dumps({"ok": True})
    except SyntaxError as exc:
        return json.dumps({
            "ok": False,
            "line": exc.lineno or 1,
            "column": max(exc.offset or 1, 1),
            "message": exc.msg or "invalid syntax",
            "text": (exc.text or "").rstrip("\n"),
        })
    except ValueError as exc:  # e.g. source with null bytes
        return json.dumps({"ok": False, "line": 1, "column": 1,
                          "message": str(exc), "text": ""})


def _make_cancel_tracer():
    """A minimal sys.settrace tracer whose only job is Stop: it raises
    _Cancelled at the next line event, so even a `while True: pass` loop
    can be interrupted. Line-traced execution is somewhat slower than a
    plain run — acceptable for a learner's scripts."""
    def local(frame, event, arg):
        if event == "line" and _BRIDGE is not None and _BRIDGE.isCancelled():
            raise _Cancelled()
        return local

    def global_tracer(frame, event, arg):
        if _BRIDGE is not None and _BRIDGE.isCancelled():
            raise _Cancelled()
        return local

    return global_tracer


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

def run_code(run_id, file_path, source):
    """Execute user code with live output streaming and input() support."""
    global _CURRENT_USER_FILE
    _CURRENT_USER_FILE = os.path.abspath(file_path)
    old_streams = (sys.stdout, sys.stderr, sys.stdin)
    old_cwd = os.getcwd()
    result = {"ok": True}
    user_globals = _prepare_namespace(file_path)
    try:
        sys.stdout = _OutputStream(run_id, "stdout")
        sys.stderr = _OutputStream(run_id, "stderr")
        sys.stdin = _InputStream(run_id)
        code = compile(source, file_path, "exec")
        sys.settrace(_make_cancel_tracer())
        try:
            exec(code, user_globals)
        finally:
            sys.settrace(None)
    except _Cancelled:
        result["cancelled"] = True
    except SystemExit as exc:
        code_value = exc.code
        result["exitCode"] = 0 if code_value is None else int(code_value or 1)
    except BaseException:
        result["ok"] = False
        result["error"] = _error_payload()
    finally:
        _restore(old_streams, old_cwd)
        _CURRENT_USER_FILE = None
    return json.dumps(result)


# ---------------------------------------------------------------------------
# Debug (genuine pause/step/continue via sys.settrace)
# ---------------------------------------------------------------------------

def debug_run(run_id, file_path, source, breakpoints_json):
    """Run under the tracer. Pauses genuinely block the Python worker
    until Flutter sends Step / Continue / Stop."""
    global _CURRENT_USER_FILE
    _CURRENT_USER_FILE = os.path.abspath(file_path)
    target = os.path.abspath(file_path)
    breakpoints = set()
    try:
        breakpoints = {int(b) for b in json.loads(str(breakpoints_json))}
    except Exception:
        breakpoints = set()

    old_streams = (sys.stdout, sys.stderr, sys.stdin)
    old_cwd = os.getcwd()
    state = {"mode": "step"}  # "step" | "continue"
    result = {"ok": True}
    user_globals = _prepare_namespace(file_path)

    def local_tracer(frame, event, arg):
        if event != "line":
            return local_tracer
        if _BRIDGE is not None and _BRIDGE.isCancelled():
            raise _StopDebug()
        pause = False
        if state["mode"] == "step":
            pause = True
        elif frame.f_lineno in breakpoints:
            pause = True
        elif _BRIDGE is not None and _BRIDGE.consumePauseRequest():
            pause = True
        if pause:
            command = _BRIDGE.debugPause(run_id, frame.f_lineno,
                                         _safe_locals_json(frame.f_locals))
            if command == 1:
                state["mode"] = "step"
            elif command == 2:
                state["mode"] = "continue"
            else:
                raise _StopDebug()
        return local_tracer

    def global_tracer(frame, event, arg):
        if _BRIDGE is not None and _BRIDGE.isCancelled():
            raise _StopDebug()
        if event == "call" and os.path.abspath(frame.f_code.co_filename) == target:
            return local_tracer
        return None

    try:
        sys.stdout = _OutputStream(run_id, "stdout")
        sys.stderr = _OutputStream(run_id, "stderr")
        sys.stdin = _InputStream(run_id)
        code = compile(source, file_path, "exec")
        sys.settrace(global_tracer)
        try:
            exec(code, user_globals)
        finally:
            sys.settrace(None)
    except _Cancelled:
        result["cancelled"] = True
    except _StopDebug:
        result["ok"] = True
        result["stoppedByUser"] = True
    except SystemExit as exc:
        code_value = exc.code
        result["exitCode"] = 0 if code_value is None else int(code_value or 1)
    except BaseException:
        result["ok"] = False
        result["error"] = _error_payload()
    finally:
        sys.settrace(None)
        _restore(old_streams, old_cwd)
        _CURRENT_USER_FILE = None
    return json.dumps(result)


# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------

def list_packages():
    """All distributions visible to the embedded interpreter."""
    from importlib import metadata
    packages = []
    try:
        for dist in metadata.distributions():
            name = dist.metadata["Name"]
            if name:
                packages.append({"name": name, "version": dist.version or "?"})
    except Exception:
        pass
    packages.sort(key=lambda p: p["name"].lower())
    return json.dumps({"ok": True, "packages": packages})


def try_install_package(name):
    """Attempt a runtime pip install. Chaquopy bundles packages at *build*
    time; a runtime pip is not guaranteed to exist, so failures are reported
    honestly with a pointer to the build-time path."""
    try:
        # Already importable under its likely module name?
        import importlib
        module_name = name.split("[")[0].replace("-", "_")
        try:
            importlib.import_module(module_name)
            return json.dumps({
                "ok": True,
                "alreadyAvailable": True,
                "message": f"{name} is already available in this build.",
            })
        except ImportError:
            pass
    except Exception:
        pass

    try:
        import pip  # noqa: F401
    except ImportError:
        return json.dumps({
            "ok": False,
            "reason": "runtime_pip_unavailable",
            "message": (
                "This build of the app does not include pip at runtime. "
                "Chaquopy bundles packages when the APK is built: add "
                "install(\"%s\") to the chaquopy block in "
                "android/app/build.gradle and rebuild (see README > Packages)."
            ) % name,
        })

    try:
        from pip._internal.commands import create_command
        command = create_command("install")
        status = command.main(["--quiet", name])
        if status == 0:
            return json.dumps({"ok": True, "message": f"Installed {name}."})
        return json.dumps({
            "ok": False,
            "message": f"pip exited with status {status} while installing {name}.",
        })
    except Exception as exc:  # pragma: no cover - depends on device
        return json.dumps({
            "ok": False,
            "message": f"Runtime install failed ({exc}). Use the build-time "
                       "pip block in android/app/build.gradle instead.",
        })


# ---------------------------------------------------------------------------
# Curriculum challenge checking (isolated namespace + captured stdout)
# ---------------------------------------------------------------------------

def challenge_check(challenge_id, source, test_code):
    """Executes the learner's submission, then the challenge's tests."""
    buffer = io.StringIO()
    user_ns = {"__name__": "__main__"}
    try:
        code = compile(source, "<submission>", "exec")
        old_stdout, old_stderr = sys.stdout, sys.stderr
        sys.stdout = buffer
        sys.stderr = buffer
        try:
            exec(code, user_ns)
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr
    except BaseException:
        return json.dumps({
            "ok": False,
            "stage": "run",
            "error": _error_payload(),
        })

    test_ns = dict(user_ns)
    try:
        exec(compile(test_code, "<tests>", "exec"), test_ns)
    except SyntaxError as exc:
        return json.dumps({
            "ok": False,
            "stage": "tests",
            "error": {"type": "TestError", "message": str(exc), "line": None,
                      "traceback": ""},
        })

    test_names = sorted(
        k for k in test_ns
        if k.startswith("test_") and callable(test_ns[k])
    )
    results = []
    for test_name in test_names:
        try:
            test_ns[test_name]()
            results.append({"name": test_name, "passed": True})
        except AssertionError as exc:
            results.append({
                "name": test_name,
                "passed": False,
                "message": str(exc) or "assertion failed",
            })
        except BaseException as exc:
            results.append({
                "name": test_name,
                "passed": False,
                "message": f"{type(exc).__name__}: {exc}",
            })
    return json.dumps({
        "ok": True,
        "results": results,
        "stdout": buffer.getvalue()[-2000:],
    })


# ---------------------------------------------------------------------------
# Git (dulwich — pure-Python Git; optional dependency)
# ---------------------------------------------------------------------------

def git_init(repo_path):
    try:
        from dulwich.repo import Repo
    except ImportError:
        return json.dumps({"ok": False, "reason": "dulwich_not_installed",
                           "message": "The dulwich package is not bundled. "
                                      "See README > Version control."})
    try:
        if not os.path.isdir(os.path.join(repo_path, ".git")):
            Repo.init(repo_path)
        return json.dumps({"ok": True, "initialized": True})
    except Exception as exc:
        return json.dumps({"ok": False, "message": str(exc)})


def git_status(repo_path):
    try:
        from dulwich import porcelain
    except ImportError:
        return json.dumps({"ok": False, "reason": "dulwich_not_installed"})
    try:
        status = porcelain.status(repo_path)
        def _names(entries):
            names = []
            for entry in entries:
                if isinstance(entry, (tuple, list)):
                    names.append(entry[0].decode()
                                 if isinstance(entry[0], bytes) else str(entry[0]))
                else:
                    names.append(entry.decode() if isinstance(entry, bytes) else str(entry))
            return names
        return json.dumps({
            "ok": True,
            "staged": _names(status.staged.get("add", []))
                     + _names(status.staged.get("modify", [])),
            "modified": _names(status.unstaged),
            "untracked": _names(status.untracked),
        })
    except Exception as exc:
        return json.dumps({"ok": False, "message": str(exc)})


def git_commit(repo_path, message, author_name, author_email):
    try:
        from dulwich import porcelain
    except ImportError:
        return json.dumps({"ok": False, "reason": "dulwich_not_installed"})
    try:
        repo_dir = repo_path
        # Stage everything in the workspace.
        porcelain.add(repo_dir, paths=[repo_dir])
        author = f"{author_name} <{author_email}>"
        sha = porcelain.commit(repo_dir, message=message,
                               author=author, committer=author)
        return json.dumps({"ok": True, "sha": sha.decode()
                          if isinstance(sha, bytes) else str(sha)})
    except Exception as exc:
        return json.dumps({"ok": False, "message": str(exc)})


def git_push(repo_path, remote_url, username, token):
    """HTTPS push. Credentials are injected into an in-memory URL only —
    they are never written to the repository config or disk."""
    try:
        from dulwich import porcelain
    except ImportError:
        return json.dumps({"ok": False, "reason": "dulwich_not_installed"})
    if not remote_url.startswith("https://"):
        return json.dumps({
            "ok": False,
            "message": "Only HTTPS remotes are supported "
                       "(got a non-https URL).",
        })
    try:
        authed_url = remote_url
        if username or token:
            host_part = remote_url[len("https://"):]
            authed_url = f"https://{username}:{token}@{host_part}"
        # Push the current branch's HEAD ref.
        from dulwich.repo import Repo
        with Repo(repo_path) as repo:
            refs = repo.get_refs()
            branch = None
            for ref in refs:
                if ref.startswith(b"refs/heads/"):
                    branch = ref.decode()
                    break
            if branch is None:
                return json.dumps({"ok": False,
                                   "message": "No commits yet — commit first."})
            porcelain.push(repo_path, remote_location=authed_url,
                           refspecs=[branch])
        return json.dumps({"ok": True})
    except Exception as exc:
        return json.dumps({"ok": False, "message": str(exc)})
