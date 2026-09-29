import Darwin

// Same-volume, exclusive rename: unlike `mv source destination`, an existing
// destination is never overwritten or interpreted as a containing directory.
let arguments = CommandLine.arguments
guard arguments.count == 3, arguments[1].hasPrefix("/"), arguments[2].hasPrefix("/") else {
    fputs("Usage: MoveApp /absolute/source /absolute/destination\n", stderr)
    exit(2)
}
if renameatx_np(AT_FDCWD, arguments[1], AT_FDCWD, arguments[2], UInt32(RENAME_EXCL)) != 0 {
    fputs("Exclusive rename failed: \(String(cString: strerror(errno)))\n", stderr)
    exit(1)
}
