/* vim: set cin et sw=4 : */
using GLib;

static const string prog_name = "arXiv-fetcher";

class Timeout {
    public delegate void Func();

    uint source;
    uint interval;
    unowned Func f;

    public Timeout(uint interval, Func f) {
        source = 0;
        this.interval = interval;
        this.f = f;
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
}

class Status {
    public int version;
    public Gee.HashSet<string> tags;

    public Status(int version) {
        this.version = version;
        tags = new Gee.HashSet<string>();
    }
}

class Entry {
    public static const string variant_type = "(sissssassssas)";
    public static Regex url_id;

    public Entry() {
        updated = "";
        published = "";
        title = "";
        summary = "";
        authors = new string[0];
        comment = "";
        arxiv = "";
        pdf = "";
        categories = new string[] { "" };
    }

    public string id;
    public int version;
    public string updated;
    public string published;
    public string title;
    public string summary;
    public string[] authors;
    public string comment;
    public string arxiv;
    public string pdf;
    public string[] categories;

    public Variant get_variant() {
        return new Variant.tuple(new Variant[] {
                id,
                version,
                updated,
                published,
                title,
                summary,
                authors,
                comment,
                arxiv,
                pdf,
                categories
            });
    }

    public Entry.from_variant(Variant v) {
        int i = 0;
        id         =   (string)v.get_child_value(i++);
        version    =      (int)v.get_child_value(i++);
        updated    =   (string)v.get_child_value(i++);
        published  =   (string)v.get_child_value(i++);
        title      =   (string)v.get_child_value(i++);
        summary    =   (string)v.get_child_value(i++);
        authors    = (string[])v.get_child_value(i++);
        comment    =   (string)v.get_child_value(i++);
        arxiv      =   (string)v.get_child_value(i++);
        pdf        =   (string)v.get_child_value(i++);
        categories = (string[])v.get_child_value(i++);
    }

    public string get_filename() {
        return Path.build_filename(
                Environment.get_user_cache_dir(),
                prog_name,
                "preprints",
                id.replace("/","_") + @"v$version.pdf"
            );

    }

    public bool download() {
        var filename = get_filename();
        var file = File.new_for_path(filename);
        var dir = file.get_parent();
        try {
            if (!dir.query_exists())
                dir.make_directory_with_parents();
            if (file.query_exists())
                return true;

            FileIOStream tmpstream;
            var tmp = File.new_tmp(null, out tmpstream);
            var tmpname = tmp.get_path();
            tmpstream.close();
            var wget = @"wget --user-agent=Lynx -O \"$tmpname\" $pdf";
            if (!Process.spawn_command_line_sync(wget))
                return false;
            tmp.move(file, FileCopyFlags.NONE);
            Thread.usleep(1000000);
            return true;
        } catch (Error e) {
            stderr.printf("Error downloading %s: %s\n", filename, e.message);
            return false;
        }
    }

    public Entry.from_xml(Xml.Node* node) {
        this();
        for (Xml.Node* i = node->children; i != null; i = i->next) {
            if (i->name == "id") {
                MatchInfo info;
                if (!url_id.match(i->get_content(), 0, out info))
                    continue;
                id = Arxiv.get_id(info.fetch(1), out version);
            } else if (i->name == "updated") {
                updated = i->get_content();
            } else if (i->name == "published") {
                published = i->get_content();
            } else if (i->name == "title") {
                title = i->get_content().replace("\n ","");
            } else if (i->name == "summary") {
                summary = i->get_content().replace("\n"," ").strip();
            } else if (i->name == "author") {
                for (Xml.Node* j = i->children; j != null; j = j->next)
                    if (j->name == "name")
                        authors += j->get_content();
            } else if (i->name == "comment") {
                comment = i->get_content().replace("\n ","");
            } else if (i->name == "link") {
                if (i->get_prop("type") == "text/html")
                    arxiv = i->get_prop("href");
                else if (i->get_prop("type") == "application/pdf")
                    pdf = i->get_prop("href");
            } else if (i->name == "primary_category") {
                categories[0] = i->get_content();
            } else if (i->name == "category") {
                categories += i->get_prop("term");
            }
        }
    }
}

class Arxiv {
    public static Regex old_format;
    public static Regex new_format;

    Soup.SessionAsync session;
    public Timeout config_timeout;
    const string api = "http://export.arxiv.org/api/query";

    public Gee.HashMap<string, Entry> entries;
    public Gee.HashMap<string, Status> config;


    public Arxiv() {
        config = new Gee.HashMap<string, Status>();
        entries = new Gee.HashMap<string, Entry>();

        session = new Soup.SessionAsync();
        config_timeout = new Timeout(5, save_config);

        read_config();
        load_entries();
    }

