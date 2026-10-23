package dev.openmarkji.openmarkji

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingApk: File? = null
    private var pendingInstall: MethodChannel.Result? = null
    private val installPermissionRequest = 7081

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openmarkji/app_update")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull {
                            it in listOf("arm64-v8a", "armeabi-v7a", "x86_64")
                        } ?: throw IllegalStateException("当前设备架构暂不支持应用内更新"))
                        "prepareUpdate" -> {
                            val directory = File(cacheDir, "updates")
                            directory.mkdirs()
                            directory.listFiles()?.forEach { it.delete() }
                            result.success(File(directory, "OpenMarkji-update.apk").absolutePath)
                        }
                        "installUpdate" -> {
                            val apk = File(requireNotNull(call.argument<String>("path")))
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()) {
                                pendingApk = apk
                                pendingInstall = result
                                startActivityForResult(Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                ), installPermissionRequest)
                            } else {
                                openInstaller(apk, result)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    pendingApk = null
                    pendingInstall = null
                    result.error("update_failed", e.localizedMessage, null)
                }
            }
    }

    private fun openInstaller(apk: File, result: MethodChannel.Result) {
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            result.success(null)
        } catch (e: Exception) {
            result.error("install_failed", e.localizedMessage, null)
        }
    }

    @Deprecated("Android activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != installPermissionRequest) return
        val apk = pendingApk ?: return
        val result = pendingInstall ?: return
        pendingApk = null
        pendingInstall = null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()) {
            openInstaller(apk, result)
        } else {
            result.error("install_permission_denied", "尚未允许本应用安装更新，安装包已保留，可再次点击安装。", null)
        }
    }
}
