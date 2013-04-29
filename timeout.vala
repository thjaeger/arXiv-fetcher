/* vim: set cin et sw=4 : */

public class Timeout {
    public delegate void Func();

    uint source;
    uint interval;
    unowned Func f;

    static Gee.ArrayList<weak Timeout> all = new Gee.ArrayList<weak Timeout>();

    public Timeout(uint interval, Func f) {
        source = 0;
        this.interval = interval;
        this.f = f;
        all.add(this);
    }

    ~Timeout() {
        all.remove(this);
    }

    public void reset() {
        if (source > 0)
            GLib.Source.remove(source);
        source = GLib.Timeout.add_seconds(interval, () => {
                source = 0;
                f();
                return false;
            });
    }

    public void trigger() {
        if (source > 0) {
            GLib.Source.remove(source);
            f();
        }
    }

    public static void trigger_all() {
        foreach (var timeout in all)
            timeout.trigger();
    }
}
