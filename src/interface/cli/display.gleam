import gleam/io

/// Displays a section heading.
pub fn heading(title: String) -> Nil {
  io.println("")
  io.println("================================")
  io.println("  " <> title)
  io.println("================================")
}

/// Displays an informational message.
pub fn info(message: String) -> Nil {
  io.println("[INFO] " <> message)
}

/// Displays a success message.
pub fn success(message: String) -> Nil {
  io.println("[SUCCESS] " <> message)
}

/// Displays an error message.
pub fn error(message: String) -> Nil {
  io.println("[ERROR] " <> message)
}

/// Displays a warning message.
pub fn warning(message: String) -> Nil {
  io.println("[WARNING] " <> message)
}

/// Displays a separator.
pub fn separator() -> Nil {
  io.println("--------------------------------")
}

/// Displays a prompt without a newline.
pub fn prompt(message: String) -> Nil {
  io.print(message)
}
