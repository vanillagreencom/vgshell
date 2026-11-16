import QtQuick
import QtTest

// inputs: shell/plugins/vgs.polkit/Prompt.qml shell/plugins/vgs.polkit/PolkitModel.js shell/Hosts/SummonHost.qml
// Exercise the shipped prompt and host's yield/hide/drop path with a fake
// authentication flow. Native surface creation is outside this unit test.
Item {
    id: root
    width: 800
    height: 600

    QtObject {
        id: agent
        property var flow: null
        readonly property bool isActive: flow !== null
    }

    Component {
        id: flowComponent
        QtObject {
            property bool isResponseRequired: true
            property bool isCompleted: false
            property bool isCancelled: false
            property var identities: []
            property var selectedIdentity: null
            property int cancellations: 0
            function cancelAuthenticationRequest() {
                cancellations += 1;
                isCancelled = true;
            }
        }
    }

    TestCase {
        name: "polkit_prompt"
        when: windowShown

        function source(path) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl(path), false);
            request.send();
            verify(request.responseText.length > 0, "read " + path);
            return request.responseText;
        }

        function test_window_yield_respects_the_request_lifetime_data() {
            return [
                { tag: "live", live: true, control: false },
                { tag: "ended", live: false, control: false },
                { tag: "missing-hold-control", live: true, control: true }
            ];
        }

        function test_window_yield_respects_the_request_lifetime(data) {
            const flow = createTemporaryObject(flowComponent, root);
            verify(flow !== null);
            agent.flow = flow;
            let promptSource = source("../../shell/plugins/vgs.polkit/Prompt.qml");
            if (data.control) {
                const hold = /    function holdsHide\(\) \{\n[\s\S]*?\n    \}\n/;
                verify(hold.test(promptSource), "the control removes the live-request hold");
                promptSource = promptSource.replace(hold, "");
            }
            const prompt = Qt.createQmlObject(promptSource, root,
                Qt.resolvedUrl("../../shell/plugins/vgs.polkit/Prompt.qml"));
            const hostSource = source("../../shell/Hosts/SummonHost.qml");
            const parts = hostSource.split("\n    Variants {");
            compare(parts.length, 2, "mount host methods without native surfaces");
            const registration = "    Component.onCompleted: Plugins.registerHost(kind, host)";
            compare(parts[0].split(registration).length, 2);
            const host = Qt.createQmlObject(parts[0].replace(registration, "")
                .replace("required property string kind", "property string kind: \"overlay\"") + "\n}", root,
                Qt.resolvedUrl("../../shell/Hosts/SummonHost.qml"));
            try {
                prompt.shell = { polkit: { agent: agent } };
                prompt.open("{}");
                const screen = { name: "test-screen" };
                host.requests = { "vgs.polkit": { anchored: false, screen: screen } };
                host.instances = { "vgs.polkit": prompt };
                host.openIds = ["vgs.polkit"];
                // SummonLayer unmaps on dropping, then closes the instance.
                host.dropping.connect(() => { prompt.visible = false; prompt.close(); });
                if (!data.live) agent.flow = null;

                host.yieldToWindow(screen);
                if (data.control) expectFailContinue("", "without the hold, a window cancels the live request");
                compare(host.openIds.indexOf("vgs.polkit") !== -1, data.live);
                if (data.control) expectFailContinue("", "the control also hides the prompt");
                compare(prompt.visible, data.live);
                if (data.control) expectFailContinue("", "the control reaches close and cancels authentication");
                compare(flow.cancellations, 0);

                if (data.live && !data.control) {
                    // The request's end releases the hold for the service's hide.
                    agent.flow = null;
                    compare(host.hide("vgs.polkit"), "ok");
                    compare(host.openIds.length, 0);
                    compare(prompt.visible, false);
                }
            } finally {
                host.destroy();
                prompt.destroy();
                agent.flow = null;
            }
        }
    }
}
