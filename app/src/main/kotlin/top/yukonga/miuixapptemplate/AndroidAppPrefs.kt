package top.yukonga.miuixapptemplate

import android.content.Context
import android.content.SharedPreferences

/**
 * [AppPrefs] 的 Android 实现，基于 SharedPreferences（同步读写，无需挂起）。
 * 仅在模板当前编译目标（Android）下使用。
 */
class SharedPreferencesAppPrefs(context: Context) : AppPrefs {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("miuix_template_prefs", Context.MODE_PRIVATE)

    override var themeMode: Int
        get() = prefs.getInt(KEY_THEME_MODE, 0)
        set(value) = prefs.edit().putInt(KEY_THEME_MODE, value).apply()

    override var keyColorIndex: Int
        get() = prefs.getInt(KEY_KEY_COLOR, 0)
        set(value) = prefs.edit().putInt(KEY_KEY_COLOR, value).apply()

    override var notificationsEnabled: Boolean
        get() = prefs.getBoolean(KEY_NOTIFICATIONS, false)
        set(value) = prefs.edit().putBoolean(KEY_NOTIFICATIONS, value).apply()

    private companion object {
        const val KEY_THEME_MODE = "themeMode"
        const val KEY_KEY_COLOR = "keyColorIndex"
        const val KEY_NOTIFICATIONS = "notificationsEnabled"
    }
}
