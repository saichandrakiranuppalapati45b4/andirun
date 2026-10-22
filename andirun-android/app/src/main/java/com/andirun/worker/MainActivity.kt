package com.andirun.worker

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import java.util.Timer
import java.util.TimerTask

class MainActivity : Activity() {
    private var isServiceRunning = false
    private var timer: Timer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Programmatic UI layout
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(40, 60, 40, 40)
        }

        val title = TextView(this).apply {
            text = "AndiRun: Android LLM Worker"
            textSize = 22f
            setPadding(0, 0, 0, 30)
        }
        layout.addView(title)

        val portInput = EditText(this).apply {
            hint = "Worker Port (default: 50060)"
            setText("50060")
        }
        layout.addView(portInput)

        val modelInput = EditText(this).apply {
            hint = "Tail GGUF Path"
            setText("/data/local/tmp/tail-L40.gguf")
        }
        layout.addView(modelInput)

        val statusView = TextView(this).apply {
            text = "Status: Idle"
            textSize = 16f
            setPadding(0, 30, 0, 30)
        }
        layout.addView(statusView)

        val toggleButton = Button(this).apply {
            text = "Start Co-Processor Service"
        }
        toggleButton.setOnClickListener {
            if (!isServiceRunning) {
                val intent = Intent(this, WorkerService::class.java).apply {
                    putExtra("PORT", portInput.text.toString().toIntOrNull() ?: 50060)
                    putExtra("MODEL_PATH", modelInput.text.toString())
                }
                startForegroundService(intent)
                isServiceRunning = true
                toggleButton.text = "Stop Co-Processor Service"

                timer = Timer().apply {
                    scheduleAtFixedRate(object : TimerTask() {
                        override fun run() {
                            runOnUiThread {
                                statusView.text = WorkerService.getWorkerStatus()
                            }
                        }
                    }, 1000, 1000)
                }
            } else {
                stopService(Intent(this, WorkerService::class.java))
                isServiceRunning = false
                toggleButton.text = "Start Co-Processor Service"
                timer?.cancel()
                statusView.text = "Status: Stopped"
            }
        }
        layout.addView(toggleButton)

        setContentView(layout)
    }

    override fun onDestroy() {
        super.onDestroy()
        timer?.cancel()
    }
}
