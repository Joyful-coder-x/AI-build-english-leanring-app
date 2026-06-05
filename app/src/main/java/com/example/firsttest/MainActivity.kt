package com.example.firsttest

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.example.firsttest.ui.navigation.MainScreen
import com.example.firsttest.ui.theme.KuaKuaTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            KuaKuaTheme {
                MainScreen()
            }
        }
    }
}