    public static string? get_id(string idv, out int version) {
        MatchInfo info;
        version = 0;

        if (old_format.match(idv, 0, out info)) {
            var mv = info.fetch(4);
            if (mv != null && mv != "")
                version = int.parse(mv[1:mv.length]);
            return info.fetch(1) + "/" + info.fetch(3);
        }
        if (new_format.match(idv, 0, out info)) {
            var mv = info.fetch(2);
            if (mv != null && mv != "")
                version = int.parse(mv[1:mv.length]);
            return info.fetch(1);
        }
        return null;
    }

    void save_entries() {
        // http://www.mail-archive.com/gtk-app-devel-list@gnome.org/msg17825.html
        try {
            var dbname = Path.build_filename(Environment.get_user_cache_dir(), prog_name, "database");
            Variant[] va = {};
            foreach (var ke in entries.entries)
                va += ke.value.get_variant();
            Variant db = new Variant.array(new VariantType(Entry.variant_type), va);
            // https://mail.gnome.org/archives/vala-list/2011-June/msg00200.html
            unowned uint8[] data = (uint8[]) db.get_data();
            data.length = (int)db.get_size();
            FileUtils.set_data(dbname, data);
        } catch (Error e) {
            stderr.printf("Error saving database: %s\n", e.message);
        }
    }

    void load_entries() {
        try {
            var dbname = Path.build_filename(Environment.get_user_cache_dir(), prog_name, "database");
            uint8[] data;
            if (FileUtils.get_data(dbname, out data)) {
                Variant db = Variant.new_from_data<void>(new VariantType("a"+Entry.variant_type), data, false);
                for (int i = 0; i < db.n_children(); i++) {
                    Entry entry = new Entry.from_variant(db.get_child_value(i));
                    entries.set(entry.id, entry);
                }
            }
        } catch (Error e) {
            stderr.printf("Error loading database: %s\n", e.message);
        }
        var ids = new Gee.ArrayList<string>();
        foreach (var id in config.keys)
            if (!entries.has_key(id))
                ids.add(id);
        if (ids.is_empty)
            return;
        query_ids(ids);
        save_entries();

        foreach (var id in ids)
            entries.get(id).download();
    }

    public void update_entries() {
        query_ids(config.keys);
        save_entries();

        foreach (var ke in entries.entries)
            ke.value.download();
    }

    void query_n(string[] ids, int n) {
        var query = api + @"?max_results=$n&id_list=" + string.joinv(",", ids);
        stdout.printf("%s\n", query);

        var message = new Soup.Message("GET", query);
        session.send_message(message);

        Xml.Doc* doc = Xml.Parser.parse_doc((string)message.response_body.data);
        if (doc == null)
            return;

        Xml.Node* feed = doc->get_root_element();
        if (feed->name == "feed") {
            for (Xml.Node* i = feed->children; i != null; i = i->next)
                if (i->name == "entry") {
                    Entry entry = new Entry.from_xml(i);
                    if (entry.id == null)
                        error("Got invalid response from arXiv\n");
                    entries.set(entry.id, entry);
                }
        }
        delete doc;
    }

    void query_ids(Gee.Collection<string> ids) {
        const int n = 100;

        string[] ids_array = {};
        foreach (var id in ids) {
            ids_array += id;
            if (ids_array.length == n) {
                query_n(ids_array, n);
                ids_array = {};
                Thread.usleep(3000000);
            }
        }
        query_n(ids_array, n);
    }

    static string get_config_filename() {
        return Path.build_filename(Environment.get_user_config_dir(), prog_name, "preprints");
    }

    void read_config() {
        var file = File.new_for_path(get_config_filename());
        if (!file.query_exists())
            return;

        try {
            var dis = new DataInputStream(file.read());
            string line;
            while ((line = dis.read_line(null)) != null) {
                int version;
                string[] words = line.split(" ");
                string id = get_id(words[0], out version);
                if (id == null) {
                    stderr.printf("Warning: couldn't parse arXiv id %s.\n", words[0]);
                    continue;
                }
                var status = new Status(version);
                foreach (var str in words[1:words.length])
                    status.tags.add(str);
                config.set(id, status);
            }
        } catch (Error e) {
            stderr.printf("Error reading config file: %s\n", e.message);
        }
    }

