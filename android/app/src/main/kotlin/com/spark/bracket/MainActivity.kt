package com.spark.bracket

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.View
import android.view.Surface
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.min

class MainActivity : FlutterActivity() {
    companion object {
        private const val MEDIA_ROUTE_CHANNEL = "bracket/media_route_picker"
        private const val ORIENTATION_CHANNEL = "bracket/orientation"
        private val DIALOG_SURFACE_COLOR = Color.parseColor("#17191E")
        private val DIALOG_ELEVATED_SURFACE_COLOR = Color.parseColor("#21242B")
        private val DIALOG_STROKE_COLOR = Color.parseColor("#343946")
        private val DIALOG_PRIMARY_TEXT_COLOR = Color.WHITE
        private val DIALOG_SECONDARY_TEXT_COLOR = Color.parseColor("#B8FFFFFF")
        private val DIALOG_ACCENT_COLOR = Color.parseColor("#FF7A1A")
    }

    private data class ActiveDlnaCastSession(
        val device: DlnaDevice,
    )

    private val castExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var dlnaCastingClient: DlnaCastingClient

    private var progressDialog: AlertDialog? = null
    private var devicePickerDialog: AlertDialog? = null
    private var activeDlnaCastSession: ActiveDlnaCastSession? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dlnaCastingClient = DlnaCastingClient(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_ROUTE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "presentDevicePicker" -> {
                    val mediaRequest = CastMediaRequest.fromArguments(call.arguments)
                    if (mediaRequest == null) {
                        result.error("invalid_args", "投屏参数无效", null)
                        return@setMethodCallHandler
                    }
                    presentDevicePicker(mediaRequest, result)
                }

                "recastOnActiveDevice" -> {
                    val mediaRequest = CastMediaRequest.fromArguments(call.arguments)
                    if (mediaRequest == null) {
                        result.error("invalid_args", "投屏参数无效", null)
                        return@setMethodCallHandler
                    }
                    recastOnActiveDevice(mediaRequest, result)
                }

                "queryActiveCastStatus" -> {
                    queryActiveCastStatus(result)
                }

                "clearActiveCastSession" -> {
                    activeDlnaCastSession = null
                    result.success(null)
                }

                "stopActiveCastSession" -> {
                    stopActiveCastSession(result)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ORIENTATION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentDeviceOrientation" -> {
                    result.success(currentDeviceOrientation())
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        dismissDialogs()
        castExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun presentDevicePicker(
        mediaRequest: CastMediaRequest,
        result: MethodChannel.Result,
    ) {
        if (!mediaRequest.isSupportedRemoteMedia) {
            result.error("unsupported_media", "当前视频暂不支持投屏", null)
            return
        }

        showProgressDialog("正在搜索投屏设备…")

        castExecutor.execute {
            runCatching {
                dlnaCastingClient.discoverDevices()
            }.onSuccess { devices ->
                runOnUiThread {
                    dismissProgressDialog()
                    if (devices.isEmpty()) {
                        result.error(
                            "no_device_found",
                            "未发现可投屏设备，请确认电视或盒子与手机在同一局域网。",
                            null,
                        )
                        return@runOnUiThread
                    }
                    showDevicePicker(devices, mediaRequest, result)
                }
            }.onFailure { error ->
                runOnUiThread {
                    dismissProgressDialog()
                    result.error(
                        "discovery_failed",
                        error.message ?: "搜索投屏设备失败",
                        null,
                    )
                }
            }
        }
    }

    private fun showDevicePicker(
        devices: List<DlnaDevice>,
        mediaRequest: CastMediaRequest,
        result: MethodChannel.Result,
    ) {
        devicePickerDialog?.dismiss()

        var handled = false
        lateinit var dialog: AlertDialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            minimumWidth = 300.dp
            setPadding(20.dp, 20.dp, 20.dp, 16.dp)
            background = createRoundedDrawable(
                fillColor = DIALOG_SURFACE_COLOR,
                cornerRadiusDp = 28,
                strokeColor = DIALOG_STROKE_COLOR,
            )

            addView(
                TextView(context).apply {
                    text = "选择投屏设备"
                    setTextColor(DIALOG_PRIMARY_TEXT_COLOR)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
                    setTypeface(typeface, Typeface.BOLD)
                },
            )

            addView(
                TextView(context).apply {
                    text = "确保手机和电视或盒子处于同一局域网"
                    setTextColor(DIALOG_SECONDARY_TEXT_COLOR)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    setLineSpacing(2.dp.toFloat(), 1f)
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        topMargin = 8.dp
                    }
                },
            )

            addView(
                View(context).apply {
                    setBackgroundColor(DIALOG_STROKE_COLOR)
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        1.dp,
                    ).apply {
                        topMargin = 16.dp
                        bottomMargin = 16.dp
                    }
                },
            )

            val deviceList = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
            }
            devices.forEachIndexed { index, device ->
                deviceList.addView(
                    createDevicePickerRow(device) {
                        if (handled) {
                            dialog.dismiss()
                            return@createDevicePickerRow
                        }
                        handled = true
                        dialog.dismiss()
                        castToDevice(device, mediaRequest, result)
                    },
                )
                if (index != devices.lastIndex) {
                    deviceList.addView(
                        View(context).apply {
                            layoutParams = LinearLayout.LayoutParams(
                                LinearLayout.LayoutParams.MATCH_PARENT,
                                10.dp,
                            )
                        },
                    )
                }
            }

