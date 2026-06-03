package com.example.firsttest

import com.example.firsttest.data.model.DuckTitle
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Example of our testing approach: unit-test the *logic*, not the UI.
 * Here we verify 鸭力称号 thresholds from spec 2.4.2.
 */
class DuckTitleTest {

    @Test
    fun zeroDuckPower_isBeginner() {
        assertEquals(DuckTitle.BEGINNER, DuckTitle.forDuckPower(0))
    }

    @Test
    fun prototypeUser_450_isBeginner() {
        assertEquals(DuckTitle.BEGINNER, DuckTitle.forDuckPower(450))
    }

    @Test
    fun exactThreshold_500_isHardWorking() {
        assertEquals(DuckTitle.HARD_WORKING, DuckTitle.forDuckPower(500))
    }

    @Test
    fun justBelowThreshold_1999_isHardWorking() {
        assertEquals(DuckTitle.HARD_WORKING, DuckTitle.forDuckPower(1_999))
    }

    @Test
    fun veryHighDuckPower_isMaster() {
        assertEquals(DuckTitle.MASTER, DuckTitle.forDuckPower(250_000))
    }
}
