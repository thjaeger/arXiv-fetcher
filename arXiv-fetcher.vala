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

class Status : Object, Mergable<Status> {
    private string _id;
    public string id { get { return _id; } }
    public int version;
    public Gee.HashSet<string> tags { get; private set; }

    public Status(string id, int version) {
        _id = id;
        this.version = version;
        tags = new Gee.HashSet<string>();
    }

    public void set_tag(string tag) {
        if (tags.contains(tag))
            return;
        tags.add(tag);
        tags = tags;
    }

    public void unset_tag(string tag) {
        if (!tags.contains(tag))
            return;
        tags.remove(tag);
        tags = tags;
    }

    public void merge(Status s) {
        if (s.version > version)
            version = s.version;
        if (s.tags.size > 0) {
            tags.add_all(s.tags);
            tags = tags;
        }
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

class Arxiv : Object {
    public static Regex old_format;
    public static Regex new_format;

    Soup.SessionAsync session;
    public Timeout config_timeout;
    const string api = "http://export.arxiv.org/api/query";

    public Gee.HashMap<string, Entry> entries;
    public ListModel<Status> config;

    public Arxiv() {
        config = new ListModel<Status>((s1, s2) => s1.id == s2.id);
        entries = new Gee.HashMap<string, Entry>();

        session = new Soup.SessionAsync();
        config_timeout = new Timeout(5, save_config);

        read_config();
        config.row_inserted.connect((path, iter) => { config_timeout.reset(); });
        config.row_deleted.connect(path => { config_timeout.reset(); });
        config.row_changed.connect((path, iter) => { config_timeout.reset(); });
        load_entries();
    }

    public static string? get_id(string idv, out int version) {
        MatchInfo info;
        version = 0;

        if (old_format.match(idv, 0, out info)) {
            var mv = info.fetch(3);
            if (mv != null && mv != "")
                version = int.parse(mv[1:mv.length]);
            return info.fetch(1).split(".")[0] + "/" + info.fetch(2);
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
        config.foreach(s => {
            if (!entries.has_key(s.id))
                ids.add(s.id);
        });
        if (ids.is_empty)
            return;
        query_ids(ids);
        save_entries();

        foreach (var id in ids)
            entries.get(id).download();
    }

    public bool import(Status s) {
        var ids = new Gee.ArrayList<string>();
        ids.add(s.id);
        query_ids(ids);
        save_entries();
        entries.get(s.id).download();
        config.add(s);
        return true;
    }
/*
    public void update_entries() {
        query_ids(config.keys);
        save_entries();

        foreach (var ke in entries.entries)
            ke.value.download();
    }
*/
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
                var status = new Status(id, version);
                foreach (var str in words[1:words.length])
                    status.tags.add(str);
                config.add(status);
            }
        } catch (Error e) {
            stderr.printf("Error reading config file: %s\n", e.message);
        }
    }

    void save_config() {
        var contents = new StringBuilder();
        config.foreach(s => {
            contents.append(s.id);
            if (s.version > 0)
                contents.append_printf("v%d", s.version);
            foreach (var tag in s.tags)
                contents.append(" " + tag);
            contents.append_c('\n');
        });
        try {
            FileUtils.set_contents(get_config_filename(), contents.str);
        } catch (Error e) {
            stderr.printf("Error saving config file: %s\n", e.message);
        }
    }

}

class TreeModelFilterSort : Gtk.TreeModelFilter, Gtk.TreeSortable {
    Gtk.TreeModelSort sorted_model;

    public TreeModelFilterSort(Gtk.TreeModel child_model) {
        Object(child_model: new Gtk.TreeModelSort.with_model(child_model));
    }

    public bool get_sort_column_id(out int sort_column_id, out Gtk.SortType order) {
        return sorted_model.get_sort_column_id(out sort_column_id, out order);
    }

    public bool has_default_sort_func() {
        return sorted_model.has_default_sort_func();
    }

    public void set_default_sort_func(owned Gtk.TreeIterCompareFunc sort_func) {
        sorted_model.set_default_sort_func((owned)sort_func);
    }

    public void set_sort_column_id(int sort_column_id, Gtk.SortType order) {
        sorted_model.set_sort_column_id(sort_column_id, order);
    }

    public void set_sort_func(int sort_column_id, owned Gtk.TreeIterCompareFunc sort_func) {
        sorted_model.set_sort_func(sort_column_id, (owned)sort_func);
    }

    public new bool convert_child_iter_to_iter(out Gtk.TreeIter iter, Gtk.TreeIter child_iter) {
        Gtk.TreeIter sorted_iter;
        if (!convert_child_iter_to_iter(out sorted_iter, child_iter)) {
            iter = Gtk.TreeIter();
            return false;
        }
        return convert_child_iter_to_iter(out iter, sorted_iter);

    }

