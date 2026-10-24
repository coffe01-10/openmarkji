package dev.openmarkji.openmarkji

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import java.util.Calendar

/** A daily local alarm. Counts are read at delivery, not cached when scheduled. */
object StudyReminders {
    private const val channelId = "study_reminders"
    private const val notificationId = 2101
    private const val alarmId = 2102
    const val alarmAction = "dev.openmarkji.openmarkji.STUDY_REMINDER"

    private fun preferences(context: Context) =
        context.getSharedPreferences("study_reminders", Context.MODE_PRIVATE)

    fun configure(context: Context, databasePath: String) {
        preferences(context).edit().putString("databasePath", databasePath).apply()
        sync(context)
    }

    private fun openDatabase(context: Context): SQLiteDatabase? {
        // There is no database path before this installation has opened its library.
        val path = preferences(context).getString("databasePath", null) ?: return null
        return SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
    }

    private fun config(database: SQLiteDatabase): JSONObject = database.rawQuery(
        "SELECT value FROM settings WHERE key='preferences'", null
    ).use { cursor ->
        if (cursor.moveToFirst()) JSONObject(cursor.getString(0)) else JSONObject()
    }

    private fun alarmIntent(context: Context) = PendingIntent.getBroadcast(
        context, alarmId,
        Intent(context, StudyReminderReceiver::class.java).setAction(alarmAction),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun schedule(context: Context, config: JSONObject) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val intent = alarmIntent(context)
        if (!config.optBoolean("studyReminder", false)) {
            manager.cancel(intent)
            NotificationManagerCompat.from(context).cancel(notificationId)
            return
        }
        val now = System.currentTimeMillis()
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, config.optInt("reminderHour", 20))
            set(Calendar.MINUTE, config.optInt("reminderMinute", 0))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now) add(Calendar.DAY_OF_YEAR, 1)
        }
        // A study reminder doesn't require exact-alarm permission or a foreground service.
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, intent)
    }

    fun sync(context: Context, deliver: Boolean = false) {
        openDatabase(context)?.use { database ->
            val settings = config(database)
            schedule(context, settings)
            if (deliver && settings.optBoolean("studyReminder", false)) {
                val count = pendingReviews(database)
                if (count > 0) post(context, count)
            }
        }
    }

    private fun pendingReviews(database: SQLiteDatabase): Int {
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val end = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
        // Matches prepareSession's due-review query, including overdue cards and
        // excluding cards already formally graded today. Shared cards count once.
        return database.rawQuery(
            """SELECT count(*) FROM cards c WHERE c.plan='active' AND c.due_at<?
                AND NOT EXISTS (SELECT 1 FROM reviews r WHERE r.card_id=c.id
                AND r.kind='formal' AND r.reviewed_at>=? AND r.reviewed_at<?)""",
            arrayOf(end.timeInMillis.toString(), start.timeInMillis.toString(), end.timeInMillis.toString())
        ).use { cursor -> cursor.moveToFirst(); cursor.getInt(0) }
    }

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "学习提醒", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "每天提醒未完成的到期复习"
                }
            )
        }
    }

    fun isAllowed(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context.getSystemService(NotificationManager::class.java)
                .getNotificationChannel(channelId)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun post(context: Context, count: Int): Boolean {
        createChannel(context)
        if (!isAllowed(context)) return false
        val open = PendingIntent.getActivity(
            context, notificationId,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_study_reminder)
            .setContentTitle("OpenMarkji · 学习提醒")
            .setContentText("今日待复习 $count 张")
            .setNumber(count)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(context).notify(notificationId, notification)
        return true
    }

    fun preview(context: Context): Boolean = openDatabase(context)?.use { database ->
        post(context, pendingReviews(database))
    } ?: false
}

class StudyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                StudyReminders.sync(context, deliver = intent.action == StudyReminders.alarmAction)
            } catch (error: Exception) {
                Log.e("StudyReminder", "Unable to restore or deliver learning reminder", error)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
