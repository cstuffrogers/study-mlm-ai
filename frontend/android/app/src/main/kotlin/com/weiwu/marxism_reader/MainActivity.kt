package com.weiwu.marxism_reader

import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * 安卓原生 TTS（系统 TextToSpeech 引擎，离线可用）。
 *
 * 通道：[xxmz/tts]
 *   init   -> {ready: Boolean, chinese: Boolean, engine: String?}
 *   speak  -> 参数 {text: String, id: String, rate: Double}，返回 Boolean（引擎是否接受）
 *   stop   -> null
 * 回调用 invokeMethod("done", id) 通知 Dart 侧朗读结束，用于熄灭喇叭高亮。
 *
 * 要点：
 *  · 单机版没有后端，朗读只能靠系统语音包，因此这条通道是「喇叭按钮」能否出现的关键；
 *  · 长文本按句读切段后 QUEUE_ADD 续播，避免超过引擎单次长度上限被截断；
 *  · 引擎初始化是异步的，未就绪时 speak 直接返回 false，Dart 侧不会卡在高亮状态。
 */
class MainActivity : FlutterActivity() {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var chinese = false
    private var channel: MethodChannel? = null
    private var lastChunkIndex = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xxmz/tts")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    ensureTts { result.success(statusMap()) }
                }
                "status" -> result.success(statusMap())
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                    val id = call.argument<String>("id") ?: "__default__"
                    if (text.isBlank() || !ready) {
                        result.success(false)
                    } else {
                        result.success(speakNow(text, id, rate))
                    }
                }
                "stop" -> {
                    tts?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "ready" to ready,
        "chinese" to chinese,
        "engine" to tts?.engines?.firstOrNull()?.name,
    )

    /** 惰性初始化；已就绪则立即回调。 */
    private fun ensureTts(onReady: () -> Unit) {
        if (ready) {
            onReady()
            return
        }
        if (tts != null) {
            // 初始化进行中：稍后再报状态（Dart 侧按钮已可见，多一次查询无副作用）
            onReady()
            return
        }
        tts = TextToSpeech(applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val engine = tts
                val zh = try {
                    val r = engine?.setLanguage(Locale.SIMPLIFIED_CHINESE)
                    r != TextToSpeech.LANG_MISSING_DATA && r != TextToSpeech.LANG_NOT_SUPPORTED
                } catch (_: Exception) {
                    false
                }
                chinese = zh
                if (!zh) {
                    // 没有中文语音包时退回系统默认语言，至少不会静音
                    try {
                        engine?.setLanguage(Locale.getDefault())
                    } catch (_: Exception) {
                    }
                }
                try {
                    engine?.setSpeechRate(1.0f)
                } catch (_: Exception) {
                }
                engine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) {
                        // 只有最后一段播完才通知 Dart，避免逐段熄灭/重亮
                        if (utteranceId != null && lastChunkIndex > 0 &&
                            utteranceId.endsWith("#$lastChunkIndex")
                        ) {
                            val id = utteranceId.substringBeforeLast('#')
                            channel?.invokeMethod("done", id)
                        }
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        if (utteranceId != null) {
                            channel?.invokeMethod("done", utteranceId.substringBeforeLast('#'))
                        }
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        if (utteranceId != null) {
                            channel?.invokeMethod("done", utteranceId.substringBeforeLast('#'))
                        }
                    }
                })
                ready = true
            }
            onReady()
        }
    }

    private fun speakNow(text: String, id: String, rate: Float): Boolean {
        val engine = tts ?: return false
        return try {
            engine.stop()
            engine.setSpeechRate(if (rate <= 0f) 1.0f else rate)
            val chunks = splitForTts(text)
            if (chunks.isEmpty()) return false
            lastChunkIndex = chunks.size - 1
            val params = Bundle()
            for ((i, part) in chunks.withIndex()) {
                val mode = if (i == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
                engine.speak(part, mode, params, "$id#$i")
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    /** 按句读切段：引擎单次上限约 4000 字，这里取 1200 字并在标点处断开，语气更自然。 */
    private fun splitForTts(text: String): List<String> {
        val max = 1200
        if (text.length <= max) return listOf(text)
        val out = ArrayList<String>()
        val sb = StringBuilder()
        for (ch in text) {
            sb.append(ch)
            val boundary = ch == '。' || ch == '！' || ch == '？' || ch == '；' || ch == '\n'
            if (sb.length >= max || (boundary && sb.length >= max / 3)) {
                out.add(sb.toString())
                sb.setLength(0)
            }
        }
        if (sb.isNotEmpty()) out.add(sb.toString())
        return out
    }

    override fun onDestroy() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        super.onDestroy()
    }
}
