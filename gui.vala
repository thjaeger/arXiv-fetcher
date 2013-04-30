/* vim: set cin et sw=4 : */

static const string prog_name = "arXiv-fetcher";

class LibraryPage : Gtk.Grid {

}

class TagsPage : Gtk.Grid {
    Data data;

    Gtk.CheckButton bold_button;
    Gtk.CheckButton use_color_button;
    Gtk.ColorButton color_button;
    Gtk.Button remove_button;

    bool updating_view = false;

    Gtk.TreeView view;

    public TagsPage(Data data) {
        this.data = data;

        view = new Gtk.TreeView();
        view.set_model(data.tags);
        view.reorderable = true;
        view.hexpand = true;
        view.vexpand = true;

        view.insert_column_with_data_func(-1, "★", new CellRendererStar(20, 20), (column, cell, model, iter) => {
            Tag tag;
            model.get(iter, 0, out tag);
            var cell_star = cell as CellRendererStar;
            cell_star.starred = true;
            cell_star.color = tag.color == null ? null : new RGB.with_rgb(tag.color.red, tag.color.blue, tag.color.green);
        });

        var tagname_renderer = new Gtk.CellRendererText();
        view.insert_column_with_data_func(-1, "Tags", tagname_renderer, (column, cell, model, iter) => {
            Tag tag;
            model.get(iter, 0, out tag);
            var cell_text = cell as Gtk.CellRendererText;
            cell_text.text = tag.name;
            cell_text.editable = true;
        });

        attach(view, 0, 0, 1, 1);

        tagname_renderer.edited.connect((path, new_text) => {
            Gtk.TreeIter iter;
            if (!data.tags.get_iter_from_string(out iter, path))
                return;
            Tag tag;
            data.tags.get(iter, 0, out tag);
            if (new_text == "") {
                if (tag.name == "")
                    data.tags.remove(iter);
                return;
            }
            bool exists_already = false;
            data.tags.foreach((model, _path, iter2) => {
                if (model.get_string_from_iter(iter) == model.get_string_from_iter(iter2))
                    return false;
                Tag tag2;
                model.get(iter2, 0, out tag2);
                if (tag2.name == new_text) {
                    exists_already = true;
                    return true;
                }
                return false;
            });
            if (exists_already) {
                view.set_cursor(data.tags.get_path(iter), view.get_column(1), true);
                return;
            }
            data.starred.foreach(s => s.rename_tag(tag.name, new_text));
            tag.name = new_text;
            data.tags.row_changed(new Gtk.TreePath.from_string(path), iter);
        });

        tagname_renderer.editing_canceled.connect(() => {
            Gtk.TreePath path;
            view.get_cursor(out path, null);
            Gtk.TreeIter iter;
            if (!data.tags.get_iter(out iter, path))
                return;
            Tag tag;
            data.tags.get(iter, 0, out tag);
            if (tag.name == "")
                data.tags.remove(iter);
        });

        var add_button = new Gtk.Button.with_label("Add Tag");
        add_button.hexpand = true;
        add_button.clicked.connect(() => {
            Gtk.TreeIter iter;
            data.tags.insert_with_values(out iter, -1, 0, new Tag(""));
            view.set_cursor(data.tags.get_path(iter), view.get_column(1), true);
        });
        attach(add_button, 0, 1, 1, 1);

        remove_button = new Gtk.Button.with_label("Remove Tag");
        remove_button.hexpand = true;
        remove_button.clicked.connect(() => {
            Gtk.TreeIter iter;
            if (!view.get_selection().get_selected(null, out iter))
                return;
            Tag tag;
            data.tags.get(iter, 0, out tag);
            int count = 0;
            data.starred.foreach(s => {
                if (s.tags.contains(tag.name))
                    count++;
            });
            bool ok = true;
            if (count > 0) {
                var times = count == 1 ? "once" : @"$count times";
                var msg = new Gtk.MessageDialog(null, Gtk.DialogFlags.MODAL, Gtk.MessageType.INFO, Gtk.ButtonsType.CANCEL, "Tag '%s', which is used %s, is about to be deleted.", tag.name, times);
                msg.add_button("_Delete Tag", Gtk.ResponseType.OK);
                msg.response.connect((response_id) => {
                    ok = response_id == Gtk.ResponseType.OK;
                    msg.destroy();
                });
                msg.run();
            }
            if (!ok)
                return;
            data.starred.foreach(s => s.unset_tag(tag.name));
            data.tags.remove(iter);
        });
        attach(remove_button, 0, 2, 1, 1);

        var right = new Gtk.Grid();
        attach(right, 1, 0, 1, 3);

        bold_button = new Gtk.CheckButton.with_label("Mark as bold");
        right.attach(bold_button, 0, 0, 1, 1);

        use_color_button = new Gtk.CheckButton.with_label("Use color");
        right.attach(use_color_button, 0, 1, 1, 1);

        var color = new Gtk.Grid();
        right.attach(color, 0, 2, 1, 1);

        var color_label = new Gtk.Label("Star color:");
        color.attach(color_label, 0, 0, 1, 1);
        color_button = new Gtk.ColorButton();
        color_button.set_size_request(100,-1);
        color.attach(color_button, 1, 0, 1, 1);

        view.get_selection().changed.connect(update_tag_view);
        update_tag_view();

        bold_button.toggled.connect(update_tag);
        use_color_button.toggled.connect(update_tag);
        color_button.color_set.connect(update_tag);
    }

