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

    /**
     * 本次朗读的**最后一段** utteranceId（形如 `reader-auto-work-3#7`）。
     *
     * 为什么存完整 id 而不是「最后一段的下标」：旧写法拿「最后一段下标」当开关，
     * 还要求它大于 0；而**单段朗读的最后一段下标就是 0**，
     * 于是单段朗读永远不通知 Dart。
     * 阅读器一页通常不到 1200 字，正好都走单段分支 → 一页念完既不高亮复位、
     * 也不接下一页，表现就是「连续朗读读完一页就停了」。
     */
    private var lastUtteranceId: String? = null

    /** 当前选中的语音包名（null = 引擎默认）。 */
    private var voiceName: String? = null

    /** 音调，供「温柔女声 / 广播员男声」等风格预设使用。 */
    private var pitch = 1.0f

    /**
     * 暂停状态的存档（Android 的 TextToSpeech 没有 pause/resume，只能停引擎重念）。
     *
     * 做法：暂停时停掉引擎，把「当前这一段还没念完的原文」存起来；
     * 继续时用同一个 id 从这段开头接着念（引擎只能按段停，做不到按字续）。
     */
    private var pausedText: String? = null
    private var pausedId: String? = null

    /** 最近一次 speak 的分段与进度，暂停时据此算出剩余的原文。 */
    private var speakingChunks: List<String> = emptyList()
    private var speakingIndex = 0
    private var currentRate = 1.0f

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
                    // 先把「等哪一段」清掉：engine.stop() 之后可能还有迟到的 onDone，
                    // 不清会让它去通知一个已经被停掉的任务，把连续朗读错接回去。
                    lastUtteranceId = null
                    clearPaused()
                    tts?.stop()
                    result.success(null)
                }
                "pause" -> {
                    // 停引擎但记住「当前这段还没念完的原文」，继续时从这里接上。
                    // 必须先清 lastUtteranceId：stop() 之后若有迟到的 onDone，
                    // 不清就会误报「这一页念完了」，连续朗读在暂停中自己翻页。
                    val id = lastUtteranceId?.substringBeforeLast('#')
                    if (id != null && speakingChunks.isNotEmpty()) {
                        val from = speakingIndex.coerceIn(0, speakingChunks.size - 1)
                        pausedText = speakingChunks.drop(from).joinToString("")
                        pausedId = id
                        lastUtteranceId = null
                        tts?.stop()
                    }
                    result.success(null)
                }
                "resume" -> {
                    val text = pausedText
                    val id = pausedId
                    clearPaused()
                    if (text.isNullOrBlank() || id == null) {
                        // 没存档（或本来就没在念）：什么都不做，由 Dart 侧自行处理
                        result.success(null)
                    } else {
                        result.success(speakNow(text, id, currentRate))
                    }
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
                    override fun onStart(utteranceId: String?) {
                        // 记下正在念第几段：暂停时据此算出剩余原文。
                        val idx = utteranceId?.substringAfterLast('#', "")?.toIntOrNull()
                        if (idx != null) speakingIndex = idx
                    }

                    override fun onDone(utteranceId: String?) {
                        // 只有「最后一段」播完才通知 Dart，避免逐段熄灭/重亮。
                        // 单段朗读的 id 就是 `...#0`，用完整 id 比对可以一并覆盖。
                        val expected = lastUtteranceId ?: return
                        if (utteranceId != expected) return
                        lastUtteranceId = null
                        notifyDone(expected)
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        notifyFailed(utteranceId)
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        notifyFailed(utteranceId)
                    }
                })
                ready = true
            }
            onReady()
        }
    }

    /**
     * 告诉 Dart「这条朗读任务结束了」。
     *
     * 必须回主线程：UtteranceProgressListener 的回调跑在引擎的 binder 线程，
     * 而 MethodChannel.invokeMethod 要求在主线程调用。
     */
    private fun notifyDone(utteranceId: String) {
        val id = utteranceId.substringBeforeLast('#')
        runOnUiThread { channel?.invokeMethod("done", id) }
    }

    /** 引擎报错：只有错在「当前这条任务」上才收尾，别让上一条的残余错误把新的一页掐掉。 */
    private fun notifyFailed(utteranceId: String?) {
        val expected = lastUtteranceId ?: return
        if (utteranceId == null) return
        if (utteranceId.substringBeforeLast('#') != expected.substringBeforeLast('#')) return
        lastUtteranceId = null
        notifyDone(expected)
    }

    private fun speakNow(text: String, id: String, rate: Float): Boolean {
        val engine = tts ?: return false
        return try {
            engine.stop()
            clearPaused()
            currentRate = if (rate <= 0f) 1.0f else rate
            engine.setSpeechRate(currentRate)
            // 音调范围 [0.5, 2.0]；越界会被引擎静默忽略，这里夹一下更保险
            engine.setPitch(pitch.coerceIn(0.5f, 2.0f))
            val chunks = splitForTts(text)
            if (chunks.isEmpty()) {
                lastUtteranceId = null
                speakingChunks = emptyList()
                speakingIndex = 0
                return false
            }
            speakingChunks = chunks
            speakingIndex = 0
            lastUtteranceId = "$id#${chunks.size - 1}"
            val params = Bundle()
            for ((i, part) in chunks.withIndex()) {
                val mode = if (i == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
                engine.speak(part, mode, params, "$id#$i")
            }
            true
        } catch (e: Exception) {
            lastUtteranceId = null
            false
        }
    }

    /** 清掉暂停存档（新开一段朗读 / 停止 / 已续播后调用）。 */
    private fun clearPaused() {
        pausedText = null
        pausedId = null
    }

    /**
     * 按句读切段。
     *
     * 上限 200 字（远低于引擎 4000 字上限）是**为了暂停精度**：安卓引擎只能
     * 整段停，段越细，「继续朗读」就从越靠近暂停点的地方接上；段界一律落在
     * 句读处（。！？；换行），所以听起来仍是自然停顿，不会在句子中间断开。
     */
    private fun splitForTts(text: String): List<String> {
        val max = 200
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