    construct {
        sorted_model = (Gtk.TreeModelSort)child_model;
        sorted_model.sort_column_changed.connect(() => {
            sort_column_changed();
        });
    }
}

class AppWindow : Gtk.ApplicationWindow {
    Gtk.TreeView preprint_view;
    TreeModelFilterSort preprint_model;
    Gtk.Entry search_entry;
    Gtk.Button import_button;

    public Gee.ArrayList<Status> selected { get; set; }
    public Entry? entry { get; set; }

    public string clipboard_id { get; set; }
    int clipboard_version;

    Arxiv arxiv;

    internal AppWindow(App app) {
        Object (application: app, title: prog_name);

        set_default_size(800,600);

        arxiv = new Arxiv();

        selected = new Gee.ArrayList<Status>();
//        arxiv.update_entries();

        border_width = 10;

        var vgrid = new Gtk.Grid();
        var hgrid = new Gtk.Grid();
        int hi = 0;

        var search_label = new Gtk.Label("Search: ");
        hgrid.attach(search_label, hi++, 0, 1, 1);

        search_entry = new Gtk.Entry();
        search_entry.changed.connect(() => {
            preprint_view.set_cursor(new Gtk.TreePath(), null, false);
            preprint_model.refilter();
        });
        search_entry.set_size_request(300,-1);
        hgrid.attach(search_entry, hi++, 0, 1, 1);

        import_button = new Gtk.Button.with_mnemonic("_Paste");
        hgrid.attach(import_button, hi++, 0, 1, 1);

        var delete_button = new Gtk.Button.with_mnemonic("_Delete");
        delete_button.sensitive = false;
        delete_button.clicked.connect(on_delete);
        hgrid.attach(delete_button, hi++, 0, 1, 1);

        var todo_button = new Gtk.ToggleButton.with_mnemonic("_TODO");
        todo_button.sensitive = false;
        todo_button.toggled.connect(() => {
            foreach (var s in selected) {
                if (s.tags.contains("TODO") == todo_button.active) {
                    // TODO stdout.printf("This is bad!\n");
                    continue;
                }
                if (todo_button.active)
                    s.set_tag("TODO");
                else
                    s.unset_tag("TODO");
            }
        });
        todo_button.halign = Gtk.Align.END;
        todo_button.hexpand = true;
        hgrid.attach(todo_button, hi++, 0, 1, 1);

        vgrid.attach(hgrid,0,0,1,1);

        var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);

        setup_preprints();