    void update_tag_view() {
        Gtk.TreeIter iter;
        Gtk.TreeModel model;
        if (!view.get_selection().get_selected(out model, out iter)) {
            bold_button.sensitive = false;
            use_color_button.sensitive = false;
            color_button.sensitive = false;
            remove_button.sensitive = false;
            return;
        }
        Tag tag;
        model.get(iter, 0, out tag);
        updating_view = true;
        bold_button.active = tag.bold;
        use_color_button.active = tag.color != null;
        if (tag.color != null)
            color_button.rgba = tag.color;
        else
            color_button.rgba = Gdk.RGBA();

        bold_button.sensitive = true;
        use_color_button.sensitive = true;
        color_button.sensitive = tag.color != null;
        remove_button.sensitive = true;
        updating_view = false;
    }

    void update_tag() {
        if (updating_view)
            return;
        Gtk.TreeIter iter;
        Gtk.TreeModel model;
        if (!view.get_selection().get_selected(out model, out iter))
            return;
        Tag tag;
        model.get(iter, 0, out tag);

        if (tag.bold != bold_button.active)
            tag.bold = bold_button.active;
        if (use_color_button.active) {
            if (tag.color == null || !tag.color.equal(color_button.rgba)) {
                Gdk.RGBA color = color_button.rgba;
                tag.color = color;
            }
        } else {
            tag.color = null;
        }
        color_button.sensitive = tag.color != null;
        data.tags.row_changed(model.get_path(iter), iter);
    }
}

class AppWindow : Gtk.ApplicationWindow {
    Gtk.TreeView preprint_view;
    TreeModelFilterSort preprint_model;
    Gtk.Entry search_entry;
    Gtk.Button import_button;
    Gtk.Grid tag_grid;
    bool tags_changed;

    public Gee.ArrayList<Status> selected { get; set; }
    public Preprint? entry { get; set; }

    public string clipboard_id { get; set; }
    int clipboard_version;

    Data data;

    internal AppWindow(App app) {
        Object (application: app, title: prog_name);

        set_default_size(800,600);

        data = new Data();

        selected = new Gee.ArrayList<Status>();
//        arxiv.update_entries();

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

        tag_grid = new Gtk.Grid();
        tag_grid.halign = Gtk.Align.END;
        tag_grid.hexpand = true;
        hgrid.attach(tag_grid, hi++, 0, 1, 1);

        vgrid.attach(hgrid,0,0,1,1);

        var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);
        paned.set_position(350);

        setup_preprints();

