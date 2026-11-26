package com.markun.tmhb

import android.Manifest
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.WindowManager
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.InetAddress
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var pendingDownloadsScanResult: MethodChannel.Result? = null
    private var pendingLogExportFiles: List<Map<String, Any>>? = null
    private var pendingLogExportResult: MethodChannel.Result? = null
    private var akeEventSink: EventChannel.EventSink? = null
    private val akeConnections = mutableMapOf<Int, AkeSocketConnection>()
    private val akeExecutor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MULTICAST_LOCK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireMulticastLock()
                        result.success(null)
                    }
                    "release" -> {
                        releaseMulticastLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKELOCK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepAwake" -> {
                        val keepAwake = call.argument<Boolean>("keepAwake") ?: false
                        if (keepAwake) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(isKeepAwakeSet())
                    }
                    "getKeepAwake" -> result.success(isKeepAwakeSet())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AKE_SOCKET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val id = call.argument<Int>("id")!!
                        val host = call.argument<String>("host")!!
                        val port = call.argument<Int>("port")!!
                        val connection = AkeSocketConnection(id) { event -> emitAkeEvent(event) }
                        synchronized(akeConnections) { akeConnections[id] = connection }
                        akeExecutor.execute {
                            try {
                                connection.connect(host, port, 10_000)
                                mainHandler.post { result.success(null) }
                            } catch (e: Exception) {
                                synchronized(akeConnections) { akeConnections.remove(id) }
                                mainHandler.post {
                                    result.error("connect_failed", e.message, null)
                                }
                            }
                        }
                    }
                    "send" -> {
                        val id = call.argument<Int>("id")!!
                        val data = call.argument<ByteArray>("data")!!
                        val connection = synchronized(akeConnections) { akeConnections[id] }
                        if (connection != null) {
                            akeExecutor.execute { connection.send(data) }
                        }
                        result.success(null)
                    }
                    "close" -> {
                        val id = call.argument<Int>("id")!!
                        val connection = synchronized(akeConnections) { akeConnections.remove(id) }
                        connection?.close()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareFiles" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        try {
                            shareLogFiles(paths)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CREDENTIAL_DOWNLOADS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanDownloads" -> startDownloadsScan(result)
                    // The Android SDK int (plan 139): the Dart side
                    // branches the player's mpv initialization on the
                    // Android generation (lib/app/android_sdk.dart).
                    // It rides this channel; one integer does not
                    // warrant a channel of its own.
                    "getAndroidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    // The debug log export (plan 142) rides this
                    // channel too: it is the Downloads channel,
                    // and a second folder convention does not
                    // warrant a channel of its own.
                    "exportLogsToDownloads" -> startLogExport(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXTERNAL_BROWSER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Opening nasne HOME in the external browser
                    // (owner request 2026-11-26): a plain
                    // ACTION_VIEW on the URL the Dart side built;
                    // no browser present surfaces as an error
                    // the settings screen can show.
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("invalid_args", "missing url", null)
                        } else {
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("open_failed", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AKE_SOCKET_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    akeEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    akeEventSink = null
                }
            })
    }

    private fun emitAkeEvent(event: Map<String, Any?>) {
        mainHandler.post { akeEventSink?.success(event) }
    }

    // SSDP M-SEARCH responses arrive as Wi-Fi multicast; without this
    // lock the driver may filter them out (plan 17).
    private fun acquireMulticastLock() {
        if (multicastLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("torne-mobile-hb-ssdp").apply {
                setReferenceCounted(false)
            }
        }
        if (multicastLock?.isHeld != true) {
            multicastLock?.acquire()
        }
    }

    private fun releaseMulticastLock() {
        if (multicastLock?.isHeld == true) {
            multicastLock?.release()
        }
    }

    // Sleep suppression during playback (plan 35): the Dart side
    // gets the flag read back after every set, so the debug log
    // proves whether the setting actually stuck. Method channel
    // handlers run on the main thread, so touching the window
    // here is safe.
    private fun isKeepAwakeSet(): Boolean =
        window.attributes.flags and
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0

    // Debug log sharing (plan 46): hands the staged log copies in
    // the cache dir to the system share sheet. Raw file:// URIs
    // are rejected since API 24, so the files go out as
    // FileProvider content URIs; the provider's paths file exposes
    // only the staging subdirectory of the cache dir. The ClipData
    // carries the read grants through the chooser to the target
    // app.
    private fun shareLogFiles(paths: List<String>) {
        require(paths.isNotEmpty()) { "no files to share" }
        val uris = ArrayList<Uri>()
        for (path in paths) {
            uris.add(FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path)))
        }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "text/plain"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            clipData = ClipData.newUri(contentResolver, "debug logs", uris[0]).apply {
                for (i in 1 until uris.size) {
                    addItem(ClipData.Item(uris[i]))
                }
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "デバッグログを共有"))
    }

    // Downloads scan for credential files (plan 127): Android TV
    // has no usable file picker, so the import screen can look in
    // the public Downloads folder instead. The legacy storage
    // model (API 32 and below, which covers the Fire TV targets)
    // needs READ_EXTERNAL_STORAGE for that; it is requested here
    // on first use and the scan runs once the user answers. On
    // API 33+ scoped storage refuses direct reads of non-media
    // files other apps put there, and the scan reports
    // permission_denied so the Dart side can say so plainly.
    // The folder itself goes by two spellings in the field
    // (plan 132): the system constant names the singular
    // "Download", but devices also carry a plural "Downloads"
    // next to it — the Fire TV this was found on has both, with
    // the user's file in the plural one — so both are scanned.
    private fun startDownloadsScan(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT <= 32 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingDownloadsScanResult != null) {
                result.error("scan_failed", "a downloads scan is already waiting for permission", null)
                return
            }
            pendingDownloadsScanResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                REQUEST_READ_EXTERNAL_STORAGE,
            )
            return
        }
        runDownloadsScan(result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_READ_EXTERNAL_STORAGE) {
            val pending = pendingDownloadsScanResult ?: return
            pendingDownloadsScanResult = null
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                runDownloadsScan(pending)
            } else {
                pending.error("permission_denied", "READ_EXTERNAL_STORAGE was not granted", null)
            }
            return
        }
        if (requestCode == REQUEST_WRITE_EXTERNAL_STORAGE) {
            val pending = pendingLogExportResult ?: return
            val files = pendingLogExportFiles ?: emptyList()
            pendingLogExportResult = null
            pendingLogExportFiles = null
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                runLogExportLegacy(files, pending)
            } else {
                pending.error("permission_denied", "WRITE_EXTERNAL_STORAGE was not granted", null)
            }
        }
    }

    private fun runDownloadsScan(result: MethodChannel.Result) {
        try {
            val found = ArrayList<Map<String, Any>>()
            val seenPaths = HashSet<String>()
            var listedAny = false
            for (root in downloadsScanRoots()) {
                if (collectCredentialFiles(root, 0, found, seenPaths)) {
                    listedAny = true
                }
            }
            if (!listedAny) {
                throw SecurityException("cannot list the downloads folders")
            }
            result.success(found)
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: Exception) {
            result.error("scan_failed", e.message, null)
        }
    }

    // The folders the scan looks in (plan 132): the public
    // Downloads directory, plus a sibling named "Downloads"
    // (plural) when the device has one. Which spelling a file
    // lands in depends on the tool that put it there, so both
    // are scanned; roots that resolve to the same directory
    // (the two spellings can be one folder) are scanned once.
    private fun downloadsScanRoots(): List<File> {
        val roots = ArrayList<File>()
        val seenRoots = HashSet<String>()
        fun addRoot(dir: File?) {
            if (dir == null || !dir.isDirectory) return
            if (seenRoots.add(dir.canonicalPath)) roots.add(dir)
        }
        addRoot(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        )
        addRoot(Environment.getExternalStorageDirectory()?.let { File(it, "Downloads") })
        return roots
    }

    // Collects files whose names follow the credentials*.env
    // shape (the same rule the Dart side re-checks), descending
    // a few levels so a file dropped in a subfolder is still
    // found. Only small files are read: a credentials.env is a
    // few hundred bytes, and nothing larger can be one.
    //
    // Returns whether [dir] itself could be listed; only the
    // top-level caller uses that, to tell "no scan root could
    // be read at all" (reported as permission_denied) apart
    // from "read fine, nothing matched". [seenPaths] holds the
    // canonical path of every file already collected: with
    // more than one scan root the same file can be reachable
    // twice, and it is collected once.
    private fun collectCredentialFiles(
        dir: File,
        depth: Int,
        out: ArrayList<Map<String, Any>>,
        seenPaths: MutableSet<String>,
    ): Boolean {
        if (out.size >= MAX_DOWNLOADS_SCAN_FILES) return true
        val entries = dir.listFiles() ?: return false
        for (entry in entries) {
            if (out.size >= MAX_DOWNLOADS_SCAN_FILES) break
            if (entry.isDirectory) {
                if (depth < MAX_DOWNLOADS_SCAN_DEPTH) {
                    collectCredentialFiles(entry, depth + 1, out, seenPaths)
                }
            } else if (isCredentialEnvFileName(entry.name) &&
                entry.length() in 1..MAX_DOWNLOADS_SCAN_FILE_BYTES &&
                seenPaths.add(entry.canonicalPath)
            ) {
                out.add(
                    mapOf(
                        "name" to entry.name,
                        "path" to entry.absolutePath,
                        "bytes" to entry.readBytes(),
                    )
                )
            }
        }
        return true
    }

    private fun isCredentialEnvFileName(name: String): Boolean {
        val lower = name.lowercase()
        return lower.startsWith("credentials") && lower.endsWith(".env")
    }

    // Debug log export to Downloads (plan 142): the TV share
    // sheet offers too few destinations to get a log off the
    // device (plan 140), so the TV edition writes the recorded
    // logs into Downloads/tmhb-log/ instead, where a USB cable,
    // adb or a file manager can reach them without any account
    // or network state. The Dart side has already stamped every
    // file name with the export time, so a re-export never
    // overwrites an earlier export's files.
    //
    // Under scoped storage (API 29+) the files go through
    // MediaStore, which asks for no permission for files the
    // app itself creates. Under the legacy storage model
    // (API 28 and below, which covers the Fire TV targets) the
    // write is a direct file write into the public Downloads
    // folder and needs WRITE_EXTERNAL_STORAGE, requested on
    // first use the same way the Downloads scan requests its
    // read permission above.
    private fun startLogExport(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val files = call.argument<List<Map<String, Any>>>("files") ?: emptyList()
        if (files.isEmpty()) {
            result.error("export_failed", "no files to export", null)
            return
        }
        if (Build.VERSION.SDK_INT >= 29) {
            runLogExportMediaStore(files, result)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingLogExportResult != null) {
                result.error(
                    "export_failed",
                    "a log export is already waiting for permission",
                    null,
                )
                return
            }
            pendingLogExportFiles = files
            pendingLogExportResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_WRITE_EXTERNAL_STORAGE,
            )
            return
        }
        runLogExportLegacy(files, result)
    }

    // Legacy storage model: a direct write into
    // Downloads/tmhb-log/, creating the folder first. Answers
    // the folder's absolute path.
    private fun runLogExportLegacy(
        files: List<Map<String, Any>>,
        result: MethodChannel.Result,
    ) {
        try {
            val downloads = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            val dir = File(downloads, LOG_EXPORT_DIRECTORY_NAME)
            if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) {
                throw SecurityException("cannot create ${dir.absolutePath}")
            }
            for (file in files) {
                val name = file["name"] as String
                val bytes = file["bytes"] as ByteArray
                File(dir, name).writeBytes(bytes)
            }
            result.success(dir.absolutePath)
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: Exception) {
            result.error("export_failed", e.message, null)
        }
    }

    // Scoped storage (API 29+): insert each file into the
    // Downloads collection under tmhb-log/. Files the app
    // creates this way need no storage permission, and they
    // are visible to the user and to adb like any other
    // Downloads content. Answers the public relative path.
    private fun runLogExportMediaStore(
        files: List<Map<String, Any>>,
        result: MethodChannel.Result,
    ) {
        try {
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val relativePath =
                Environment.DIRECTORY_DOWNLOADS + "/" + LOG_EXPORT_DIRECTORY_NAME
            for (file in files) {
                val name = file["name"] as String
                val bytes = file["bytes"] as ByteArray
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                    put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
                }
                val uri = contentResolver.insert(collection, values)
                    ?: throw IOException("MediaStore insert returned no URI for $name")
                val stream = contentResolver.openOutputStream(uri)
                    ?: throw IOException("MediaStore opened no stream for $name")
                stream.use { it.write(bytes) }
            }
            result.success(relativePath)
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: Exception) {
            result.error("export_failed", e.message, null)
        }
    }

    companion object {
        private const val MULTICAST_LOCK_CHANNEL = "com.markun.tmhb/multicast_lock"
        private const val WAKELOCK_CHANNEL = "com.markun.tmhb/wakelock"
        private const val SHARE_FILES_CHANNEL = "com.markun.tmhb/share_files"
        private const val AKE_SOCKET_CHANNEL = "com.markun.tmhb/ake_socket"
        private const val AKE_SOCKET_EVENTS_CHANNEL = "com.markun.tmhb/ake_socket_events"
        private const val CREDENTIAL_DOWNLOADS_CHANNEL = "com.markun.tmhb/credential_downloads"
        private const val EXTERNAL_BROWSER_CHANNEL = "com.markun.tmhb/external_browser"
        private const val REQUEST_READ_EXTERNAL_STORAGE = 7411
        private const val REQUEST_WRITE_EXTERNAL_STORAGE = 7412
        private const val LOG_EXPORT_DIRECTORY_NAME = "tmhb-log"
        private const val MAX_DOWNLOADS_SCAN_DEPTH = 3
        private const val MAX_DOWNLOADS_SCAN_FILES = 64
        private const val MAX_DOWNLOADS_SCAN_FILE_BYTES = 256L * 1024L
    }
}

