import QtQuick

// The fields of one page that hold an unsaved edit, in the order each
// began. A field joins through `track`, which it calls whenever its
// `edited` changes, and leaves through `forget` when it is destroyed.
// `save()` asks every field to write its edit and answers whether none
// is left: a field whose value was refused stays edited. A field calls
// `wrote()` once a write of its edit was accepted, whether `save()` or
// Enter in the field sent it, and `saved()` follows the one that leaves
// the set empty. `discard()` asks every field to put back what the
// configuration holds.
QtObject {
    id: root

    property var fields: []
    readonly property bool edited: fields.length > 0
    signal saved()

    function track(field) {
        const rest = fields.filter(held => held !== field);
        fields = field.edited ? rest.concat([field]) : rest;
    }

    function forget(field) {
        fields = fields.filter(held => held !== field);
    }

    function save() {
        for (const field of fields.slice()) field.save();
        return fields.length === 0;
    }

    function wrote() {
        if (fields.length === 0) saved();
    }

    function discard() {
        for (const field of fields.slice()) field.discard();
    }
}
