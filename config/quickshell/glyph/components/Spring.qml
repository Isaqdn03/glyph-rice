import QtQuick

// local: value follows `to` on a critically damped spring: Rune's duration with bounce 0 (rune-motion,
// github.com/anomalyco/rune, MIT, © Anomaly). ω = 2π / period, in closed form, so any frame length is exact. A new `to`
// keeps the speed it has, where a Behavior on a fixed curve restarts it. Not SpringAnimation: that steps every 16 ms
// whatever the screen runs at, and it takes no period. It ticks only while it moves. instant: no motion, value is `to`
FrameAnimation {
    property real to: 0
    property real period: 0.3 // s; settled in about 1.4 × this
    property bool instant: false
    property real epsilon: 0.001 // close enough, in value's units
    property real value: 0
    property real velocity: 0
    property bool ready: false

    function settle() {
        value = to;
        velocity = 0;
        running = false;
    }
    function kick() {
        if (!ready) return;
        if (instant || (Math.abs(to - value) <= epsilon && Math.abs(velocity) <= epsilon * 10)) settle();
        else running = true;
    }
    // at v, at rest, and on towards `to` from there
    function jump(v) {
        value = v;
        velocity = 0;
        kick();
    }

    onToChanged: kick()
    onInstantChanged: kick()
    onTriggered: {
        const dt = Math.min(frameTime, 1 / 24); // a long first frame (a window being built) doesn't eat the motion
        const w = 2 * Math.PI / period, a = value - to, b = velocity + w * a, e = Math.exp(-w * dt);
        value = to + (a + b * dt) * e;
        velocity = (b - w * (a + b * dt)) * e;
        if (Math.abs(value - to) <= epsilon && Math.abs(velocity) <= epsilon * 10) settle();
    }
    Component.onCompleted: {
        value = to;
        ready = true;
    }
}
