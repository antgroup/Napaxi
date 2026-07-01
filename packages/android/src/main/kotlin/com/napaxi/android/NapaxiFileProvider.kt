package com.napaxi.android

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File

public class NapaxiFileProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? =
        when (uri.path?.substringAfterLast('.', "")) {
            "apk" -> "application/vnd.android.package-archive"
            else -> "application/octet-stream"
        }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val ctx = context ?: return null
        val file = uri.toFile(ctx)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun Uri.toFile(context: Context): File {
        val root = when (pathSegments.firstOrNull()) {
            "files" -> context.filesDir
            "cache" -> context.cacheDir
            "external-files" -> context.getExternalFilesDir(null) ?: context.filesDir
            "external-cache" -> context.externalCacheDir ?: context.cacheDir
            else -> context.filesDir
        }
        val encodedPath = getQueryParameter("path").orEmpty()
        val file = File(encodedPath.ifBlank { root.absolutePath })
        val canonical = file.canonicalFile
        val allowedRoots = listOfNotNull(
            context.filesDir.canonicalFile,
            context.cacheDir.canonicalFile,
            context.getExternalFilesDir(null)?.canonicalFile,
            context.externalCacheDir?.canonicalFile,
        )
        require(allowedRoots.any { canonical.path == it.path || canonical.path.startsWith("${it.path}/") }) {
            "File is outside Napaxi provider roots"
        }
        return canonical
    }

    public companion object {
        public fun uriForFile(context: Context, file: File): Uri {
            val shareableFile = prepareShareableFile(context, file)
            val root = when {
                shareableFile.canonicalPath.startsWith(context.cacheDir.canonicalPath) -> "cache"
                context.getExternalFilesDir(null) != null &&
                    shareableFile.canonicalPath.startsWith(context.getExternalFilesDir(null)!!.canonicalPath) -> "external-files"
                context.externalCacheDir != null && shareableFile.canonicalPath.startsWith(context.externalCacheDir!!.canonicalPath) -> "external-cache"
                else -> "files"
            }
            return Uri.Builder()
                .scheme("content")
                .authority("${context.packageName}.napaxi.fileprovider")
                .appendPath(root)
                .appendQueryParameter("path", shareableFile.canonicalPath)
                .build()
        }

        private fun prepareShareableFile(context: Context, file: File): File {
            val canonical = file.canonicalFile
            val allowedRoots = listOfNotNull(
                context.filesDir.canonicalFile,
                context.cacheDir.canonicalFile,
                context.getExternalFilesDir(null)?.canonicalFile,
                context.externalCacheDir?.canonicalFile,
            )
            if (allowedRoots.any { canonical.path == it.path || canonical.path.startsWith("${it.path}/") }) {
                return canonical
            }

            val sharedDir = File(context.cacheDir, "napaxi-shared").apply { mkdirs() }
            val safeName = canonical.name
                .ifBlank { "shared-file" }
                .replace(Regex("""[^A-Za-z0-9._-]"""), "_")
            val target = File(
                sharedDir,
                "${canonical.length()}-${canonical.lastModified()}-$safeName",
            )
            canonical.copyTo(target, overwrite = true)
            return target.canonicalFile
        }
    }
}
