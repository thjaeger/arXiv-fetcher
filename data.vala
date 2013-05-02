/* vim: set cin et sw=4 : */

public class Status : Object {
    public string id { get; private set; }
    public int version { get; set; }
    public Gee.TreeSet<string> tags { get; private set; }
    public bool deleted { get; set; }

    private Database db;

    public class Database {
        internal Gee.HashMap<string, weak Status> db;

        public Database() {
            db = new Gee.HashMap<string, weak Status>();
        }

        public Status create(string id, int version, bool deleted) {
            if (db.has_key(id))
                return db.get(id);
            Status s = new Status(this, id, version, deleted);
            db.set(id, s);
            return s;
        }
    }

    Status(Database db, string id, int version, bool deleted) {
        this.db = db;
        this.id = id;
        this.version = version;
        this.deleted = deleted;
        tags = new Gee.TreeSet<string>();
        deleted = false;
    }

    ~Status() {
        db.db.unset(id);
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

    public void rename_tag(string src, string dst) {
        if (!tags.contains(src))
            return;
        tags.remove(src);
        tags.add(dst);
        tags = tags;
    }
}

public class RGB : Object {
    public double red;
    public double green;
    public double blue;

    public RGB.with_rgb(double red, double green, double blue) {
        this.red = red;
        this.green = green;
        this.blue = blue;
    }
}

public class Tag : Object {
    public string name { get; set; }
    public bool bold { get; set; }
    public Gdk.RGBA? color { get; set; }

    public Tag(string name, bool bold = false, Gdk.RGBA? color = null) {
        this.name = name;
        this.bold = bold;
        this.color = color;
    }

    public static const string variant_type = "(sbm(dddd))";

    public Variant to_variant() {
        Variant mcolor;
        if (color == null) {
            mcolor = new Variant.maybe(new VariantType("(dddd)"), null);
        } else {
            mcolor = new Variant.maybe(new VariantType("(dddd)"), color);
        }
        return new Variant.tuple(new Variant[] { name, bold, mcolor });
    }

    public Tag.from_variant(Variant v) {
        name = (string)v.get_child_value(0);
        bold = (bool)v.get_child_value(1);
        var mcolor = v.get_child_value(2).get_maybe();
        if (mcolor == null)
            color = null;
        else
            color = (Gdk.RGBA)mcolor;
    }
}

public class StatusList : ListModel<Status> {
    public enum Column {
        STATUS,
        AUTHORS,
        TITLE,
        WEIGHT,
        STARRED,
        COLOR
    }

