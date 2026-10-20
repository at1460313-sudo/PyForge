"""pyforge.bridge — Python half of the PyForge native bridge.

Every public function returns a JSON string so results cross the
method channel losslessly. Execution is serialized by the Kotlin side
onto a single worker thread.

The ``_BRIDGE`` object is the Kotlin ``PythonBridge.PyCallbacks`` instance.
"""
import importlib
import io
import re
import json
import os
import sys
import time
import threading
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

class _Cancelled(BaseException):
    """Raised when the user presses Stop (cooperative cancellation)."""


class _StopDebug(BaseException):
    """Raised to unwind out of a debugged program when the user stops it."""


# ---------------------------------------------------------------------------
# Stream redirection: live output + input() support + Stop checks
# ---------------------------------------------------------------------------

# Batching: every print() is two write() calls, and each one used to be its
# own method-channel message to the main thread. A loop of 100k prints would
# flood the UI (including the Stop button) with events. Writes are now
# coalesced: sent at most ~20x per second, or immediately once the buffer
# grows past _OUTPUT_FLUSH_BYTES. flush() always forces a send.
_OUTPUT_FLUSH_SECONDS = 0.05
_OUTPUT_FLUSH_BYTES = 16384


class _OutputStream(io.TextIOBase):
    """Forwards writes to Flutter in batches; aborts on Stop."""

    def __init__(self, run_id, name):
        super().__init__()
        self._run_id = run_id
        self._name = name
        self._parts = []
        self._buffered = 0
        self._timer = None
        self._lock = threading.Lock()

    def writable(self):
        return True

    def write(self, text):
        if not text:
            return 0
        if _BRIDGE is not None and _BRIDGE.isCancelled():
            raise _Cancelled()
        with self._lock:
            self._parts.append(text)
            self._buffered += len(text)
            if self._buffered >= _OUTPUT_FLUSH_BYTES:
                self._send_locked()
            elif self._timer is None:
                self._timer = threading.Timer(
                    _OUTPUT_FLUSH_SECONDS, self._flush)
                self._timer.daemon = True
                self._timer.start()
        return len(text)

    def _send_locked(self):
        if self._timer is not None:
            self._timer.cancel()
            self._timer = None
        text = "".join(self._parts)
        self._parts = []
        self._buffered = 0
        if text and _BRIDGE is not None:
            _BRIDGE.onOutput(self._run_id, self._name, text)

    def _flush(self):
        with self._lock:
            self._send_locked()

    def flush(self):
        self._flush()

    def close(self):
        try:
            self._flush()
        finally:
            super().close()


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
    if (isinstance(exc_value, SyntaxError) and exc_value.lineno
            and _CURRENT_USER_FILE
            and os.path.abspath(exc_value.filename or "") == _CURRENT_USER_FILE):
        user_line = exc_value.lineno
    # Hide this module's own frame (exec(...) call) from learner-facing tracebacks.
    shown_tb = exc_tb
    while shown_tb is not None and shown_tb.tb_frame.f_code.co_filename == __file__:
        shown_tb = shown_tb.tb_next
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
        "traceback": "".join(traceback.format_exception(exc_type, exc_value, shown_tb)).strip(),
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


def _snapshot():
    """State that a user program can pollute and that must be undone."""
    importlib.invalidate_caches()  # pick up files created since the last run
    return list(sys.path), set(sys.modules)


def _restore(old_streams, old_cwd, snapshot=None, workspace_dir=None):
    sys.stdout, sys.stderr, sys.stdin = old_streams
    try:
        os.chdir(old_cwd)
    except OSError:
        pass
    if snapshot is not None:
        old_path, old_modules = snapshot
        sys.path[:] = old_path
        # Forget modules imported from the workspace so edits to helper files
        # are picked up on the next run (Python would otherwise reuse the
        # stale cached module object).
        root = os.path.abspath(workspace_dir) if workspace_dir else None
        for name in set(sys.modules) - old_modules:
            mod = sys.modules.get(name)
            mod_file = getattr(mod, "__file__", None)
            if root and mod_file and os.path.abspath(mod_file).startswith(root + os.sep):
                sys.modules.pop(name, None)


