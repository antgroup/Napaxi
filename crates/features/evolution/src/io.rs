use std::path::Path;
use tokio::fs::OpenOptions;
use tokio::io::AsyncWriteExt;

/// Atomically write text file
///
/// Uses a temporary file in the same directory + rename to ensure atomicity
pub async fn atomic_write_text(file_path: &Path, content: &str) -> std::io::Result<()> {
    // 1. Ensure parent directory exists
    if let Some(parent) = file_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

    // 2. Create temporary file (in the same directory, to guarantee atomic rename)
    let temp_path = file_path.with_extension(format!(".tmp.{}", std::process::id()));

    // 3. Write to temporary file
    let result = async {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp_path)
            .await?;

        file.write_all(content.as_bytes()).await?;
        file.sync_all().await?;

        Ok::<(), std::io::Error>(())
    }
    .await;

    if let Err(e) = result {
        let _ = tokio::fs::remove_file(&temp_path).await;
        return Err(e);
    }

    // 4. Atomic rename
    tokio::fs::rename(&temp_path, file_path).await?;

    Ok(())
}

/// Atomically copy directory
pub async fn atomic_copy_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    // 1. Create temporary directory
    let temp_dst = dst.with_extension(format!(".tmp.{}", std::process::id()));

    // 2. Copy to temporary directory
    copy_dir_all(src, &temp_dst).await?;

    // 3. Atomic rename
    match tokio::fs::rename(&temp_dst, dst).await {
        Ok(()) => Ok(()),
        Err(e) => {
            let _ = tokio::fs::remove_dir_all(&temp_dst).await;
            Err(e)
        }
    }
}

/// Recursively copy directory
pub(crate) async fn copy_dir_all(
    src: impl AsRef<Path>,
    dst: impl AsRef<Path>,
) -> std::io::Result<()> {
    tokio::fs::create_dir_all(&dst).await?;

    let mut entries = tokio::fs::read_dir(src).await?;

    while let Some(entry) = entries.next_entry().await? {
        let src_path = entry.path();
        let dst_path = dst.as_ref().join(entry.file_name());

        let metadata = entry.metadata().await?;
        if metadata.is_dir() {
            Box::pin(copy_dir_all(&src_path, &dst_path)).await?;
        } else {
            tokio::fs::copy(&src_path, &dst_path).await?;
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[tokio::test]
    async fn test_atomic_write_text() {
        let temp = TempDir::new().unwrap();
        let file_path = temp.path().join("test.txt");

        atomic_write_text(&file_path, "Hello, World!")
            .await
            .unwrap();

        let content = tokio::fs::read_to_string(&file_path).await.unwrap();
        assert_eq!(content, "Hello, World!");
    }

    #[tokio::test]
    async fn test_atomic_copy_dir() {
        let temp = TempDir::new().unwrap();
        let src = temp.path().join("src");
        let dst = temp.path().join("dst");

        // Create source directory
        tokio::fs::create_dir(&src).await.unwrap();
        tokio::fs::write(src.join("file.txt"), "content")
            .await
            .unwrap();

        // Copy
        atomic_copy_dir(&src, &dst).await.unwrap();

        // Verify
        let content = tokio::fs::read_to_string(dst.join("file.txt"))
            .await
            .unwrap();
        assert_eq!(content, "content");
    }

    #[tokio::test]
    async fn test_atomic_write_to_readonly_dir() {
        let temp = TempDir::new().unwrap();
        let file_path = temp.path().join("readonly").join("test.txt");

        // Try writing to nonexistent subdirectory (no auto-create parent dir permission issue)
        // This test may vary by platform, here we just verify no panic
        let _result = atomic_write_text(&file_path, "content").await;
        // Result depends on system, but at least we ensure no panic
    }

    #[tokio::test]
    async fn test_atomic_write_overwrite() {
        let temp = TempDir::new().unwrap();
        let file_path = temp.path().join("test.txt");

        // First write
        atomic_write_text(&file_path, "First content")
            .await
            .unwrap();

        // Second write (overwrite)
        atomic_write_text(&file_path, "Second content")
            .await
            .unwrap();

        let content = tokio::fs::read_to_string(&file_path).await.unwrap();
        assert_eq!(content, "Second content");
    }

    #[tokio::test]
    async fn test_atomic_copy_nonexistent_src() {
        let temp = TempDir::new().unwrap();
        let src = temp.path().join("nonexistent");
        let dst = temp.path().join("dst");

        // Copying nonexistent directory should fail
        let result = atomic_copy_dir(&src, &dst).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_atomic_write_nested_dirs() {
        let temp = TempDir::new().unwrap();
        let file_path = temp.path().join("a").join("b").join("c").join("test.txt");

        // Write to nested directories
        atomic_write_text(&file_path, "nested content")
            .await
            .unwrap();

        let content = tokio::fs::read_to_string(&file_path).await.unwrap();
        assert_eq!(content, "nested content");
    }
}
