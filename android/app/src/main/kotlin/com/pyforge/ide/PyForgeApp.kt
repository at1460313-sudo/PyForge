package com.pyforge.ide

import android.app.Application
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform

/**
 * Application entry point. Python is started once per process so that the
 * interpreter is warm by the time the user taps Run.
 */
class PyForgeApp : Application() {

    companion object {
        /** The pyforge.bridge Python module (reconfigured on each fetch). */
        @Volatile
        var bridgeModule: PyObject? = null
    }

    override fun onCreate() {
        super.onCreate()
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
    }
}
