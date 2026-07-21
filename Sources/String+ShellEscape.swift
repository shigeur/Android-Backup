import Foundation

extension String {
    /// Escapes a string for use as a single argument in a POSIX shell (like Android's sh).
    /// Wraps the string in single quotes, and safely escapes any internal single quotes.
    /// Example: `Don't do it.txt` -> `'Don'\''t do it.txt'`
    var adbEscaped: String {
        return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