    public StatusList(Data data) {
        EqualFunc<Status> cmp = (s1, s2) => s1.id == s2.id;
        base(cmp);

        var status_column_id = add_object_column<Status>(s => s);
        assert(status_column_id == Column.STATUS);
        var authors_column_id = add_string_column(s => {
            string[] authors = {};
            foreach (var author in data.arxiv.get(s.id).authors) {
                var names = author.split(" ");
                authors += names[names.length-1];
            }
            return string.joinv(", ", authors);
        });
        assert(authors_column_id == Column.AUTHORS);
        var title_column_id = add_string_column(s => data.arxiv.get(s.id).title);
        assert(title_column_id == Column.TITLE);
        var weight_column_id = add_int_column(s => {
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
        assert(weight_column_id == Column.WEIGHT);
        var starred_column_id = add_boolean_column(s => { return !s.deleted; });
        assert(starred_column_id == Column.STARRED);
        var color_column_id = add_object_column<RGB?>(s => {
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
        assert(color_column_id == Column.COLOR);
    }

    public void load(Status.Database status_db, bool deleted, string filename, string description) {
        Util.load_lines(filename, description, line => {
            string[] words = line.split(" ");
            string id;
            var idvs = Arxiv.parse_ids(words[0], out id);
            if (idvs.size == 0) {
                stderr.printf("Warning: couldn't parse arXiv id %s.\n", words[0]);
                return;
            }
            var status = status_db.create(id, idvs.get(id), deleted);
            foreach (var str in words[1:words.length])
                status.tags.add(str);
            add(status);
        });
    }

    public void save(string filename, string description) {
        var contents = new StringBuilder();
        @foreach(s => {
            contents.append(s.id);
            if (s.version > 0)
                contents.append_printf("v%d", s.version);
            foreach (var tag in s.tags)
                contents.append(" " + tag);
            contents.append_c('\n');
        });
        Util.save_contents(filename, description, contents.str);
    }

}

public class Data {
    public Arxiv arxiv;
    public Status.Database status_db;

    Timeout starred_timeout;
    public StatusList starred;

    Timeout tags_timeout;
    public Gtk.ListStore tags;

    public Timeout searches_timeout;
    public Gee.ArrayList<string> searches;

    Timeout watched_timeout;
    public StatusList watched;

    public Data() {
        arxiv = new Arxiv();
        status_db = new Status.Database();

        starred_timeout = new Timeout(5, () => starred.save(get_starred_filename(), "library"));
        starred = new StatusList(this);
        starred.load(status_db, false, get_starred_filename(), "library");

        starred.row_inserted.connect((path, iter) => { starred_timeout.reset(); });
        starred.row_deleted.connect(path => { starred_timeout.reset(); });
        starred.row_changed.connect((path, iter) => { starred_timeout.reset(); });

        tags_timeout = new Timeout(5, save_tags);
        tags = new Gtk.ListStore(1, typeof(Tag));

        load_tags();
        tags.row_inserted.connect((path, iter) => { tags_timeout.reset(); });
        tags.row_deleted.connect(path => { tags_timeout.reset(); });
        tags.row_changed.connect((path, iter) => { tags_timeout.reset(); });

        searches_timeout = new Timeout(5, save_searches);
        load_searches();

        watched_timeout = new Timeout(5, () => watched.save(get_watched_filename(), "results of watched searches"));
        watched = new StatusList(this);
        watched.load(status_db, true, get_watched_filename(), "results of watched searches");

        watched.row_inserted.connect((path, iter) => { watched_timeout.reset(); });
        watched.row_deleted.connect(path => { watched_timeout.reset(); });
        watched.row_changed.connect((path, iter) => { watched_timeout.reset(); });

        download_preprints();
    }

    void load_tags() {
        var tagnames = new Gee.TreeSet<string>();
        Util.load_variant(get_tags_filename(), "tags", "a"+Tag.variant_type, db => {
            for (int i = 0; i < db.n_children(); i++) {
                Tag tag = new Tag.from_variant(db.get_child_value(i));
                tags.insert_with_values(null, -1, 0, tag);
                tagnames.add(tag.name);
            }
        });
        starred.foreach(s => {
            foreach (var tagname in s.tags)
                if (!tagnames.contains(tagname)) {
                    tags.insert_with_values(null, -1, 0, new Tag(tagname));
                    tagnames.add(tagname);
                }
        });
    }

    void save_tags() {
        Variant[] va = {};
        tags.foreach((model, _path, iter) => {
            Tag tag;
            model.get(iter, 0, out tag);
            va += tag.to_variant();
            return false;
        });
        Variant db = new Variant.array(new VariantType(Tag.variant_type), va);
        Util.save_variant(get_tags_filename(), "tags", "a"+Tag.variant_type, db);
    }

    void load_searches() {
        searches = new Gee.ArrayList<string>();
        Util.load_lines(get_searches_filename(), "watched searches", s => searches.add(s));
    }

    void save_searches() {
        var contents = new StringBuilder();
        foreach (var s in searches)
            contents.append_printf("%s\n", s);
        Util.save_contents(get_searches_filename(), "watched searches", contents.str);
    }

    public void download_preprints(bool update = false) {
        var ids = new Gee.ArrayList<string>();
        starred.foreach(s => {
            if (update || !arxiv.preprints.has_key(s.id))
                ids.add(s.id);
        });
        if (ids.is_empty)
            return;
        arxiv.query_ids(ids);

        foreach (var id in ids)
            arxiv.get(id).download();
    }

    public bool import(Gee.Map<string, int> ids) {
        arxiv.query_ids(ids.keys);
        foreach (var idv in ids.entries) {
            arxiv.get(idv.key).download();
            starred.add(status_db.create(idv.key, idv.value, false));
        }
        return true;
    }

    static string get_starred_filename() {
        return Path.build_filename(Environment.get_user_config_dir(), prog_name, "starred");
    }

    static string get_tags_filename() {
        return Path.build_filename(Environment.get_user_config_dir(), prog_name, "tags");
    }

    static string get_searches_filename() {
        return Path.build_filename(Environment.get_user_config_dir(), prog_name, "searches");
    }

    static string get_watched_filename() {
        return Path.build_filename(Environment.get_user_cache_dir(), prog_name, "watched");
    }
}
