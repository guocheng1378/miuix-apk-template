package top.yukonga.miuixapptemplate

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 沉浸式：内容延伸到状态栏/导航栏之下（X4）
        enableEdgeToEdge()
        setContent {
            App(prefs = SharedPreferencesAppPrefs(this))
        }
    }
}
