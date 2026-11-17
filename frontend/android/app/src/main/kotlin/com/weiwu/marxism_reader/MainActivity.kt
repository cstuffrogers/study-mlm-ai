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
 *   init     -> {ready: Boolean, chinese: Boolean, engine: String?, voice: String?}
 *   speak    -> 参数 {text: String, id: String, rate: Double, pitch: Double}，返回 Boolean（引擎是否接受）
 *   stop     -> null
 *   voices   -> {voices: [{name, label, locale, quality, network}], current: String?}
 *   setVoice -> 参数 {name: String}（空串 = 恢复引擎默认），返回 Boolean
 *
 * 「语音包设置」页（功能中心）靠 voices / setVoice 列出本机已装的中文语音并让用户挑选；
 * pitch 用于「温柔女声 / 广播员男声」这类风格预设（音色取决于装了哪些语音包，
 * 音调语速由 App 侧预设决定，见 lib/services/tts_settings.dart）。
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

    /** 当前选中的语音包名（null = 引擎默认）。 */
    private var voiceName: String? = null

    /** 音调，供「温柔女声 / 广播员男声」等风格预设使用。 */
    private var pitch = 1.0f

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
                    val pit = (call.argument<Double>("pitch") ?: 1.0).toFloat()
                    val id = call.argument<String>("id") ?: "__default__"
                    if (text.isBlank() || !ready) {
                        result.success(false)
                    } else {
                        pitch = pit
                        result.success(speakNow(text, id, rate))
                    }
                }
                "stop" -> {
                    tts?.stop()
                    result.success(null)
                }
                "voices" -> result.success(
                    mapOf(
                        "voices" to voiceList(),
                        "current" to voiceName,
                    )
                )
                "setVoice" -> {
                    val name = call.argument<String>("name") ?: ""
                    val ok = applyVoice(name)
                    if (ok) voiceName = name.ifBlank { null }
                    result.success(ok)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "ready" to ready,
        "chinese" to chinese,
        "engine" to tts?.engines?.firstOrNull()?.name,
        "voice" to voiceName,
    )

    /** 本机已装的中文语音包（引擎未就绪时返回空表，UI 自行提示）。 */
    private fun voiceList(): List<Map<String, Any?>> {
        val engine = tts ?: return emptyList()
        return try {
            engine.voices
                ?.filter { v ->
                    val lang = v.locale.language.lowercase()
                    lang == "zh" || lang == "cmn" || lang == "yue"
                }
                ?.map { v ->
                    // 中文引擎的语音名通常是 zh-cn-x-ccc-local / cmn-cn-x-ccc-local 这类内部名，
                    // 直接展示对用户没意义；label 只给语言 + 性别线索（引擎不给性别，就别编）。
                    mapOf(
                        "name" to v.name,
                        "locale" to v.locale.toLanguageTag(),
                        "label" to v.locale.displayName,
                        "quality" to v.quality,
                        "network" to v.isNetworkConnectionRequired,
                    )
                }
                ?.sortedWith(compareBy({ it["network"] == true }, { "${it["name"]}" }))
                ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** 切换语音包：空串 = 恢复引擎默认（setVoice(null)）。 */
    private fun applyVoice(name: String): Boolean {
        val engine = tts ?: return false
        return try {
            if (name.isBlank()) {
                engine.setVoice(null)
                true
            } else {
                val target = engine.voices?.firstOrNull { it.name == name } ?: return false
                engine.setVoice(target) == TextToSpeech.SUCCESS
            }
        } catch (_: Exception) {
            false
        }
    }

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
            // 音调范围 [0.5, 2.0]；越界会被引擎静默忽略，这里夹一下更保险
            engine.setPitch(pitch.coerceIn(0.5f, 2.0f))
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
