/* vim: set cin et sw=4 : */

public class Status : Object {
    public string id { get; private set; }
    public int version;
    public Gee.TreeSet<string> tags { get; private set; }
    public bool deleted { get; set; }

    private Database db;

    public class Database {
        internal Gee.HashMap<string, weak Status> db;

        public Database() {
            db = new Gee.HashMap<string, weak Status>();
        }

        public Status create(string id, int version) {
            if (db.has_key(id))
                return db.get(id);
            Status s = new Status(this, id, version);
            db.set(id, s);
            return s;
        }
    }

    Status(Database db, string id, int version) {
        this.db = db;
        this.id = id;
        this.version = version;
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

public class Data {
    public Arxiv arxiv;
    public Status.Database status_db;

    Timeout starred_timeout;
    public ListModel<Status> starred;
    Timeout tags_timeout;
    public Gtk.ListStore tags;

    public Data() {
        arxiv = new Arxiv();
        status_db = new Status.Database();

        starred_timeout = new Timeout(5, save_starred);
        starred = new ListModel<Status>((s1, s2) => s1.id == s2.id);

        load_starred();
        starred.row_inserted.connect((path, iter) => { starred_timeout.reset(); });
        starred.row_deleted.connect(path => { starred_timeout.reset(); });
        starred.row_changed.connect((path, iter) => { starred_timeout.reset(); });

        tags_timeout = new Timeout(5, save_tags);
        tags = new Gtk.ListStore(1, typeof(Tag));

        load_tags();
        tags.row_inserted.connect((path, iter) => { tags_timeout.reset(); });
        tags.row_deleted.connect(path => { tags_timeout.reset(); });
        tags.row_changed.connect((path, iter) => { tags_timeout.reset(); });

        download_preprints();
    }

    void load_starred() {
        var file = File.new_for_path(get_starred_filename());
        if (!file.query_exists())
            return;

        try {
            var dis = new DataInputStream(file.read());
            string line;
            while ((line = dis.read_line(null)) != null) {
                string[] words = line.split(" ");
                string id;
                var idvs = Arxiv.parse_ids(words[0], out id);
                if (idvs.size == 0) {
                    stderr.printf("Warning: couldn't parse arXiv id %s.\n", words[0]);
                    continue;
                }
                var status = status_db.create(id, idvs.get(id));
                foreach (var str in words[1:words.length])
                    status.tags.add(str);
                starred.add(status);
            }
        } catch (Error e) {
            stderr.printf("Error reading config file: %s\n", e.message);
        }
    }

    void save_starred() {
        var contents = new StringBuilder();
        starred.foreach(s => {
            contents.append(s.id);
            if (s.version > 0)
                contents.append_printf("v%d", s.version);
            foreach (var tag in s.tags)
                contents.append(" " + tag);
            contents.append_c('\n');
        });
        try {
            FileUtils.set_contents(get_starred_filename(), contents.str);
        } catch (Error e) {
            stderr.printf("Error saving config file: %s\n", e.message);
        }
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

    void download_preprints() {
        var ids = new Gee.ArrayList<string>();
        starred.foreach(s => {
            if (!arxiv.preprints.has_key(s.id))
                ids.add(s.id);
        });
        if (ids.is_empty)
            return;
        arxiv.query_ids(ids);

        foreach (var id in ids)
            arxiv.preprints.get(id).download();
    }

    public bool import(Gee.Map<string, int> ids) {
        arxiv.query_ids(ids.keys);
        foreach (var idv in ids.entries) {
            var preprint = arxiv.preprints.get(idv.key);
            if (preprint != null)
                preprint.download();
            starred.add(status_db.create(idv.key, idv.value));
        }
        return true;
    }

    static string get_starred_filename() {
        return Path.build_filename(Environment.get_user_config_dir(), prog_name, "starred");
    }

    static string get_tags_filename() {
        return Path.build_filename(Environment.get_user_config_dir(), prog_name, "tags");
    }
}