            val maxListHeight = (resources.displayMetrics.heightPixels * 0.42f).toInt()
            val estimatedHeight = (devices.size * 86).dp
            addView(
                ScrollView(context).apply {
                    isVerticalScrollBarEnabled = false
                    overScrollMode = View.OVER_SCROLL_NEVER
                    addView(deviceList)
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        min(maxListHeight, estimatedHeight),
                    ).apply {
                        bottomMargin = 14.dp
                    }
                },
            )

            addView(
                TextView(context).apply {
                    text = "取消"
                    gravity = Gravity.CENTER
                    setTextColor(DIALOG_PRIMARY_TEXT_COLOR)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    setTypeface(typeface, Typeface.BOLD)
                    setPadding(16.dp, 14.dp, 16.dp, 14.dp)
                    background = createRoundedDrawable(
                        fillColor = DIALOG_ELEVATED_SURFACE_COLOR,
                        cornerRadiusDp = 18,
                        strokeColor = DIALOG_STROKE_COLOR,
                    )
                    setOnClickListener {
                        dialog.dismiss()
                        if (!handled) {
                            handled = true
                            result.error("cancelled", "已取消投屏", null)
                        }
                    }
                },
            )
        }

        dialog = AlertDialog.Builder(
            ContextThemeWrapper(this, androidx.appcompat.R.style.Theme_AppCompat_Dialog),
        ).setView(content)
            .setOnCancelListener {
                if (!handled) {
                    handled = true
                    result.error("cancelled", "已取消投屏", null)
                }
            }
            .create()

        devicePickerDialog = dialog
        showStyledDialog(dialog)
    }

    private fun castToDevice(
        device: DlnaDevice,
        mediaRequest: CastMediaRequest,
        result: MethodChannel.Result,
    ) {
        showProgressDialog("正在连接 ${device.friendlyName}…")

        castExecutor.execute {
            runCatching {
                dlnaCastingClient.cast(device, mediaRequest)
            }.onSuccess {
                runOnUiThread {
                    activeDlnaCastSession = ActiveDlnaCastSession(device = device)
                    dismissProgressDialog()
                    result.success(
                        mapOf(
                            "name" to device.friendlyName,
                            "type" to "dlna",
                        ),
                    )
                }
            }.onFailure { error ->
                runOnUiThread {
                    dismissProgressDialog()
                    activeDlnaCastSession = null
                    result.error(
                        "cast_failed",
                        error.message ?: "投屏失败，请稍后重试。",
                        null,
                    )
                }
            }
        }
    }

    private fun recastOnActiveDevice(
        mediaRequest: CastMediaRequest,
        result: MethodChannel.Result,
    ) {
        val session = activeDlnaCastSession
        if (session == null) {
            result.error("no_active_session", "当前没有可复用的投屏设备", null)
            return
        }

        castExecutor.execute {
            runCatching {
                dlnaCastingClient.cast(session.device, mediaRequest)
            }.onSuccess {
                runOnUiThread {
                    activeDlnaCastSession = session
                    result.success(
                        mapOf(
                            "name" to session.device.friendlyName,
                            "type" to "dlna",
                        ),
                    )
                }
            }.onFailure { error ->
                runOnUiThread {
                    activeDlnaCastSession = null
                    result.error(
                        "cast_failed",
                        error.message ?: "重新投屏失败，请稍后重试。",
                        null,
                    )
                }
            }
        }
    }

    private fun queryActiveCastStatus(result: MethodChannel.Result) {
        val session = activeDlnaCastSession
        if (session == null) {
            result.success(null)
            return
        }

        castExecutor.execute {
            runCatching {
                dlnaCastingClient.getPlaybackStatus(session.device)
            }.onSuccess { status ->
                runOnUiThread {
                    result.success(
                        mapOf(
                            "name" to session.device.friendlyName,
                            "type" to "dlna",
                            "transportState" to status.transportState,
                            "positionSeconds" to status.positionSeconds,
                            "durationSeconds" to status.durationSeconds,
                        ),
                    )
                }
            }.onFailure { error ->
                runOnUiThread {
                    activeDlnaCastSession = null
                    result.error(
                        "cast_status_failed",
                        error.message ?: "读取投屏状态失败",
                        null,
                    )
                }
            }
        }
    }

    private fun stopActiveCastSession(result: MethodChannel.Result) {
        val session = activeDlnaCastSession
        if (session == null) {
            result.success(null)
            return
        }

        castExecutor.execute {
            runCatching {
                dlnaCastingClient.stop(session.device)
            }.onSuccess {
                runOnUiThread {
                    activeDlnaCastSession = null
                    result.success(null)
                }
            }.onFailure { error ->
                runOnUiThread {
                    result.error(
                        "cast_stop_failed",
                        error.message ?: "结束投屏失败",
                        null,
                    )
                }
            }
        }
    }

    private fun showProgressDialog(message: String) {
        dismissProgressDialog()

        val subtitle =
            if (message.contains("搜索")) {
                "请确认电视或盒子与手机连接在同一 Wi-Fi 下"
            } else {
                "请保持当前页面，连接完成后会自动开始播放"
            }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            minimumWidth = 280.dp
            setPadding(20.dp, 20.dp, 20.dp, 20.dp)
            background = createRoundedDrawable(
                fillColor = DIALOG_SURFACE_COLOR,
                cornerRadiusDp = 24,
                strokeColor = DIALOG_STROKE_COLOR,
            )

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL

                    addView(RotatingLoadingIndicator(context))

                    addView(
                        LinearLayout(context).apply {
                            orientation = LinearLayout.VERTICAL
                            layoutParams = LinearLayout.LayoutParams(
                                0,
                                LinearLayout.LayoutParams.WRAP_CONTENT,
                                1f,
                            ).apply {
                                leftMargin = 16.dp
                            }

                            addView(
                                TextView(context).apply {
                                    text = message
                                    setTextColor(DIALOG_PRIMARY_TEXT_COLOR)
                                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                                    setTypeface(typeface, Typeface.BOLD)
                                },
                            )

                            addView(
                                TextView(context).apply {
                                    text = subtitle
                                    setTextColor(DIALOG_SECONDARY_TEXT_COLOR)
                                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                                    setLineSpacing(2.dp.toFloat(), 1f)
                                    layoutParams = LinearLayout.LayoutParams(
                                        LinearLayout.LayoutParams.MATCH_PARENT,
                                        LinearLayout.LayoutParams.WRAP_CONTENT,
                                    ).apply {
                                        topMargin = 6.dp
                                    }
                                },
                            )
                        },
                    )
                },
            )
        }

        progressDialog = AlertDialog.Builder(
            ContextThemeWrapper(this, androidx.appcompat.R.style.Theme_AppCompat_Dialog),
        ).setView(container)
            .setCancelable(false)
            .create()
            .also { showStyledDialog(it) }
    }

    private fun createDevicePickerRow(
        device: DlnaDevice,
        onTap: () -> Unit,
    ): View {
        val deviceName = device.friendlyName.ifBlank { "未命名设备" }
        val subtitle = listOfNotNull(
            device.manufacturer?.takeIf { it.isNotBlank() },
            device.modelName?.takeIf { it.isNotBlank() },
        ).joinToString(" · ").ifBlank { "DLNA 设备" }

        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(16.dp, 14.dp, 16.dp, 14.dp)
            background = createRoundedDrawable(
                fillColor = DIALOG_ELEVATED_SURFACE_COLOR,
                cornerRadiusDp = 20,
                strokeColor = DIALOG_STROKE_COLOR,
            )
            isClickable = true
            isFocusable = true
            setOnClickListener { onTap() }

            addView(
                TextView(context).apply {
                    text = deviceName.first().uppercaseChar().toString()
                    gravity = Gravity.CENTER
                    setTextColor(DIALOG_PRIMARY_TEXT_COLOR)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    setTypeface(typeface, Typeface.BOLD)
                    background = createRoundedDrawable(
                        fillColor = DIALOG_ACCENT_COLOR,
                        cornerRadiusDp = 16,
                    )
                    layoutParams = LinearLayout.LayoutParams(40.dp, 40.dp)
                },
            )

            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(
                        0,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        1f,
                    ).apply {
                        leftMargin = 14.dp
                        rightMargin = 12.dp
                    }

                    addView(
                        TextView(context).apply {
                            text = deviceName
                            setTextColor(DIALOG_PRIMARY_TEXT_COLOR)
                            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                            setTypeface(typeface, Typeface.BOLD)
                            maxLines = 1
                        },
                    )

                    addView(
                        TextView(context).apply {
                            text = subtitle
                            setTextColor(DIALOG_SECONDARY_TEXT_COLOR)
                            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                            maxLines = 1
                            layoutParams = LinearLayout.LayoutParams(
                                LinearLayout.LayoutParams.MATCH_PARENT,
                                LinearLayout.LayoutParams.WRAP_CONTENT,
                            ).apply {
                                topMargin = 4.dp
                            }
                        },
                    )
                },
            )

            addView(
                TextView(context).apply {
                    text = "›"
                    setTextColor(DIALOG_SECONDARY_TEXT_COLOR)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
                    setTypeface(typeface, Typeface.BOLD)
                },
            )
        }
    }

    private fun showStyledDialog(dialog: AlertDialog) {
        dialog.show()
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        dialog.window?.decorView?.setPadding(20.dp, 0, 20.dp, 0)
    }

    private fun createRoundedDrawable(
        fillColor: Int,
        cornerRadiusDp: Int,
        strokeColor: Int? = null,
        strokeWidthDp: Int = 1,
    ): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = cornerRadiusDp.dp.toFloat()
            setColor(fillColor)
            if (strokeColor != null) {
                setStroke(strokeWidthDp.dp, strokeColor)
            }
        }
    }

    private class RotatingLoadingIndicator(
        context: Context,
    ) : FrameLayout(context) {
        private val rotationAnimator = ObjectAnimator.ofFloat(this, View.ROTATION, 0f, 360f).apply {
            duration = 900L
            interpolator = LinearInterpolator()
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
        }

        init {
            val indicatorSize = 32.dp
            layoutParams = LinearLayout.LayoutParams(indicatorSize, indicatorSize)

            addView(
                View(context).apply {
                    layoutParams = LayoutParams(indicatorSize, indicatorSize)
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(Color.TRANSPARENT)
                        setStroke(2.dp, DIALOG_ACCENT_COLOR and 0x66FFFFFF)
                    }
                },
            )

            addView(
                View(context).apply {
                    layoutParams = LayoutParams(10.dp, 10.dp, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
                        topMargin = 1.dp
                    }
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(DIALOG_ACCENT_COLOR)
                    }
                },
            )
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            if (!rotationAnimator.isStarted) {
                rotationAnimator.start()
            } else if (rotationAnimator.isPaused) {
                rotationAnimator.resume()
            }
        }

        override fun onDetachedFromWindow() {
            rotationAnimator.cancel()
            super.onDetachedFromWindow()
        }

        private val Int.dp: Int
            get() = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                toFloat(),
                resources.displayMetrics,
            ).toInt()
    }

    private fun dismissProgressDialog() {
        progressDialog?.dismiss()
        progressDialog = null
    }

    private fun dismissDialogs() {
        dismissProgressDialog()
        devicePickerDialog?.dismiss()
        devicePickerDialog = null
    }

    private fun currentDeviceOrientation(): String {
        val rotation =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                display?.rotation ?: Surface.ROTATION_0
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.rotation
            }

        return when (rotation) {
            Surface.ROTATION_90 -> "landscapeLeft"
            Surface.ROTATION_180 -> "portraitDown"
            Surface.ROTATION_270 -> "landscapeRight"
            else -> "portraitUp"
        }
    }

    private val Int.dp: Int
        get() = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            toFloat(),
            resources.displayMetrics,
        ).toInt()
}