        preprint_view.expand = true;
        preprint_view.set_size_request(750, -1);
        preprint_view.get_selection().changed.connect(on_selection_changed);
        preprint_view.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE);
        preprint_view.row_activated.connect(on_row_activated);

        var scroll1 = new Gtk.ScrolledWindow(null, null);
        scroll1.set_border_width(10);
        scroll1.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scroll1.add(preprint_view);
        paned.pack1(scroll1, true, true);
        scroll1.set_size_request(-1,350);

        var field_grid = new Gtk.Grid();
        add_field(field_grid, "Author(s)", e => string.joinv(", ", e.authors));
        add_field(field_grid, "Title", e => e.title);
        add_field(field_grid, "Abstract", e => e.summary);
        add_field(field_grid, "Comment", e => e.comment);
        add_field(field_grid, "ArXiv ID", e => "<a href=\"%s\">%sv%d</a>".printf(e.arxiv, e.id, e.version), true);

        var scroll2 = new Gtk.ScrolledWindow(null, null);
        scroll2.set_border_width(10);
        scroll2.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scroll2.add_with_viewport(field_grid);
        paned.pack2(scroll2, true, true);
        scroll2.set_size_request(-1,200);

        vgrid.attach(paned,0,1,1,1);
        add(vgrid);

        destroy.connect(() => { arxiv.config_timeout.trigger(); });

        var clipboard = Gtk.Clipboard.get_for_display(get_display(), Gdk.SELECTION_CLIPBOARD);
        clipboard.owner_change.connect((e) => {
            clipboard.request_text((c, text) => { clipboard_id = text == null ? null : Arxiv.get_id(text, out clipboard_version); });
        });
        var selection_clipboard = Gtk.Clipboard.get_for_display(get_display(), Gdk.SELECTION_PRIMARY);
        selection_clipboard.owner_change.connect((e) => {
            selection_clipboard.request_text((c, text) => { clipboard_id = text == null ? null : Arxiv.get_id(text, out clipboard_version); });
        });

        notify["clipboard-id"].connect((s, p) => { import_button.sensitive = clipboard_id != null; });

        clipboard.owner_change(new Gdk.Event(Gdk.EventType.NOTHING));

        import_button.clicked.connect(() => { import_clipboard(); });

        notify["selected"].connect((ss, p) => {
            entry = selected.size != 1 ? null : arxiv.entries.get(selected[0].id);
            delete_button.sensitive = selected.size > 0;
            bool? active = null;
            foreach (var s in selected) {
                if (active == null) {
                    active = s.tags.contains("TODO");
                } else if (active != s.tags.contains("TODO")) {
                    todo_button.active = false;
                    todo_button.sensitive = false;
                    return;
                }
            }
            todo_button.active = active != null && active;
            todo_button.sensitive = active != null;
        });

        arxiv.config.row_inserted.connect((path, iter) => {
            Gtk.TreeIter preprint_iter;
            if (!preprint_model.convert_child_iter_to_iter(out preprint_iter, iter))
                return;
            preprint_view.get_selection().select_iter(preprint_iter);
        });

        search_entry.grab_focus();
    }

    void import_clipboard() {
        if (clipboard_id == null)
            return;
        preprint_view.get_selection().unselect_all();
        arxiv.import(new Status(clipboard_id, clipboard_version));
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
                    field.set_markup(entry != null ? f(entry) : "");
                else
                    field.set_text(entry != null ? f(entry) : "");
            });
    }

    void setup_preprints() {
        preprint_view = new Gtk.TreeView();
        var status_column_id = arxiv.config.add_object_column<Status>(s => s);
        assert(status_column_id == 0);
        var authors_column_id = arxiv.config.add_string_column(s => {
            string[] authors = {};
            foreach (var author in arxiv.entries.get(s.id).authors) {
                var names = author.split(" ");
                authors += names[names.length-1];
            }
            return string.joinv(", ", authors);
        });
        var title_column_id = arxiv.config.add_string_column(s => arxiv.entries.get(s.id).title);
        var weight_column_id = arxiv.config.add_int_column(s => s.tags.contains("TODO") ? 700 : 400);

        preprint_model = new TreeModelFilterSort(arxiv.config);
        preprint_model.set_visible_func(do_filter);
        preprint_model.set_default_sort_func((model, iter1, iter2) => {
                int i1 = model.get_path(iter1).get_indices()[0];
                int i2 = model.get_path(iter2).get_indices()[0];
                return i2 - i1;

        });

        preprint_view.set_model(preprint_model);
        var authors_renderer = new Gtk.CellRendererText();
        authors_renderer.ellipsize = Pango.EllipsizeMode.END;
        preprint_view.insert_column_with_attributes(-1, "Author(s)", authors_renderer, "text", authors_column_id);
        var title_renderer = new Gtk.CellRendererText();
        title_renderer.ellipsize = Pango.EllipsizeMode.END;
        preprint_view.insert_column_with_attributes(-1, "Title", title_renderer, "text", title_column_id);
        var authors_column = preprint_view.get_column(0);
        authors_column.set_sizing(Gtk.TreeViewColumnSizing.FIXED);
        authors_column.set_fixed_width(200);
        authors_column.resizable = true;
        authors_column.set_sort_column_id(authors_column_id);
        var title_column = preprint_view.get_column(1);
        title_column.resizable = true;
        title_column.set_sort_column_id(title_column_id);
        title_column.add_attribute(title_renderer, "weight", weight_column_id);
    }

    void on_selection_changed(Gtk.TreeSelection selection) {
        Gtk.TreeModel model;

        selected.clear();
        var rows = selection.get_selected_rows(out model);
        rows.foreach(row => {
            Gtk.TreeIter iter;
            if (model.get_iter(out iter, row)) {
                Status s;
                model.get(iter, 0, out s);
                selected.add(s);
            }
        });
        selected = selected;
    }

    void on_row_activated(Gtk.TreePath path, Gtk.TreeViewColumn column) {
        Gtk.TreeIter iter;
        if (!preprint_model.get_iter(out iter, path))
            return;
        Status s;
        preprint_model.get(iter, 0, out s);
        var pdf = arxiv.entries.get(s.id).get_filename();
        try {
            Gtk.show_uri(null, "file://" + pdf, Gdk.CURRENT_TIME);
        } catch (GLib.Error e) {
            stdout.printf("Error opening %s: %s", pdf, e.message);
        }
    }

    void on_delete() {
        bool ok = false;
        var msg = new Gtk.MessageDialog(this, Gtk.DialogFlags.MODAL, Gtk.MessageType.INFO, Gtk.ButtonsType.CANCEL, "%d %s about to be deleted.", selected.size, selected.size == 1 ? "preprint is" : "preprints are");
        msg.add_button("_Delete", Gtk.ResponseType.OK);
        msg.response.connect((response_id) => {
            ok = response_id == Gtk.ResponseType.OK;
            msg.destroy();
        });
        msg.run();
        if (!ok)
            return;
        var to_delete = selected.to_array();
        foreach (var s in to_delete)
            arxiv.config.remove(s);
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
        Status s;
        model.get(iter, 0, out s);
        Entry e = arxiv.entries.get(s.id);
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

static const string[] subjects = {
    "stat",
    "stat\\.AP",
    "stat\\.CO",
    "stat\\.ML",
    "stat\\.ME",
    "stat\\.TH",
    "q-bio",
    "q-bio\\.BM",
    "q-bio\\.CB",
    "q-bio\\.GN",
    "q-bio\\.MN",
    "q-bio\\.NC",
    "q-bio\\.OT",
    "q-bio\\.PE",
    "q-bio\\.QM",
    "q-bio\\.SC",
    "q-bio\\.TO",
    "cs",
    "cs\\.AR",
    "cs\\.AI",
    "cs\\.CL",
    "cs\\.CC",
    "cs\\.CE",
    "cs\\.CG",
    "cs\\.GT",
    "cs\\.CV",
    "cs\\.CY",
    "cs\\.CR",
    "cs\\.DS",
    "cs\\.DB",
    "cs\\.DL",
    "cs\\.DM",
    "cs\\.DC",
    "cs\\.GL",
    "cs\\.GR",
    "cs\\.HC",
    "cs\\.IR",
    "cs\\.IT",
    "cs\\.LG",
    "cs\\.LO",
    "cs\\.MS",
    "cs\\.MA",
    "cs\\.MM",
    "cs\\.NI",
    "cs\\.NE",
    "cs\\.NA",
    "cs\\.OS",
    "cs\\.OH",
    "cs\\.PF",
    "cs\\.PL",
    "cs\\.RO",
    "cs\\.SE",
    "cs\\.SD",
    "cs\\.SC",
    "nlin",
    "nlin\\.AO",
    "nlin\\.CG",
    "nlin\\.CD",
    "nlin\\.SI",
    "nlin\\.PS",
    "math",
    "math\\.AG",
    "math\\.AT",
    "math\\.AP",
    "math\\.CT",
    "math\\.CA",
    "math\\.CO",
    "math\\.AC",
    "math\\.CV",
    "math\\.DG",
    "math\\.DS",
    "math\\.FA",
    "math\\.GM",
    "math\\.GN",
    "math\\.GT",
    "math\\.GR",
    "math\\.HO",
    "math\\.IT",
    "math\\.KT",
    "math\\.LO",
    "math\\.MP",
    "math\\.MG",
    "math\\.NT",
    "math\\.NA",
    "math\\.OA",
    "math\\.OC",
    "math\\.PR",
    "math\\.QA",
    "math\\.RT",
    "math\\.RA",
    "math\\.SP",
    "math\\.ST",
    "math\\.SG",
    "astro-ph",
    "cond-mat",
    "cond-mat\\.dis-nn",
    "cond-mat\\.mes-hall",
    "cond-mat\\.mtrl-sci",
    "cond-mat\\.other",
    "cond-mat\\.soft",
    "cond-mat\\.stat-mech",
    "cond-mat\\.str-el",
    "cond-mat\\.supr-con",
    "gr-qc",
    "hep-ex",
    "hep-lat",
    "hep-ph",
    "hep-th",
    "math-ph",
    "nucl-ex",
    "nucl-th",
    "physics",
    "physics\\.acc-ph",
    "physics\\.ao-ph",
    "physics\\.atom-ph",
    "physics\\.atm-clus",
    "physics\\.bio-ph",
    "physics\\.chem-ph",
    "physics\\.class-ph",
    "physics\\.comp-ph",
    "physics\\.data-an",
    "physics\\.flu-dyn",
    "physics\\.gen-ph",
    "physics\\.geo-ph",
    "physics\\.hist-ph",
    "physics\\.ins-det",
    "physics\\.med-ph",
    "physics\\.optics",
    "physics\\.ed-ph",
    "physics\\.soc-ph",
    "physics\\.plasm-ph",
    "physics\\.pop-ph",
    "physics\\.space-ph",
    "quant-ph",
};

int main (string[] args) {
    try {
        Arxiv.old_format = new Regex("("+string.joinv("|", subjects)+")/([[:digit:]]{7})(v[[:digit:]]+)?");
        Arxiv.new_format = new Regex("([[:digit:]]{4}\\.[[:digit:]]{4})(v[[:digit:]]+)?");
        Entry.url_id = new Regex("^http://arxiv.org/abs/(.*)$");
    } catch (GLib.RegexError e) {
        stderr.printf("Regex Error: %s\n", e.message);
    }

    return new App().run(args);
}
