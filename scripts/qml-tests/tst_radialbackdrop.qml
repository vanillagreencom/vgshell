import QtQuick
import QtTest
import qs.Ui
import qs.Unit

// RadialBackdrop draws one field from up to four boxes: each box's own
// peak, ink and fade; an eased falloff from the box's inset to zero at its
// reach, or a Gaussian one; boxes joined with no crease, peak and ink
// passing gradually from one to the next; a halo past box 0's ring only
// when asked; premultiplied output; and no frame while its inputs stay.
// Read from the drawn image under scripts/qml-unit.sh's software OpenGL:
// black ink over a white ground reads alpha a as 255 × (1 - a).
Item {
    id: root
    width: 400
    height: 200

    Rectangle { id: ground; anchors.fill: parent; color: "#ffffff" }
    RadialBackdrop {
        id: field
        anchors.fill: parent
        boxes: []
        join: 0.1
        blend: 0.15
        falloff: "eased"
        halo: null
    }

    UnitCase {
        name: "radial-backdrop"
        when: windowShown

        function init() {
            ground.color = "#ffffff";
            field.join = 0.1;
            field.blend = 0.15;
            field.falloff = "eased";
            field.halo = null;
            field.boxes = [];
        }
        function box(x, w, peak, fade, inset, ink) {
            return { x: x, y: 50, w: w, h: 100, corner: 0, peak: peak, fade: fade, inset: inset, ink: ink || "#000000" };
        }
        function drawn() {
            verify(renderedFrame(root), "the field draws");
            return grabImage(root);
        }
        // The alpha black ink draws at pixel column X on the boxes' middle row.
        function alpha(image, x) { return 1 - image.red(x, 100) / 255; }
        function eased(t) { t = Math.max(0, Math.min(1, t)); return 1 - t * t * t * (t * (t * 6 - 15) + 10); }
        function near(actual, expected, label) {
            verify(Math.abs(actual - expected) <= 0.015, label + ": " + actual.toFixed(3) + " against " + expected.toFixed(3));
        }

        // One box: its peak on the plateau `inset` inside its edge, half
        // way down the eased fall at the reach's middle, nothing at
        // `fade - inset` outside it.
        function test_one_box_falls_from_its_plateau_to_nothing() {
            field.boxes = [box(100, 100, 0.8, 100, 20)];
            const image = drawn();
            near(alpha(image, 150), 0.8, "the box's middle");
            near(alpha(image, 175), 0.8, "the plateau's end");
            // Pixel 230's centre lies 30.5 px past the edge: x = 0.505.
            near(alpha(image, 230), 0.8 * eased(50.5 / 100), "the fall's middle");
            near(alpha(image, 285), 0, "the reach");
            near(alpha(image, 50), 0.8 * eased((100 - 50.5 + 20) / 100), "the left side");
        }

        // The Gaussian falloff: exp(-x²) past the plateau.
        function test_a_gaussian_box_falls_as_exp_of_minus_x_squared() {
            field.falloff = "gaussian";
            field.boxes = [box(100, 100, 0.9, 20, 0)];
            const image = drawn();
            near(alpha(image, 150), 0.9, "the box's middle");
            for (const px of [205, 215, 225]) {
                const x = (px + 0.5 - 200) / 20;
                near(alpha(image, px), 0.9 * Math.exp(-x * x), "pixel " + px);
            }
        }

        // Two boxes join by a smooth minimum: half way between them the
        // field is darker than either box alone draws there, as the union
        // s = m - join ln Σ e^{-(x - m)/join} sets, so no crease shows.
        function test_two_boxes_join_with_no_crease() {
            field.boxes = [box(50, 100, 0.8, 100, 0), box(250, 100, 0.8, 100, 0)];
            const image = drawn();
            // Pixel 200's centre lies 50.5 px from the first box and 49.5 px
            // from the second.
            const first = 50.5 / 100, second = 49.5 / 100;
            const joined = second - 0.1 * Math.log(1 + Math.exp(-(first - second) / 0.1));
            near(alpha(image, 200), 0.8 * eased(joined), "the middle between them");
            verify(alpha(image, 200) > 0.8 * eased(second) + 0.05, "darker than the nearer box alone");
        }

        // Each box draws its own peak and ink, and the field passes from one
        // to the other in small steps.
        function test_each_box_draws_its_own_peak_and_ink() {
            field.boxes = [box(0, 60, 0.8, 200, 0), box(340, 60, 0.3, 200, 0, "#ff0000")];
            const image = drawn();
            near(alpha(image, 30), 0.8, "box 0's peak");
            compare(image.red(370, 100), 255, "box 1's red ink");
            near(1 - image.green(370, 100) / 255, 0.3, "box 1's peak");
            let previous = image.green(60, 100);
            for (let px = 62; px <= 340; px += 2) {
                const value = image.green(px, 100);
                verify(Math.abs(value - previous) <= 8, "a gradual pass at pixel " + px + ": " + previous + " to " + value);
                previous = value;
            }
        }

        // Each box's distance is scaled by its own fade.
        function test_each_box_falls_over_its_own_fade() {
            field.boxes = [box(0, 60, 0.8, 40, 0), box(340, 60, 0.8, 160, 0)];
            const image = drawn();
            near(alpha(image, 79), 0.8 * eased(19.5 / 40), "box 0, 19.5 px out");
            near(alpha(image, 320), 0.8 * eased(19.5 / 160), "box 1, 19.5 px out");
        }

        // The halo draws past box 0's ring in its stops' colours, and only
        // when asked.
        function test_the_halo_draws_only_when_asked() {
            ground.color = "#000000";
            const disc = { x: 160, y: 60, w: 80, h: 80, corner: 40, peak: 0.6, fade: 60, inset: 0, ink: "#000000" };
            field.boxes = [disc];
            let image = drawn();
            compare(image.green(200, 55), 0, "no halo while none is asked");
            field.halo = { strength: 0.5, width: 20, ring: 40, stops: ["#00ff00", "#00ff00", "#00ff00", "#00ff00"] };
            image = drawn();
            verify(image.green(200, 55) > 60, "the halo past the ring: " + image.green(200, 55));
            compare(image.red(200, 55), 0, "in its stops' colour");
        }

        // The output is premultiplied: grey ink at 0.5 over black draws half
        // its value.
        function test_the_field_is_premultiplied() {
            ground.color = "#000000";
            field.boxes = [box(100, 200, 0.5, 40, 0, "#808080")];
            const image = drawn();
            verify(Math.abs(image.red(200, 100) - 64) <= 2, "half of the ink's 128: " + image.red(200, 100));
        }

        // A decoration: no pointer handler, no focus and no accessible
        // node, so a passive layer that draws it stays input-free (D026).
        function test_the_field_takes_no_input() {
            compare(field.children.length, 0);
            compare(field.activeFocusOnTab, false);
            compare(field.Accessible.ignored, true);
        }

        // Nothing animates: with its inputs unchanged the window swaps no
        // frame, and a changed box draws one.
        function test_a_still_field_draws_no_frame() {
            field.boxes = [box(100, 100, 0.8, 100, 20)];
            const frames = createTemporaryObject(frameSpy, root, { target: root.Window.window });
            verify(renderedFrame(root), "the field draws");
            frames.clear();
            wait(500);
            compare(frames.count, 0);
            field.boxes = [box(120, 100, 0.8, 100, 20)];
            tryVerify(() => frames.count > 0, 1000, "a moved box draws");
        }
    }

    Component {
        id: frameSpy
        SignalSpy { signalName: "frameSwapped" }
    }
}
