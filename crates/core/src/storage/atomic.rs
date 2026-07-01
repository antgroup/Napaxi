use std::fs;
use std::path::Path;

pub(crate) fn atomic_write_text_sync(path: &Path, content: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let temp = path.with_file_name(format!(
        ".{}.{}.tmp",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("napaxi"),
        uuid::Uuid::new_v4()
    ));
    if let Err(error) = fs::write(&temp, content) {
        let _ = fs::remove_file(&temp);
        return Err(error.to_string());
    }
    fs::rename(&temp, path).map_err(|error| {
        let _ = fs::remove_file(&temp);
        error.to_string()
    })
}
