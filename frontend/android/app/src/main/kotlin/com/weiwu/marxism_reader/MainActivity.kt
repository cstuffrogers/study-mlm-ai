package com.weiwu.marxism_reader

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/**
 * 安卓原生 TTS（系统 TextToSpeech 引擎，离线可用）。
 *
 * 通道：[xxmz/tts]
 *   init     -> {ready: Boolean, chinese: Boolean, engine: String?, voice: String?}
 *   speak    -> 参数 {text: String, id: String, rate: Double, pitch: Double}，返回 Boolean（引擎是否接受）
 *   stop     -> null
 *   voices   -> {voices: [{name, label, locale, quality, network, gender}], current: String?}
 *   setVoice -> 参数 {name: String}（空串 = 恢复引擎默认），返回 Boolean
 *
 * 「语音包设置」页（功能中心）靠 voices / setVoice 列出本机已装的中文语音并让用户挑选；
 * pitch 用于「温柔女声 / 广播员男声」这类风格预设（音色取决于装了哪些语音包，
 * 音调语速由 App 侧预设决定，见 lib/services/tts_settings.dart）。
 * 回调用 invokeMethod("done", id) 通知 Dart 侧朗读结束，用于熄灭喇叭高亮。
 *
 * 另一条通道 [xxmz/app]（应用内更新）：
 *   installApk -> 参数 {path: String}，返回 Boolean（是否成功唤起系统安装器）。
 *                 Android 7+ 只接受 content:// URI，这里用 FileProvider 转换；
 *                 见 AndroidManifest.xml 的 <provider> 与 res/xml/file_paths.xml。
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

        val appCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xxmz/app")
        appCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(installApk(path))
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 用 FileProvider 把缓存里的 APK 转成 content:// 再交给系统安装器。
     *
     * 三个易错点：
     *  · Android 7+ 直接给 file:// 会抛 FileUriExposedException —— 必须走 provider；
     *  · 必须带 FLAG_GRANT_READ_URI_PERMISSION，否则安装器读不到文件；
     *  · Android 8+ 还要 REQUEST_INSTALL_PACKAGES 权限 + 用户允许「安装未知应用」，
     *    缺权限时系统会抛 ActivityNotFoundException，这里兜住返回 false。
     */
    private fun installApk(path: String): Boolean {
        if (path.isBlank()) return false
        return try {
            val file = File(path)
            if (!file.exists() || file.length() == 0L) return false
            val uri: Uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
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
                    // 有的引擎把中文报成 und / zh-Hans / zh-Hant，只认 zh|cmn|yue 会整张表空掉
                    // （用户就会觉得「APP 里一个语音包都没有」）。这里放宽到语言标签包含中文。
                    val tag = v.locale.toLanguageTag().lowercase()
                    val lang = v.locale.language.lowercase()
                    lang == "zh" || lang == "cmn" || lang == "yue" ||
                        tag.startsWith("zh") || tag.contains("-cn") ||
                        tag.contains("hans") || tag.contains("hant")
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
                        // 引擎不提供性别时给 null，UI 显示「未知」——不猜、不编
                        "gender" to genderOf(v),  // 已是 null 或 male/female
                    )
                }
                ?.sortedWith(compareBy({ it["network"] == true }, { "${it["name"]}" }))
                ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    // ---------------- 语音性别标签（能查就标，查不到就「未知」，绝不按名字猜） ----------------
    //
    // 用户实报「APP 没有男声」：安卓只报一个 locale 显示名（都叫「中文」），
    // 实际可能有男女两套音色，界面上看起来就像只有一个。
    // Voice.getFeatures()（API 21+ 公开接口）在 Google 引擎里带 "gender=female|male"，
    // 有就标出来；国产引擎大多不给，就标「未知」，并由 App 侧用音调语速做近似。

    private val genderCache = HashMap<String, String>()

    private fun genderOf(voice: android.speech.tts.Voice): String? {
        val cached = genderCache[voice.name]
        if (cached != null) return cached.ifEmpty { null }
        val parsed = parseGender(voice)
        genderCache[voice.name] = parsed
        return parsed.ifEmpty { null }
    }

    /** 从 Voice.features 里取性别；取不到返回空串（= 引擎不提供）。 */
    private fun parseGender(voice: android.speech.tts.Voice): String {
        val features = try {
            voice.features
        } catch (_: Exception) {
            null
        } ?: return ""
        for (f in features) {
            val low = f.lowercase()
            if (!low.startsWith("gender")) continue
            val v = low.substringAfter("=", "").trim()
            if (v.startsWith("f")) return "female"
            if (v.startsWith("m")) return "male"
        }
        return ""
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