    void save_config() {
        var contents = new StringBuilder();
        foreach (var ke in config.entries) {
            contents.append(ke.key);
            if (ke.value.version > 0)
                contents.append_printf("v%d", ke.value.version);
            foreach (var tag in ke.value.tags)
                contents.append(" " + tag);
            contents.append_c('\n');
        }
        try {
            FileUtils.set_contents(get_config_filename(), contents.str);
        } catch (Error e) {
            stderr.printf("Error saving config file: %s\n", e.message);
        }
    }

}

class AppWindow : Gtk.ApplicationWindow {
    Gtk.TreeView preprint_view;
    Gtk.ListStore preprint_model;
    Gtk.TreeModelFilter filtered_model;
    Gtk.ToggleButton todo_button;
    Gtk.Entry search_entry;

    public Entry entry { get; set; }

    Arxiv arxiv;

    enum Column {
        ID,
        AUTHORS,
        TITLE,
        WEIGHT,
    }

    internal AppWindow(App app) {
        Object (application: app, title: prog_name);

        set_default_size(800,600);

        arxiv = new Arxiv();
//        arxiv.update_entries();

        border_width = 10;

        var vgrid = new Gtk.Grid();
        var hgrid = new Gtk.Grid();

        var search_label = new Gtk.Label("Search: ");
        hgrid.attach(search_label,0,0,1,1);

        search_entry = new Gtk.Entry();
        search_entry.changed.connect(() => { filtered_model.refilter(); });
        search_entry.set_size_request(300,-1);
        hgrid.attach(search_entry,1,0,1,1);

        todo_button = new Gtk.ToggleButton.with_label("TODO");
        todo_button.sensitive = false;
        todo_button.notify["active"].connect(on_todo_button_toggled);
        todo_button.halign = Gtk.Align.END;
        todo_button.hexpand = true;
        hgrid.attach(todo_button,2,0,1,1);

        vgrid.attach(hgrid,0,0,1,1);

        var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);

        setup_preprints();
        populate_preprints();
        preprint_view.expand = true;
        preprint_view.set_size_request(750, -1);
        preprint_view.get_selection().changed.connect(on_selection_changed);
        preprint_view.row_activated.connect(on_row_activated);
        preprint_model.set_sort_column_id(Column.AUTHORS, Gtk.SortType.ASCENDING);

        var scroll1 = new Gtk.ScrolledWindow(null, null);
        scroll1.set_border_width(10);
        scroll1.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scroll1.add(preprint_view);
        paned.pack1(scroll1, true, true);
        scroll1.set_size_request(-1,350);

        var field_grid = new Gtk.Grid();
        add_field(field_grid, "Author(s)", (e) => string.joinv(", ", e.authors));
        add_field(field_grid, "Title", (e) => e.title);
        add_field(field_grid, "Abstract", (e) => e.summary);
        add_field(field_grid, "Comment", (e) => e.comment);
        add_field(field_grid, "ArXiv ID", (e) => "<a href=\"%s\">%sv%d</a>".printf(e.arxiv, e.id, e.version), true);

        var scroll2 = new Gtk.ScrolledWindow(null, null);
        scroll2.set_border_width(10);
        scroll2.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scroll2.add_with_viewport(field_grid);
        paned.pack2(scroll2, true, true);
        scroll2.set_size_request(-1,200);

        vgrid.attach(paned,0,1,1,1);
        add(vgrid);

        destroy.connect(() => { arxiv.config_timeout.trigger(); });
    }

    delegate string EntryField(Entry e);

    void add_field(Gtk.Grid grid, string name, EntryField f, bool markup = false) {
        var field_label = new Gtk.Label(@"<b>$name: </b> ");
        field_label.xalign = 0.0f;
        field_label.yalign = 0.0f;
        field_label.expand = false;
        field_label.use_markup = true;

        var field = new Gtk.Label("");
        field.wrap = true;
        field.xalign = 0.0f;
        field.yalign = 0.0f;

        int n = 0;
        while (grid.get_child_at(1,n) != null)
            n++;
        grid.attach(field_label, 0, n, 1, 1);
        grid.attach(field, 1, n, 1, 1);

        this.notify["entry"].connect((s, p) => {
                if (markup)
                    field.set_markup(f(entry));
                else
                    field.set_text(f(entry));
            });
    }

    void setup_preprints() {
        preprint_view = new Gtk.TreeView();
        preprint_model = new Gtk.ListStore(4, typeof(string), typeof(string), typeof(string), typeof(int));
        filtered_model = new Gtk.TreeModelFilter(preprint_model, null);
        filtered_model.set_visible_func(do_filter);

        preprint_view.set_model(filtered_model);
        var authors_renderer = new Gtk.CellRendererText();
        authors_renderer.ellipsize = Pango.EllipsizeMode.END;
        preprint_view.insert_column_with_attributes (-1, "Author(s)", authors_renderer, "text", Column.AUTHORS);
        var title_renderer = new Gtk.CellRendererText();
        title_renderer.ellipsize = Pango.EllipsizeMode.END;
        preprint_view.insert_column_with_attributes (-1, "Title", title_renderer, "text", Column.TITLE);
        var authors_column = preprint_view.get_column(0);
        authors_column.resizable = true;
        authors_column.set_sort_column_id(Column.AUTHORS);
        var title_column = preprint_view.get_column(1);
        title_column.resizable = true;
        title_column.set_sort_column_id(Column.TITLE);
        title_column.add_attribute(title_renderer, "weight", Column.WEIGHT);
    }

