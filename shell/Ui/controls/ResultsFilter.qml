import QtQuick
import qs.Ui

// A result-type choice beside a search field. The accessible name states
// what the choice filters when the page shows no separate visible label.
Select {
    id: root

    property string accessibleLabel: "Filter results"

    Accessible.name: accessibleLabel + ": " + currentText
}
