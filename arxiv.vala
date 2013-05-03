/* vim: set cin et sw=4 : */

public class Preprint {
    public static const string variant_type = "(sissssassssas)";
    public static Regex url_id;

    public Preprint() {
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

    public Preprint.dummy(string id) {
        this();
        title = id;
        this.id = id;
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

    public Preprint.from_variant(Variant v) {
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

    public string get_filename(int version) {
        return Path.build_filename(
                Environment.get_user_cache_dir(),
                prog_name,
                "preprints",
                id.replace("/","_") + @"v$version.pdf"
            );

    }

    public bool download() {
        if (pdf == null || pdf == "")
            return false;
        var filename = get_filename(version);
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

    public Preprint.from_xml(Xml.Node* node) {
        this();
        for (Xml.Node* i = node->children; i != null; i = i->next) {
            if (i->name == "id") {
                MatchInfo info;
                if (!url_id.match(i->get_content(), 0, out info))
                    continue;
                var match = info.fetch(1);
                var idvs = Arxiv.parse_ids(match, out id);
                if (id != null)
                    version = idvs.get(id);
                else
                    stderr.printf("Error: Couldn't parse arxiv identifier '%s'.\n", match);
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
                    if (j->name == "name") {
                        var authors_ = authors;
                        authors_ += j->get_content();
                        authors = authors_;
                    }
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
                var categories_ = categories;
                categories_ += i->get_prop("term");
                categories = categories_;
            }
        }
    }
}


public class Arxiv {
    public static Regex old_format;
    public static Regex new_format;

    Soup.SessionAsync session;
    const string api = "http://export.arxiv.org/api/query";

    public Timeout preprints_timeout;
    public Gee.HashMap<string, Preprint> preprints;

    public Arxiv() {
        session = new Soup.SessionAsync();
        preprints_timeout = new Timeout(10, save_preprints);
        preprints = new Gee.HashMap<string, Preprint>();
        load_preprints();
    }

    public Preprint @get(string id) {
        Preprint? p = preprints.get(id);
        return p ?? new Preprint.dummy(id);
    }

    public static Gee.Map<string, int> parse_ids(string idv, out string first_id = null) {
        first_id = null;
        var idvs = new Gee.TreeMap<string, int>();
        MatchInfo info;

        try {
            if (old_format.match(idv, 0, out info))
                do {
                    var mv = info.fetch(3);
                    var version = (mv == null || mv == "") ? 0 : int.parse(mv[1:mv.length]);
                    var id = info.fetch(1).split(".")[0] + "/" + info.fetch(2);
                    idvs.set(id, version);
                    if (first_id == null)
                        first_id = id;
                } while (info.next());

            if (new_format.match(idv, 0, out info))
                do {
                    var mv = info.fetch(2);
                    var version = (mv == null || mv == "") ? 0 : int.parse(mv[1:mv.length]);
                    var id = info.fetch(1);
                    idvs.set(id, version);
                    if (first_id == null)
                        first_id = id;
                } while (info.next());
        } catch (RegexError e) {
            stderr.printf("Regex error: %s\n", e.message);
        }
        return idvs;
    }

    void save_preprints() {
        Variant[] va = {};
        foreach (var ke in preprints.entries)
            va += ke.value.get_variant();
        Variant db = new Variant.array(new VariantType(Preprint.variant_type), va);
        Util.save_variant(get_db_filename(), "database", "a"+Preprint.variant_type, db);
    }

    void load_preprints() {
        Util.load_variant(get_db_filename(), "database", "a"+Preprint.variant_type, db => {
            for (int i = 0; i < db.n_children(); i++) {
                Preprint entry = new Preprint.from_variant(db.get_child_value(i));
                preprints.set(entry.id, entry);
            }
        });
    }

    static string get_db_filename() {
        return Path.build_filename(Environment.get_user_cache_dir(), prog_name, "database");
    }

    Gee.Collection<string> query(string query_string) {
        var ids = new Gee.ArrayList<string>();

        var message = new Soup.Message("GET", api + "?" + query_string);
        var response_code = session.send_message(message);
        if (response_code != 200) {
            stdout.printf("Error %u executing arxiv query '%s'.\n", response_code, query_string);
            if (response_code != 400)
                return ids;
        }

        Xml.Doc* doc = Xml.Parser.parse_doc((string)message.response_body.data);
        if (doc == null)
            return ids;

        Xml.Node* feed = doc->get_root_element();
        if (feed->name == "feed")
            for (Xml.Node* i = feed->children; i != null; i = i->next)
                if (i->name == "entry") {
                    if (response_code == 400)
                        for (Xml.Node* j = i->children; j != null; j = j->next)
                            if (j->name == "summary") {
                                stdout.printf("  Summary: %s\n", j->get_content());
                                delete doc;
                                return ids;
                            }

                    Preprint entry = new Preprint.from_xml(i);
                    if (entry.id == null) {
                        stderr.printf("Error: Invalid response from arXiv.\n");
                        continue;
                    }
                    preprints.set(entry.id, entry);
                    ids.add(entry.id);
                }
        preprints_timeout.reset();
        delete doc;
        return ids;
    }

    public void query_ids(Gee.Collection<string> ids) {
        const int n = 100;

        string[] ids_array = {};
        foreach (var id in ids) {
            ids_array += id;
            if (ids_array.length == n) {
                query(@"max_results=$n&id_list=" + string.joinv(",", ids_array));
                ids_array = {};
                Thread.usleep(3000000);
            }
        }
        query(@"max_results=$n&id_list=" + string.joinv(",", ids_array));
    }

    public Gee.Collection<string> search(string search_string, bool most_recent = true) {
        var q = Soup.Form.encode("max_results", "100", "search_query", search_string);
        if (most_recent)
            q += "&sortBy=submittedDate&sortOrder=descending";
        return query(q);
    }

    public static const string[] subjects = {
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

    public static const string[] obsolete_subjects = {
        "acc-phys",
        "adap-org",
        "alg-geom",
        "ao-sci",
        "atom-ph",
        "bayes-an",
        "chao-dyn",
        "chem-ph",
        "cmp-lg",
        "comp-gas",
        "dg-ga",
        "funct-an",
        "mtrl-th",
        "patt-sol",
        "plasm-ph",
        "q-alg",
        "solv-int",
        "supr-con",
    };
}
