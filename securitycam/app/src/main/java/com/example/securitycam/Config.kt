package com.example.securitycam

import android.content.Context
import androidx.camera.video.Quality

/** ユーザー設定。サービスは1回録画するたびに読み直すので、録画中に変更しても次回から反映される。 */
data class Config(
    val useFront: Boolean = false,
    val qualityIndex: Int = 1,      // 0=SD 1=HD 2=FHD 3=UHD
    val intervalMin: Int = 5,       // 録画開始から次の録画開始までの間隔(分)
    val clipSec: Int = 10,          // 1回の録画時間(秒)
    val maxMb: Int = 2000,          // クリップ保存に使う最大容量(MB)
    val autoStart: Boolean = true,  // アプリ起動時に自動開始
) {
    val quality: Quality
        get() = when (qualityIndex) {
            0 -> Quality.SD
            1 -> Quality.HD
            2 -> Quality.FHD
            else -> Quality.UHD
        }
    val maxBytes: Long get() = maxMb.toLong() * 1024 * 1024
}

object Prefs {
    private const val NAME = "securitycam"

    fun load(ctx: Context): Config {
        val p = ctx.getSharedPreferences(NAME, Context.MODE_PRIVATE)
        val d = Config()
        return Config(
            useFront = p.getBoolean("useFront", d.useFront),
            qualityIndex = p.getInt("quality", d.qualityIndex).coerceIn(0, 3),
            intervalMin = p.getInt("intervalMin", d.intervalMin).coerceAtLeast(1),
            clipSec = p.getInt("clipSec", d.clipSec).coerceAtLeast(1),
            maxMb = p.getInt("maxMb", d.maxMb).coerceAtLeast(10),
            autoStart = p.getBoolean("autoStart", d.autoStart),
        )
    }

    fun save(ctx: Context, c: Config) {
        ctx.getSharedPreferences(NAME, Context.MODE_PRIVATE).edit()
            .putBoolean("useFront", c.useFront)
            .putInt("quality", c.qualityIndex)
            .putInt("intervalMin", c.intervalMin)
            .putInt("clipSec", c.clipSec)
            .putInt("maxMb", c.maxMb)
            .putBoolean("autoStart", c.autoStart)
            .apply()
    }
}