def _flush_streams():
    """Send any batched output before the real streams are swapped back in,
    so everything a program printed is on screen before its result is."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.flush()
        except Exception:
            pass


def _exit_code(value):
    """Map SystemExit.code to a process-style integer (never raises)."""
    if value is None:
        return 0
    if isinstance(value, int):
        return value
    return 1  # sys.exit("message") exits with status 1 (message goes to stderr)


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
    snapshot = _snapshot()
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
        _report_exit_message(exc)
        result["exitCode"] = _exit_code(exc.code)
    except BaseException:
        result["ok"] = False
        result["error"] = _error_payload()
    finally:
        _flush_streams()
        _restore(old_streams, old_cwd, snapshot, os.path.dirname(_CURRENT_USER_FILE))
        _CURRENT_USER_FILE = None
    return json.dumps(result)


def _report_exit_message(exc):
    """sys.exit("text") prints text to stderr, exactly like the real interpreter."""
    if exc.code is not None and not isinstance(exc.code, int):
        try:
            print(exc.code, file=sys.stderr)
        except BaseException:
            pass


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
    snapshot = _snapshot()
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
        _report_exit_message(exc)
        result["exitCode"] = _exit_code(exc.code)
    except BaseException:
        result["ok"] = False
        result["error"] = _error_payload()
    finally:
        sys.settrace(None)
        _flush_streams()
        _restore(old_streams, old_cwd, snapshot, os.path.dirname(target))
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


# Whitelist for pip arguments: a PEP 508-ish name, optional extras, and an
# optional ==version pin. Anything else (notably anything starting with "-",
# like --index-url or -r) is a pip *option*, not a package, and must never
# reach pip.
_PACKAGE_RE = re.compile(
    r"^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?"
    r"(\[[A-Za-z0-9,._-]+\])?"
    r"(==[A-Za-z0-9.+!_-]+)?$"
)


def try_install_package(name):
    """Attempt a runtime pip install. Chaquopy bundles packages at *build*
    time; a runtime pip is not guaranteed to exist, so failures are reported
    honestly with a pointer to the build-time path."""
    name = (name or "").strip()
    if not _PACKAGE_RE.match(name):
        return json.dumps({
            "ok": False,
            "message": f"{name!r} is not a valid package name "
                      f"(name or name==version).",
        })
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

CHALLENGE_TIME_LIMIT_SECONDS = 10


def _make_deadline_tracer(seconds):
    """Aborts runaway code (e.g. `while True`) after `seconds`, so one bad
    submission cannot freeze the single Python worker thread for the rest of
    the session. Deliberately ignores the Stop flag: that flag stays set after
    a Stop until the next Run, which would instantly fail the next check."""
    deadline = time.monotonic() + seconds

    def expired():
        return time.monotonic() > deadline

    def local(frame, event, arg):
        if event == "line" and expired():
            raise _Cancelled()
        return local

    def global_tracer(frame, event, arg):
        if expired():
            raise _Cancelled()
        return local

    return global_tracer


def challenge_check(challenge_id, source, test_code):
    """Executes the learner's submission, then the challenge's tests."""
    buffer = io.StringIO()
    user_ns = {"__name__": "__main__"}
    old_streams = (sys.stdout, sys.stderr, sys.stdin)
    snapshot = _snapshot()

    def timed_out():
        return json.dumps({
            "ok": False,
            "stage": "run",
            "error": {"type": "TimeoutError",
                      "message": "Your code ran for too long (infinite loop?).",
                      "line": None, "traceback": ""},
        })

    try:
        # Keep output of the submission AND of the tests away from the real
        # stdout, and make input() fail fast instead of blocking the worker.
        sys.stdout = buffer
        sys.stderr = buffer
        sys.stdin = io.StringIO("")
        sys.settrace(_make_deadline_tracer(CHALLENGE_TIME_LIMIT_SECONDS))
        try:
            try:
                code = compile(source, "<submission>", "exec")
                exec(code, user_ns)
            except _Cancelled:
                return timed_out()
            except SystemExit:
                pass  # a submission calling exit() is not a crash
            except BaseException:
                return json.dumps({"ok": False, "stage": "run",
                                   "error": _error_payload()})

            test_ns = dict(user_ns)
            try:
                exec(compile(test_code, "<tests>", "exec"), test_ns)
            except BaseException as exc:  # syntax OR runtime error in test setup
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
                except _Cancelled:
                    return timed_out()
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
        finally:
            sys.settrace(None)
        return json.dumps({
            "ok": True,
            "results": results,
            "stdout": buffer.getvalue()[-2000:],
        })
    finally:
        _restore(old_streams, os.getcwd(), snapshot, None)


# ---------------------------------------------------------------------------
# Git (dulwich — pure-Python Git; optional dependency)
# ---------------------------------------------------------------------------

_DEFAULT_GITIGNORE = "__pycache__/\n*.pyc\n.DS_Store\n"


def _import_dulwich():
    try:
        from dulwich import porcelain  # noqa: F401
        return True
    except ImportError:
        return False


def _redact(text, *secrets):
    """Never let a token travel back to the UI inside an error message."""
    text = str(text)
    for secret in secrets:
        if secret:
            text = text.replace(secret, "***")
    return text


def git_init(repo_path):
    try:
        from dulwich.repo import Repo
    except ImportError:
        return json.dumps({"ok": False, "reason": "dulwich_not_installed",
                           "message": "The dulwich package is not bundled. "
                                      "See README > Version control."})
    try:
        if not os.path.isdir(os.path.join(repo_path, ".git")):
            Repo.init(repo_path).close()
        ignore = os.path.join(repo_path, ".gitignore")
        if not os.path.exists(ignore):
            with open(ignore, "w", encoding="utf-8") as handle:
                handle.write(_DEFAULT_GITIGNORE)
        return json.dumps({"ok": True, "initialized": True})
    except Exception as exc:
        return json.dumps({"ok": False, "message": str(exc)})


def git_status(repo_path):
    if not _import_dulwich():
        return json.dumps({"ok": False, "reason": "dulwich_not_installed"})
    from dulwich import porcelain
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
                     + _names(status.staged.get("modify", []))
                     + _names(status.staged.get("delete", [])),
            "modified": _names(status.unstaged),
            "untracked": _names(status.untracked),
        })
    except Exception as exc:
        return json.dumps({"ok": False, "message": str(exc)})


def _stage_everything(repo_path):
    """Stage new + changed + deleted files, honouring .gitignore.

    `porcelain.add(repo, paths=[repo_path])` is NOT equivalent: dulwich turns
    that into the pseudo-path "./", which stages nothing, so commits were
    silently empty."""
    from dulwich.ignore import IgnoreFilterManager
    from dulwich.repo import Repo
    with Repo(repo_path) as repo:
        ignores = IgnoreFilterManager.from_repo(repo)
        wanted = []
        for directory, dirnames, filenames in os.walk(repo_path):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for filename in filenames:
                rel = os.path.relpath(os.path.join(directory, filename), repo_path)
                rel = rel.replace(os.sep, "/")
                if not ignores.is_ignored(rel):
                    wanted.append(rel)
        # Files that are tracked but gone from disk must be staged as deletions.
        index = repo.open_index()
        wanted += [k.decode() for k in index
                   if not os.path.exists(os.path.join(repo_path, k.decode()))]
        repo.stage(wanted)


def git_commit(repo_path, message, author_name, author_email):
    if not _import_dulwich():
        return json.dumps({"ok": False, "reason": "dulwich_not_installed"})
    from dulwich import porcelain
    try:
        _stage_everything(repo_path)
        author = f"{author_name} <{author_email}>".encode()
        sha = porcelain.commit(repo_path, message=message.encode(),
                               author=author, committer=author)
        return json.dumps({"ok": True, "sha": sha.decode()
                          if isinstance(sha, bytes) else str(sha)})
    except Exception as exc:
        return json.dumps({"ok": False, "message": str(exc)})


def git_push(repo_path, remote_url, username, token):
    """HTTPS push. Credentials are passed to dulwich as arguments (never
    spliced into the URL, so special characters are safe) and are never
    written to the repository config or disk."""
    if not _import_dulwich():
        return json.dumps({"ok": False, "reason": "dulwich_not_installed"})
    from dulwich import porcelain
    if not remote_url.startswith("https://"):
        return json.dumps({
            "ok": False,
            "message": "Only HTTPS remotes are supported "
                       "(got a non-https URL).",
        })
    try:
        from dulwich.repo import Repo
        with Repo(repo_path) as repo:
            try:
                head_target = repo.refs.follow(b"HEAD")[0][-1]
            except Exception:
                head_target = None
            if not head_target or not head_target.startswith(b"refs/heads/") \
                    or head_target not in repo.refs:
                return json.dumps({"ok": False,
                                   "message": "No commits yet — commit first."})
            branch = head_target.decode()
        kwargs = {}
        if username or token:
            kwargs["username"] = username or token
            kwargs["password"] = token or ""
        porcelain.push(repo_path, remote_location=remote_url,
                       refspecs=[branch], **kwargs)
        return json.dumps({"ok": True})
    except Exception as exc:
        return json.dumps({"ok": False, "message": _redact(exc, token, username)})