        preprint_view.expand = true;
        preprint_view.set_size_request(750, -1);
        preprint_view.get_selection().changed.connect(on_selection_changed);
        preprint_view.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE);
        preprint_view.row_activated.connect(on_row_activated);

        var scroll1 = new Gtk.ScrolledWindow(null, null);
        scroll1.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scroll1.add(preprint_view);
        paned.pack1(scroll1, true, true);

        var field_grid = new Gtk.Grid();
        add_field(field_grid, "Author(s)", e => string.joinv(", ", e.authors));
        add_field(field_grid, "Title", e => e.title);
        add_field(field_grid, "Abstract", e => e.summary);
        add_field(field_grid, "Comment", e => e.comment);
        add_field(field_grid, "ArXiv ID", e => "<a href=\"%s\">%sv%d</a>".printf(e.arxiv, e.id, e.version), true);

        var scroll2 = new Gtk.ScrolledWindow(null, null);
        scroll2.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scroll2.add_with_viewport(field_grid);
        paned.pack2(scroll2, true, true);
        scroll2.set_size_request(-1,200);

        vgrid.attach(paned,0,1,1,1);

        var notebook = new Gtk.Notebook();
        notebook.tab_pos = Gtk.PositionType.LEFT;
        var lib_label = new Gtk.Label("Library");
        lib_label.angle = 90;
        notebook.append_page(vgrid, lib_label);

        var tags_label = new Gtk.Label("Tags");
        tags_label.angle = 90;
        notebook.append_page(new TagsPage(data), tags_label);

        add(notebook);

        destroy.connect(() => { Timeout.trigger_all(); });

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
            entry = selected.size != 1 ? null : data.arxiv.preprints.get(selected[0].id);
            delete_button.sensitive = selected.size > 0;
            int i = 0;
            data.tags.foreach((model, _path, iter) => {
                Tag tag;
                model.get(iter, 0, out tag);
                var tag_button = tag_grid.get_child_at(i++, 0) as Gtk.ToggleButton;
                bool? active = null;
                foreach (var s in selected) {
                    if (active == null) {
                        active = s.tags.contains(tag.name);
                    } else if (active != s.tags.contains(tag.name)) {
                        tag_button.active = false;
                        tag_button.sensitive = false;
                        return false;
                    }
                }
                tag_button.active = active != null && active;
                tag_button.sensitive = active != null;
                return false;
            });
        });

        data.starred.row_inserted.connect((path, iter) => {
            Gtk.TreeIter preprint_iter;
            if (!preprint_model.convert_child_iter_to_iter(out preprint_iter, iter))
                return;
            preprint_view.get_selection().select_iter(preprint_iter);
            preprint_view.set_cursor(preprint_model.get_path(preprint_iter), null, false);
        });

        search_entry.grab_focus();

        notebook.switch_page.connect((_page, page_num) => {
            if (page_num == 0 && tags_changed)
                update_tags();
        });
        tags_changed = true;
        update_tags();

        data.tags.row_inserted.connect((_path, _iter) => { tags_changed = true; });
        data.tags.row_changed.connect((_path, _iter) => { tags_changed = true; });
        data.tags.row_deleted.connect((_path) => { tags_changed = true; });
        data.tags.rows_reordered.connect((_path, _iter, _new_order) => { tags_changed = true; });
    }

    void update_tags() {
        tag_grid.foreach(widget => widget.destroy());
        int hi = 0;
        data.tags.foreach((model, _path, iter) => {
            Tag tag;
            model.get(iter, 0, out tag);
            var tag_button = new Gtk.ToggleButton.with_label(tag.name); // TODO: mnemonic
            tag_button.sensitive = false;
            tag_button.toggled.connect(() => {
                foreach (var s in selected) {
                    if (s.tags.contains(tag.name) == tag_button.active)
                        continue;
                    if (tag_button.active)
                        s.set_tag(tag.name);
                    else
                        s.unset_tag(tag.name);
                }
            });
            tag_grid.attach(tag_button, hi++, 0, 1, 1);
            return false;
        });
        tag_grid.show_all();
        tags_changed = false;
    }

    void import_clipboard() {
        if (clipboard_id == null)
            return;
        preprint_view.get_selection().unselect_all();
        data.import(data.status_db.create(clipboard_id, clipboard_version));
    }

    delegate string PreprintField(Preprint e);

    void add_field(Gtk.Grid grid, string name, PreprintField f, bool markup = false) {
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
        var status_column_id = data.starred.add_object_column<Status>(s => s);
        assert(status_column_id == 0);
        var authors_column_id = data.starred.add_string_column(s => {
            string[] authors = {};
            foreach (var author in data.arxiv.preprints.get(s.id).authors) {
                var names = author.split(" ");
                authors += names[names.length-1];
            }
            return string.joinv(", ", authors);
        });
        var title_column_id = data.starred.add_string_column(s => data.arxiv.preprints.get(s.id).title);
        var weight_column_id = data.starred.add_int_column(s => {
            int weight = 400;
            data.tags.foreach((model, _path, iter) => {
                Tag tag;
                model.get(iter, 0, out tag);
                if (!s.tags.contains(tag.name))
                    return false;
                if (tag.bold)
                    weight = 700;
                return true;
            });
            return weight;
        });
        var starred_column_id = data.starred.add_boolean_column(s => { return true; });
        var color_column_id = data.starred.add_object_column<RGB?>(s => {
            RGB? color = null;
            data.tags.foreach((model, _path, iter) => {
                Tag tag;
                model.get(iter, 0, out tag);
                if (tag.color == null || !s.tags.contains(tag.name))
                    return false;
                color = new RGB();
                color.red = tag.color.red;
                color.green = tag.color.green;
                color.blue = tag.color.blue;
                return true;
            });
            return color;
        });

        preprint_model = new TreeModelFilterSort(data.starred);
        preprint_model.set_visible_func(do_filter);
        preprint_model.set_default_sort_func((model, iter1, iter2) => {
                int i1 = model.get_path(iter1).get_indices()[0];
                int i2 = model.get_path(iter2).get_indices()[0];
                return i2 - i1;
        });

        preprint_view.set_model(preprint_model);

        int n;
        var star_renderer = new CellRendererStar(20,20);
        n = preprint_view.insert_column_with_attributes(-1, "★", star_renderer, "starred", starred_column_id);
        var star_column = preprint_view.get_column(n-1);
        star_column.add_attribute(star_renderer, "color", color_column_id);

        var authors_renderer = new Gtk.CellRendererText();
        authors_renderer.ellipsize = Pango.EllipsizeMode.END;
        n = preprint_view.insert_column_with_attributes(-1, "Author(s)", authors_renderer, "text", authors_column_id);
        var authors_column = preprint_view.get_column(n-1);
        authors_column.set_sizing(Gtk.TreeViewColumnSizing.FIXED);
        authors_column.set_fixed_width(200);
        authors_column.resizable = true;
        authors_column.set_sort_column_id(authors_column_id);

        var title_renderer = new Gtk.CellRendererText();
        title_renderer.ellipsize = Pango.EllipsizeMode.END;
        n = preprint_view.insert_column_with_attributes(-1, "Title", title_renderer, "text", title_column_id);
        var title_column = preprint_view.get_column(n-1);
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
        var pdf = data.arxiv.preprints.get(s.id).get_filename();
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
            data.starred.remove(s);
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
        Preprint e = data.arxiv.preprints.get(s.id);
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
        Arxiv.old_format = new Regex("("+string.joinv("|", Arxiv.subjects)+")/([[:digit:]]{7})(v[[:digit:]]+)?");
        Arxiv.new_format = new Regex("([[:digit:]]{4}\\.[[:digit:]]{4})(v[[:digit:]]+)?");
        Preprint.url_id = new Regex("^http://arxiv.org/abs/(.*)$");
    } catch (GLib.RegexError e) {
        stderr.printf("Regex Error: %s\n", e.message);
    }

    return new App().run(args);
}
