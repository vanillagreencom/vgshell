import QtQuick

Item {
    property var shell: null
    property string draft: ""
    function open(payload) {
        if (draft !== "") throw new Error("draft occupied");
        draft = JSON.parse(payload).text;
    }
    function close() {}
}
