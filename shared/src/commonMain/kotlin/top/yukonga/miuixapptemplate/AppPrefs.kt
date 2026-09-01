package top.yukonga.miuixapptemplate

/**
 * 跨平台应用偏好接口（KMP 干净接口，具体实现由各平台提供）。
 *
 * 解决"设置页选的主题/主题色/通知开关重启即丢失"的问题：UI 层只读写这个接口，
 * Android 侧用 SharedPreferences 同步持久化。值约定：
 * - [themeMode]: 0=跟随系统 1=浅色 2=深色 3=动态取色(Monet)
 * - [keyColorIndex]: 0=默认蓝，1..n 对应 [ui.KeyColors] 的索引
 * - [notificationsEnabled]: 通知开关
 */
interface AppPrefs {
    var themeMode: Int
    var keyColorIndex: Int
    var notificationsEnabled: Boolean
}
