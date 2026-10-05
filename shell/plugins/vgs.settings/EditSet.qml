import QtQuick

// The fields of one page that hold an unsaved edit, in the order each
// began. A field joins through `track`, which it calls whenever its
// `edited` changes, and leaves through `forget` when it is destroyed.
// `save()` asks every field to write its edit, or `only` alone, as Enter
// in that field does, and answers whether none is left: a field whose
// value was refused stays edited. `saved()` follows a save that wrote the
// set's last edit. `discard()` asks every field to put back what the
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

    function save(only) {
        const held = only === undefined ? fields.slice() : fields.filter(field => field === only);
        for (const field of held) field.save();
        if (held.length > 0 && !edited) saved();
        return !edited;
    }

    function discard() {
        for (const field of fields.slice()) field.discard();
    }
}
