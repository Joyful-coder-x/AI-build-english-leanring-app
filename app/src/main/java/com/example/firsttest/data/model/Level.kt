package com.example.firsttest.data.model

data class Level(
    val number: Int,
    val title: String,
    val bandScore: Double,
    val isUnlocked: Boolean,
    val isCompleted: Boolean = false,
    val bestAccuracy: Float = 0f,
    val bestStarRating: Int = 0,
    val completedSessionCount: Int = 0,
    val isComingSoon: Boolean = false,
)
