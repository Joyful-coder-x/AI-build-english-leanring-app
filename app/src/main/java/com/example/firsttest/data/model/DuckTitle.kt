package com.example.firsttest.data.model

/**
 * 鸭力称号 — a title awarded based on the user's total 鸭力值 (duckPower / EXP).
 * Source: spec 2.4.2 积分系统.
 */
enum class DuckTitle(val displayName: String, val minDuckPower: Int) {
    BEGINNER("初学鸭", 0),
    HARD_WORKING("努力鸭", 500),
    PROGRESSING("进步鸭", 2_000),
    SKILLED("熟练鸭", 5_000),
    SUPER("超级鸭", 10_000),
    EXCELLENT("卓越鸭", 20_000),
    INVINCIBLE("无敌鸭", 50_000),
    MASTER("大师鸭", 100_000);

    companion object {
        /** The highest title whose threshold the given [duckPower] reaches. */
        fun forDuckPower(duckPower: Int): DuckTitle =
            entries.last { duckPower >= it.minDuckPower }
    }
}
