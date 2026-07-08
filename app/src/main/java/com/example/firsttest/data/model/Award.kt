package com.example.firsttest.data.model

/** A badge granted for a login/level/band milestone. Source: masterplan Feature J. */
data class Award(
    val id: String,
    val nameZh: String,
    val descriptionZh: String?,
    val awardedAt: String,
)

/** A single newly-granted award returned by check_and_grant_awards(). */
data class NewAward(
    val id: String,
    val nameZh: String,
)
