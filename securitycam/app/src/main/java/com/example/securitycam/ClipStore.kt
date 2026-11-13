package com.example.securitycam

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 録画クリップの保存先と容量管理。
 *
 * 容量超過時は「古いファイルをまるごと削除」する。
 * 別の撮影タイミングのファイルを途中から上書き・切り詰めることはしない。
 */
class ClipStore(ctx: Context) {
    val dir: File = File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "clips").also { it.mkdirs() }

    fun newFile(): File {
        val name = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        return File(dir, "clip_$name.mp4")
    }

    /** 古い順(撮影日時順)のクリップ一覧。ファイル名が日時なので名前順 = 古い順。 */
    fun clips(): List<File> =
        dir.listFiles { f -> f.isFile && f.name.endsWith(".mp4") }?.sortedBy { it.name } ?: emptyList()

    fun totalBytes(): Long = clips().sumOf { it.length() }

    fun lastClipBytes(): Long = clips().lastOrNull()?.length() ?: 0L

    /**
     * 合計が [maxBytes] 以下になるまで、古いファイルから削除する。
     * 最新の1本は(単体で上限を超えていても)残す。
     */
    fun trim(maxBytes: Long) {
        val list = clips().toMutableList()
        var total = list.sumOf { it.length() }
        while (total > maxBytes && list.size > 1) {
            val oldest = list.removeAt(0)
            total -= oldest.length()
            oldest.delete()
        }
    }
}