    void populate_preprints() {
        Gtk.TreeIter iter;

        foreach (var ke in arxiv.entries.entries) {
            preprint_model.append(out iter);
            string[] authors = {};
            foreach (var author in ke.value.authors) {
                var names = author.split(" ");
                authors += names[names.length-1];
            }
            preprint_model.set(iter,
                    Column.ID, ke.key,
                    Column.AUTHORS, string.joinv(", ", authors),
                    Column.TITLE, ke.value.title,
                    Column.WEIGHT,  arxiv.config.get(ke.key).tags.contains("TODO") ? 700 : 400
                );
        }
    }

    void on_selection_changed(Gtk.TreeSelection selection) {
        Gtk.TreeModel model;
        Gtk.TreeIter iter;

        if (selection.get_selected(out model, out iter)) {
            string id;
            int weight;
            model.get(iter, Column.ID, out id, Column.WEIGHT, out weight);
            entry = arxiv.entries.get(id);
            todo_button.active = arxiv.config.get(id).tags.contains("TODO");
            todo_button.sensitive = true;
        } else {
            todo_button.active = false;
            todo_button.sensitive = false;
        }
    }

    void on_row_activated(Gtk.TreePath path, Gtk.TreeViewColumn column) {
        Gtk.TreeIter iter;
        if (!filtered_model.get_iter(out iter, path))
            return;
        string id;
        filtered_model.get(iter, Column.ID, out id);
        var pdf = arxiv.entries.get(id).get_filename();
        try {
            Gtk.show_uri(null, "file://" + pdf, Gdk.CURRENT_TIME);
        } catch (GLib.Error e) {
            stdout.printf("Error opening %s: %s", pdf, e.message);
        }
    }

    void on_todo_button_toggled() {
        Gtk.TreeModel model;
        Gtk.TreeIter iter;
        if (preprint_view.get_selection().get_selected(out model, out iter)) {
            string id;
            filtered_model.get(iter, Column.ID, out id);
            if (todo_button.active)
                arxiv.config.get(id).tags.add("TODO");
            else
                arxiv.config.get(id).tags.remove("TODO");

            Gtk.TreeIter child_iter;
            filtered_model.convert_iter_to_child_iter(out child_iter, iter);
            preprint_model.set(child_iter, Column.WEIGHT, todo_button.active ? 700:400);
            arxiv.config_timeout.reset();
        }
    }

    bool match_array(Regex re, string[] arr) throws GLib.RegexError {
        foreach (var str in arr)
            if (re.match(str))
                return true;
        return false;
    }

    bool do_filter(Gtk.TreeModel model, Gtk.TreeIter iter) {
        if (search_entry.text == "")
            return true;
        string id;
        model.get(iter, Column.ID, out id);
        Entry e = arxiv.entries.get(id);
        Status s = arxiv.config.get(id);
        foreach (var str in search_entry.text.split(" ")) {
            if (str == "")
                continue;
            try {
                Regex re = new Regex(str, GLib.RegexCompileFlags.CASELESS);
                if (
                        !re.match(e.title) &&
                        !re.match(e.summary) &&
                        !match_array(re, e.authors) &&
                        !re.match(e.comment) &&
                        !match_array(re, e.categories) &&
                        !match_array(re, s.tags.to_array())
                   )
                    return false;
            } catch (GLib.RegexError e) {
            }
        }

        return true;
    }
}

class App : Gtk.Application {
    protected override void activate() {
        new AppWindow(this).show_all();
    }

    internal App() {
        Object(application_id: @"org.$prog_name.$prog_name");
    }
}

int main (string[] args) {
    try {
        Arxiv.old_format = new Regex("^([[:lower:]-]+)(\\.[[:upper:]]{2})?/([[:digit:]]{7})(v[[:digit:]]+)?$");
        Arxiv.new_format = new Regex("^([[:digit:]]{4}\\.[[:digit:]]{4})(v[[:digit:]]+)?");
        Entry.url_id = new Regex("^http://arxiv.org/abs/(.*)$");
    } catch (GLib.RegexError e) {
        stderr.printf("Regex Error: %s\n", e.message);
    }

    return new App().run(args);
}
