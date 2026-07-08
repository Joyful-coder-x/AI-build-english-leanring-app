package com.example.firsttest.data.model

data class LevelWordStatus(
    val senseId: String,
    val word: String,
    val definitionZh: String,
    val status: String,
    val wrongCount: Int,
    val isDue: Boolean,
)
