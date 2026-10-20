package com.pyforge.ide

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * The single hop between Flutter and the embedded CPython runtime.
 *
 * Channels:
 *  - "pyforge/bridge" : Dart -> Kotlin commands (run, debug, git, packages...)
 *  - "pyforge/events" : Kotlin -> Dart events (output, debugger pauses, input requests)
 *
 * All Python work is serialized onto one background thread: the CPython
 * interpreter is process-global and not safe for concurrent use.
 *
 * Debugger contract (no deadlocks):
 *  - The Python worker blocks inside [PyCallbacks.debugPause] while Flutter
 *    shows the variable explorer.
 *  - Step / Continue / Stop arrive on the *main* thread via the bridge
 *    channel and merely release the worker. They never queue behind it.
 */
class PythonBridge(private val activity: Activity, engine: FlutterEngine) {

    companion object {
        const val BRIDGE_CHANNEL = "pyforge/bridge"
        const val EVENTS_CHANNEL = "pyforge/events"

        // Debugger commands returned to Python.
        const val DEBUG_STEP = 1
        const val DEBUG_CONTINUE = 2
        const val DEBUG_STOP = 3
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pythonExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private val eventsChannel = MethodChannel(
        engine.dartExecutor.binaryMessenger, EVENTS_CHANNEL
    )
    private val bridgeChannel = MethodChannel(
        engine.dartExecutor.binaryMessenger, BRIDGE_CHANNEL
    )

    // ---- Cross-thread coordination state ----

    // Explicit lock + condition objects (Object.wait/notify are not
    // exposed on Kotlin Any).
    private val inputLock = ReentrantLock()
    private val inputIdle = inputLock.newCondition()

    /** Debugger handoff: Python waits, main thread releases with a command. */
    private val debugLock = ReentrantLock()
    private val debugIdle = debugLock.newCondition()

    @Volatile private var pendingInput: String? = null
    @Volatile private var debugCommand: Int = 0

    @Volatile private var cancelRequested = false
    @Volatile private var pauseRequested = false

    /** Java callbacks object handed to Python; Python invokes these directly. */
    private val pyCallbacks = PyCallbacks()

    init {
        bridgeChannel.setMethodCallHandler { call, result ->
            handleCall(call.method, call.arguments, result)
        }
    }

    fun dispose() {
        bridgeChannel.setMethodCallHandler(null)
        cancelRequested = true
        releaseBlockedWorkers()
        pythonExecutor.shutdown()
    }

    // ---------------------------------------------------------------------
    // Dart -> Kotlin command handling (main thread; must stay quick).
    // ---------------------------------------------------------------------

    private fun handleCall(method: String, arguments: Any?, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = (arguments as? Map<String, Any?>) ?: emptyMap()

        when (method) {
            "ping" -> result.success("pong")

            "checkSyntax" -> onPythonThread(result) { mod ->
                mod.callAttr("check_syntax", args["source"] as String).toString()
            }

            "runCode" -> {
                cancelRequested = false
                onPythonThread(result) { mod ->
                    mod.callAttr(
                        "run_code",
                        args["runId"] as String,
                        args["filePath"] as String,
                        args["source"] as String
                    ).toString()
                }
            }

            "stopRun" -> {
                cancelRequested = true
                releaseBlockedWorkers()
                result.success(true)
            }

            "submitInput" -> {
                inputLock.withLock {
                    pendingInput = args["text"] as? String ?: ""
                    inputIdle.signalAll()
                }
                result.success(true)
            }

            "debugRun" -> {
                cancelRequested = false
                pauseRequested = false
                val breakpoints = (args["breakpoints"] as? List<*>)?.map { (it as Number).toInt() }
                    ?: emptyList()
                onPythonThread(result) { mod ->
                    mod.callAttr(
                        "debug_run",
                        args["runId"] as String,
                        args["filePath"] as String,
                        args["source"] as String,
                        JSONArray(breakpoints)
                    ).toString()
                }
            }

            "debugStep" -> releaseDebugger(DEBUG_STEP, result)
            "debugContinue" -> releaseDebugger(DEBUG_CONTINUE, result)
            "debugStop" -> {
                cancelRequested = true
                releaseDebugger(DEBUG_STOP, result)
            }
            "debugPause" -> {
                pauseRequested = true
                result.success(true)
            }

            "listPackages" -> onPythonThread(result) { mod ->
                mod.callAttr("list_packages").toString()
            }

            "tryInstallPackage" -> onPythonThread(result) { mod ->
                mod.callAttr("try_install_package", args["name"] as String).toString()
            }

            "challengeCheck" -> onPythonThread(result) { mod ->
                mod.callAttr(
                    "challenge_check",
                    args["challengeId"] as String,
                    args["source"] as String,
                    args["testCode"] as String
                ).toString()
            }

            "gitInit" -> onPythonThread(result) { mod ->
                mod.callAttr("git_init", args["repoPath"] as String).toString()
            }

            "gitStatus" -> onPythonThread(result) { mod ->
                mod.callAttr("git_status", args["repoPath"] as String).toString()
            }

            "gitCommit" -> onPythonThread(result) { mod ->
                mod.callAttr(
                    "git_commit",
                    args["repoPath"] as String,
                    args["message"] as String,
                    args["authorName"] as String,
                    args["authorEmail"] as String
                ).toString()
            }

            "gitPush" -> onPythonThread(result) { mod ->
                mod.callAttr(
                    "git_push",
                    args["repoPath"] as String,
                    args["remoteUrl"] as String,
                    args["username"] as String,
                    args["token"] as String
                ).toString()
            }

            else -> result.notImplemented()
        }
    }

    private fun releaseDebugger(command: Int, result: MethodChannel.Result) {
        debugLock.withLock {
            debugCommand = command
            debugIdle.signalAll()
        }
        result.success(true)
    }

    /** Releases anything blocked on input/debug locks (used by Stop). */
    private fun releaseBlockedWorkers() {
        inputLock.withLock { inputIdle.signalAll() }
        debugLock.withLock { debugIdle.signalAll() }
    }

    // ---------------------------------------------------------------------
    // Python invocation
    // ---------------------------------------------------------------------

    private fun onPythonThread(
        result: MethodChannel.Result,
        body: (PyObject) -> String
    ) {
        pythonExecutor.execute {
            val reply = try {
                val mod = bridgeModule()
                body(mod)
            } catch (t: Throwable) {
                jsonError(t.message ?: t.javaClass.simpleName)
            }
            mainHandler.post { result.success(reply) }
        }
    }

    private fun bridgeModule(): PyObject {
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(activity))
        }
        val py = Python.getInstance()
        val mod = py.getModule("pyforge.bridge")
        // Re-run configure on every fetch: cheap, and guarantees the
        // callbacks object matches the current Flutter engine (the module
        // outlives activity recreations).
        mod.callAttr("configure", pyCallbacks)
        PyForgeApp.bridgeModule = mod
        return mod
    }

    private fun jsonError(message: String): String =
        JSONObject().put("ok", false).put("error", message).toString()

    // ---------------------------------------------------------------------
    // Callbacks invoked *by Python* (on the Python worker thread).
    // ---------------------------------------------------------------------

    inner class PyCallbacks {

        /** Streamed stdout/stderr (also used for live program output). */
        fun onOutput(runId: String, stream: String, text: String) {
            postEvent(
                "output",
                JSONObject()
                    .put("runId", runId)
                    .put("stream", stream)
                    .put("text", text)
            )
        }

        /** Terminal-style input() support: ask Flutter, block until answered. */
        fun requestInput(runId: String, prompt: String): String {
            postEvent(
                "input_request",
                JSONObject().put("runId", runId).put("prompt", prompt)
            )
            inputLock.withLock {
                while (pendingInput == null && !cancelRequested) {
                    inputIdle.await(250, java.util.concurrent.TimeUnit.MILLISECONDS)
                }
                val value = pendingInput
                pendingInput = null
                return value ?: "" // Stop pressed: feed EOF-like empty input.
            }
        }

        /**
         * Debugger pause. The wait state is established BEFORE the event is
         * published, so a Step that races in between can never be lost —
         * the wait loop re-checks the command and returns immediately.
         */
        fun debugPause(runId: String, line: Int, localsJson: String): Int {
            debugLock.withLock {
                debugCommand = 0
            }
            postEvent(
                "debug_pause",
                JSONObject()
                    .put("runId", runId)
                    .put("line", line)
                    .put("locals", localsJson)
            )
            debugLock.withLock {
                while (debugCommand == 0 && !cancelRequested) {
                    debugIdle.await(250, java.util.concurrent.TimeUnit.MILLISECONDS)
                }
                val cmd = if (debugCommand == 0) DEBUG_STOP else debugCommand
                debugCommand = 0
                return cmd
            }
        }

        /** Whether the user pressed Pause while running in continue-mode. */
        fun consumePauseRequest(): Boolean {
            val value = pauseRequested
            pauseRequested = false
            return value
        }

        /** Whether the user pressed Stop (checked at safe points). */
        fun isCancelled(): Boolean = cancelRequested
    }

    private fun postEvent(type: String, payload: JSONObject) {
        payload.put("type", type)
        mainHandler.post { eventsChannel.invokeMethod("onEvent", payload.toString()) }
    }
}
