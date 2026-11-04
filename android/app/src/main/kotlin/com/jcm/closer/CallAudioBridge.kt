package com.jcm.closer

import android.os.Handler
import android.os.Looper
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.LocalAudioTrack
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.webrtc.AudioTrackSink
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/** Taps the existing WebRTC microphone. Never opens a second recorder or saves audio. */
class CallAudioBridge(messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var events: EventChannel.EventSink? = null
    @Volatile private var enabled = false
    private var track: LocalAudioTrack? = null
    private val pending = AtomicBoolean(false)
    private val packet = ByteArrayOutputStream(2560)
    private var accumulator = 0.0
    private var sum = 0.0
    private var count = 0
    private val sink = AudioTrackSink { buffer, bits, rate, channels, frames, _ ->
        if (enabled && bits == 16 && rate >= 16000 && channels > 0) {
            val input = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
            synchronized(packet) {
                repeat(minOf(frames, input.remaining() / (channels * 2))) {
                    var mono = 0.0
                    repeat(channels) { mono += input.short.toDouble() }
                    sum += mono / channels
                    count++
                    accumulator += 16000.0
                    if (accumulator >= rate) {
                        accumulator -= rate
                        val sample = (sum / count).toInt().coerceIn(-32768,32767)
                        packet.write(sample and 255); packet.write((sample shr 8) and 255)
                        sum = 0.0; count = 0
                    }
                }
                if (packet.size() >= 2560) {
                    val bytes = packet.toByteArray(); packet.reset()
                    if (pending.compareAndSet(false,true)) main.post {
                        try { if (enabled) events?.success(bytes) } finally { pending.set(false) }
                    }
                }
            }
        }
    }
    init {
        EventChannel(messenger,"com.jcm.closer/call_pcm").setStreamHandler(this)
        MethodChannel(messenger,"com.jcm.closer/call_audio").setMethodCallHandler { call,result ->
            when(call.method) {
                "start" -> {
                    stop()
                    val id = call.argument<String>("trackId")
                    val local = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(id) as? LocalAudioTrack
                    if (local == null) result.error("no_microphone","Call microphone is unavailable",null)
                    else {
                        synchronized(packet) { packet.reset(); accumulator=0.0; sum=0.0; count=0 }
                        track=local; enabled=true; local.addSink(sink); result.success(null)
                    }
                }
                "stop" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun stop() { enabled=false; track?.removeSink(sink); track=null }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events=sink }
    override fun onCancel(arguments: Any?) { stop(); events=null }
}
