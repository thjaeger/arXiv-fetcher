/* vim: set cin et sw=4 : */

public class Status : Object {
    public string id { get; private set; }
    public int version;
    public Gee.TreeSet<string> tags { get; private set; }

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
}


public class Data {
    public Arxiv arxiv;
    public Status.Database status_db;

    Timeout starred_timeout;
    public ListModel<Status> starred;

    public Data() {
        arxiv = new Arxiv();
        status_db = new Status.Database();

        starred_timeout = new Timeout(5, save_starred);
        starred = new ListModel<Status>((s1, s2) => s1.id == s2.id);

        read_starred();
        starred.row_inserted.connect((path, iter) => { starred_timeout.reset(); });
        starred.row_deleted.connect(path => { starred_timeout.reset(); });
        starred.row_changed.connect((path, iter) => { starred_timeout.reset(); });

        download_preprints();
    }

    void read_starred() {
        var file = File.new_for_path(get_starred_filename());
        if (!file.query_exists())
            return;

        try {
            var dis = new DataInputStream(file.read());
            string line;
            while ((line = dis.read_line(null)) != null) {
                int version;
                string[] words = line.split(" ");
                string id = Arxiv.get_id(words[0], out version);
                if (id == null) {
                    stderr.printf("Warning: couldn't parse arXiv id %s.\n", words[0]);
                    continue;
                }
                var status = status_db.create(id, version);
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

    public bool import(Status s) {
        var ids = new Gee.ArrayList<string>();
        ids.add(s.id);
        arxiv.query_ids(ids);
        arxiv.preprints.get(s.id).download();
        starred.add(s);
        return true;
    }

    static string get_starred_filename() {
        return Path.build_filename(Environment.get_user_config_dir(), prog_name, "starred");
    }

}
