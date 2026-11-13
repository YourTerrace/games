package com.example.securitycam

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.RadioButton
import android.widget.Spinner
import android.widget.TextView
import androidx.core.content.ContextCompat

class MainActivity : Activity() {

    private lateinit var radioFront: RadioButton
    private lateinit var radioBack: RadioButton
    private lateinit var qualitySpinner: Spinner
    private lateinit var intervalEdit: EditText
    private lateinit var clipEdit: EditText
    private lateinit var maxMbEdit: EditText
    private lateinit var autoStartCheck: CheckBox
    private lateinit var toggleButton: Button
    private lateinit var statusText: TextView
    private lateinit var store: ClipStore

    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            refreshStatus()
            handler.postDelayed(this, 2_000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        store = ClipStore(this)

        radioFront = findViewById(R.id.radioFront)
        radioBack = findViewById(R.id.radioBack)
        qualitySpinner = findViewById(R.id.qualitySpinner)
        intervalEdit = findViewById(R.id.intervalEdit)
        clipEdit = findViewById(R.id.clipEdit)
        maxMbEdit = findViewById(R.id.maxMbEdit)
        autoStartCheck = findViewById(R.id.autoStartCheck)
        toggleButton = findViewById(R.id.toggleButton)
        statusText = findViewById(R.id.statusText)

        qualitySpinner.adapter = ArrayAdapter.createFromResource(
            this, R.array.qualities, android.R.layout.simple_spinner_dropdown_item,
        )

        val cfg = Prefs.load(this)
        radioFront.isChecked = cfg.useFront
        radioBack.isChecked = !cfg.useFront
        qualitySpinner.setSelection(cfg.qualityIndex)
        intervalEdit.setText(cfg.intervalMin.toString())
        clipEdit.setText(cfg.clipSec.toString())
        maxMbEdit.setText(cfg.maxMb.toString())
        autoStartCheck.isChecked = cfg.autoStart

        toggleButton.setOnClickListener {
            if (RecorderService.running) stopRecording() else startRecording()
        }

        if (cfg.autoStart && !RecorderService.running) startRecording()
    }

    override fun onResume() {
        super.onResume()
        handler.post(ticker)
    }

    override fun onPause() {
        handler.removeCallbacks(ticker)
        saveConfig()
        super.onPause()
    }

    private fun readConfig() = Config(
        useFront = radioFront.isChecked,
        qualityIndex = qualitySpinner.selectedItemPosition.coerceAtLeast(0),
        intervalMin = (intervalEdit.text.toString().toIntOrNull() ?: 5).coerceAtLeast(1),
        clipSec = (clipEdit.text.toString().toIntOrNull() ?: 10).coerceAtLeast(1),
        maxMb = (maxMbEdit.text.toString().toIntOrNull() ?: 2000).coerceAtLeast(10),
        autoStart = autoStartCheck.isChecked,
    )

    private fun saveConfig() = Prefs.save(this, readConfig())

    private fun startRecording() {
        val needed = buildList {
            add(Manifest.permission.CAMERA)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }
        val missing = needed.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            requestPermissions(missing.toTypedArray(), REQ_PERM)
            return
        }
        saveConfig()
        ContextCompat.startForegroundService(this, Intent(this, RecorderService::class.java))
        handler.postDelayed({ refreshStatus() }, 500)
    }

    private fun stopRecording() {
        stopService(Intent(this, RecorderService::class.java))
        handler.postDelayed({ refreshStatus() }, 500)
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, perms, results)
        if (code != REQ_PERM) return
        // 通知の許可が無くても録画自体は動くので、カメラ許可だけを必須にする
        val camIdx = perms.indexOf(Manifest.permission.CAMERA)
        if (camIdx >= 0 && results[camIdx] == PackageManager.PERMISSION_GRANTED) startRecording()
    }

    private fun refreshStatus() {
        toggleButton.text = if (RecorderService.running) "停止" else "開始"
        val mb = store.totalBytes() / (1024.0 * 1024.0)
        statusText.text = buildString {
            append(if (RecorderService.running) "状態: 録画中\n" else "状態: 停止中\n")
            append("保存済み: ${store.clips().size} 本 / %.1f MB\n".format(mb))
            append("保存先: ${store.dir.absolutePath}")
        }
    }

    companion object {
        private const val REQ_PERM = 100
    }
}
