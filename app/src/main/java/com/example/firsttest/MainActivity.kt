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
                // Real app shell: 4-tab bottom navigation.
                // (The Supabase connectivity proof is kept in
                // ui/debug/SupabaseTestScreen.kt — not wired here. To run it
                // again temporarily, render SupabaseTestScreen() instead.)
                MainScreen()
            }
        }
    }
}
