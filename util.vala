/* vim: set cin et sw=4 : */

public class Util {
    // http://www.mail-archive.com/gtk-app-devel-list@gnome.org/msg17825.html
    public static void save_variant(string filename, string description, string type_string, Variant v) {
        assert(v.is_of_type(new VariantType(type_string)));
        try {
            // https://mail.gnome.org/archives/vala-list/2011-June/msg00200.html
            unowned uint8[] data = (uint8[])v.get_data();
            data.length = (int)v.get_size();
            FileUtils.set_data(filename, data);
        } catch (Error e) {
            stderr.printf("Error saving %s: %s\n", description, e.message);
        }
    }

    public delegate void ProcessVariant(Variant v);

    public static void load_variant(string filename, string description, string type_string, ProcessVariant f) {
        if (!File.new_for_path(filename).query_exists())
            return;
        try {
            uint8[] data;
            if (FileUtils.get_data(filename, out data))
                f(Variant.new_from_data<void>(new VariantType(type_string), data, false));
        } catch (Error e) {
            stderr.printf("Error loading %s: %s\n", description, e.message);
        }
    }

    public delegate void ProcessLine(string line);

    public static void load_lines(string filename, string description, ProcessLine f) {
        if (!File.new_for_path(filename).query_exists())
            return;
        try {
            string contents;
            if (FileUtils.get_contents(filename, out contents))
                foreach (var search in contents.split("\n"))
                    if (search != "")
                        f(search);
        } catch (FileError e) {
            stderr.printf("Error loading %s: %s\n", description, e.message);
        }
    }

    public static void save_contents(string filename, string description, string contents) {
        try {
            FileUtils.set_contents(filename, contents);
        } catch (Error e) {
            stderr.printf("Error saving %s: %s\n", description, e.message);
        }
    }
}