/// fcntl(2) via JNI (libtmhb_fcntl). android.system.Os.fcntlInt only
/// exists on API 30+, and calling it on an older device kills the
/// calling thread with NoSuchMethodError — the AKE socket connects on
/// a worker thread at the start of playback, so playback crashed on
/// API 29 (and on every API below 30) devices. The native call has
/// the exact semantics of Os.fcntlInt on every API level, so there is
/// a single code path: it returns the fcntl(2) result, or -errno on
/// failure, which is converted to ErrnoException here just like Os.
private object FcntlCompat {
    init {
        System.loadLibrary("tmhb_fcntl")
    }

    private external fun nativeFcntlInt(fd: FileDescriptor, cmd: Int, arg: Int): Int

    fun fcntlInt(fd: FileDescriptor, cmd: Int, arg: Int): Int {
        val result = nativeFcntlInt(fd, cmd, arg)
        if (result < 0) throw ErrnoException("fcntl", -result)
        return result
    }
}

/// One native AKE socket (plan 28): a BSD socket with IP TTL 3 and
/// TCP_NODELAY set via setsockopt before connect (the DTCP-IP
/// proximity requirement the reference client implements), with
/// blocking I/O on worker threads afterwards.
private class AkeSocketConnection(
    private val id: Int,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private var fd: FileDescriptor? = null
    private var input: FileInputStream? = null
    private var output: FileOutputStream? = null

    @Volatile
    private var closed = false

    fun connect(host: String, port: Int, timeoutMs: Int) {
        val descriptor = Os.socket(OsConstants.AF_INET, OsConstants.SOCK_STREAM, 0)
        try {
            Os.setsockoptInt(descriptor, OsConstants.IPPROTO_IP, OsConstants.IP_TTL, 3)
            Os.setsockoptInt(descriptor, OsConstants.IPPROTO_TCP, OsConstants.TCP_NODELAY, 1)
            val address = InetAddress.getByName(host)
            val flags = FcntlCompat.fcntlInt(descriptor, OsConstants.F_GETFL, 0)
            FcntlCompat.fcntlInt(descriptor, OsConstants.F_SETFL, flags or OsConstants.O_NONBLOCK)
            var inProgress = false
            try {
                Os.connect(descriptor, address, port)
            } catch (e: ErrnoException) {
                if (e.errno != OsConstants.EINPROGRESS) throw e
                inProgress = true
            }
            if (inProgress) {
                val pollFd = StructPollfd().apply {
                    fd = descriptor
                    events = OsConstants.POLLOUT.toShort()
                }
                val ready = Os.poll(arrayOf(pollFd), timeoutMs)
                if (ready <= 0) {
                    throw ErrnoException("connect", OsConstants.ETIMEDOUT)
                }
                // A failed connect also reports writable; confirm
                // the peer exists (throws ENOTCONN otherwise).
                // (android.system.Os has no public getsockoptInt in
                // the SDK stubs, hence getpeername.)
                Os.getpeername(descriptor)
            }
            FcntlCompat.fcntlInt(descriptor, OsConstants.F_SETFL, flags)
        } catch (e: Exception) {
            try {
                Os.close(descriptor)
            } catch (_: Exception) {
            }
            throw e
        }
        fd = descriptor
        input = FileInputStream(descriptor)
        output = FileOutputStream(descriptor)
        Thread { readLoop() }.apply { isDaemon = true }.start()
    }

    private fun readLoop() {
        val buffer = ByteArray(16384)
        try {
            while (!closed) {
                val count = input!!.read(buffer)
                if (count > 0) {
                    emit(
                        mapOf(
                            "id" to id,
                            "kind" to "data",
                            "data" to buffer.copyOf(count),
                        ),
                    )
                } else if (count < 0) {
                    if (!closed) emit(mapOf("id" to id, "kind" to "done"))
                    return
                }
            }
        } catch (e: Exception) {
            if (!closed) {
                emit(
                    mapOf(
                        "id" to id,
                        "kind" to "error",
                        "message" to (e.message ?: "socket error"),
                    ),
                )
            }
        }
    }

    fun send(data: ByteArray) {
        val out = output ?: return
        synchronized(out) {
            try {
                out.write(data)
                out.flush()
            } catch (e: Exception) {
                if (!closed) {
                    emit(
                        mapOf(
                            "id" to id,
                            "kind" to "error",
                            "message" to (e.message ?: "send failed"),
                        ),
                    )
                }
            }
        }
    }

    fun close() {
        closed = true
        // Best effort: closing the descriptor and the streams wakes
        // the read loop in practice; a lingering reader exits when
        // the peer closes and its events are dropped by the Dart
        // side, which has already forgotten this connection.
        try {
            input?.close()
        } catch (_: Exception) {
        }
        try {
            output?.close()
        } catch (_: Exception) {
        }
        val descriptor = fd
        fd = null
        if (descriptor != null) {
            try {
                Os.close(descriptor)
            } catch (_: Exception) {
            }
        }
    }
}
