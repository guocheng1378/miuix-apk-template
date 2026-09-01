package top.yukonga.miuixapptemplate

import kotlinx.serialization.Serializable
import top.yukonga.miuix.kmp.nav.core.NavKey

/**
 * 页面路由（miuix-nav 的 NavKey）。
 *
 * 顶层三个 tab + 一个带参数的详情页。`@Serializable` 是硬要求：
 * `rememberNavController` / `rememberNavBackStack` 靠它把返回栈跨配置变更/进程重建保存下来，
 * sealed 层级用闭式多态序列化，无需 SerializersModule。
 */
@Serializable
sealed interface Route : NavKey {
    @Serializable
    data object Home : Route

    @Serializable
    data object Image : Route

    @Serializable
    data object Settings : Route

    @Serializable
    data class Detail(val id: Int) : Route
}
