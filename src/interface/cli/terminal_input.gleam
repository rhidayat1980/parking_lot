//// Provides terminal input functionality for the CLI.
////
//// This module wraps the Erlang terminal input adapter.

@external(erlang, "terminal_input", "read_line")
fn read_line_ffi() -> Result(String, Nil)

/// Reads one line from standard input.
///
/// Returns `Ok(input)` when a line is available.
/// Returns `Error(Nil)` when the input stream reaches EOF or fails.
pub fn read_line() -> Result(String, Nil) {
  read_line_ffi()
}
