package com.example.k_e_commerce

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    // F07: the channels FCM pushes name (see supabase/functions/_shared/fcm.ts).
    // Rider job alerts get their own channel so riders can give it a louder
    // sound without changing everything else.
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                "k_default",
                getString(R.string.channel_default),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        manager.createNotificationChannel(
            NotificationChannel(
                "k_jobs",
                getString(R.string.channel_jobs),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }
}
