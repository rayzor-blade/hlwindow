import window.Gamepad;
import window.GamepadButton;
import window.GamepadAxis;

class Checks {
    static var missing:Gamepad = 0;
    static var snapshot:haxe.io.Bytes;
    static var events:haxe.io.Bytes;
    static var sum:Float = 0;

    static function require(value:Bool, message:String):Void {
        if (!value) throw message;
    }

    static function sampleAbsent():Void {
        for (_ in 0...8192) {
            require(!missing.valid(), "invalid handle became valid");
            require(!missing.snapshot(snapshot), "invalid snapshot succeeded");
            require(!missing.pressed(GamepadButton.South), "invalid button was pressed");
            sum += missing.button(GamepadButton.LeftTrigger) + missing.axis(GamepadAxis.LeftY);
        }
    }

    static function least(run:Void->Void):Float {
        var best = Math.POSITIVE_INFINITY;
        for (_ in 0...5) {
            var empty = hl.Gc.stats().totalAllocated;
            var reading = hl.Gc.stats().totalAllocated - empty;
            var before = hl.Gc.stats().totalAllocated;
            run();
            var used = hl.Gc.stats().totalAllocated - before - reading;
            if (used < best) best = used;
        }
        return Math.max(0, best);
    }

    static function main():Void {
        var available = Gamepad.available();
        Sys.println('Backend available: ' + available + '; controllers: ' + Gamepad.count());
        if (!available) Sys.println(Gamepad.error());
        require(Gamepad.at(-1) == 0, "negative index returned a controller");
        require(Gamepad.fromId(0) == 0, "zero device ID became valid");
        require(!missing.hasButton(GamepadButton.South), "invalid button capability");
        require(!missing.hasAxis(GamepadAxis.LeftY), "invalid axis capability");
        require(!missing.rumbleSupported() && !missing.rumble(1, 1, 0.1), "invalid rumble accepted");
        require(missing.name() == "", "invalid name was not empty");
        snapshot = haxe.io.Bytes.alloc(176);
        snapshot.fill(0, snapshot.length, 99);
        require(!missing.snapshot(snapshot), "invalid snapshot accepted");
        for (i in 0...snapshot.length) require(snapshot.get(i) == 99, "failed snapshot wrote bytes");
        events = haxe.io.Bytes.alloc(31);
        events.fill(0, 31, 77);
        require(Gamepad.drain(events) == 0, "short event buffer consumed events");
        for (i in 0...31) require(events.get(i) == 77, "short drain wrote bytes");
        events = haxe.io.Bytes.alloc(32 * 64);
        while (Gamepad.drain(events) == 64) {}
        Gamepad.poll();
        sampleAbsent();
        var allocated = least(sampleAbsent);
        require(allocated == 0, 'absent-controller reads allocated ' + allocated + ' bytes');
        require(sum == 0, "invalid controls had nonzero values");
        Sys.println('Gamepad checks passed; absent-controller sample allocation: ' + allocated);
    }
}
