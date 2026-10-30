pragma Singleton
import QtQuick

// Stands in for Quickshell.Io's FileViewError enum, whose plugin does not
// load outside the shell. Values match src/io/fileview.hpp at VGS's pin.
QtObject {
    enum Error {
        Success = 0,
        Unknown = 1,
        FileNotFound = 2,
        PermissionDenied = 3,
        NotAFile = 4
    }
}
