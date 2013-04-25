/* vim: set cin et sw=4 : */

public interface Mergable<A> {
    public abstract void merge(A x);
}

public class ListModel<A> : Object, Gtk.TreeModel {
    Gee.ArrayList<A> data;
    Gee.ArrayList<ulong> signals;
    Gee.ArrayList<Column<A>> columns;
    int stamp;

    public delegate B View<A, B>(A x);
    public delegate void Func<A>(A x);

    class Column<A> {
        public delegate Value ValueView<A>(A x);
        public Column(Type type, owned ValueView<A> view) {
            this.type = type;
            this.view = (owned)view;
        }
        public Type type;
        public ValueView<A> view;
    }

    public ListModel(EqualFunc<A>? equal_func = null) {
        assert(typeof(A).is_a(typeof(Object)) && typeof(A).is_a(typeof(Mergable)));
        data = new Gee.ArrayList<A>(equal_func);
        signals = new Gee.ArrayList<ulong>();
        columns = new Gee.ArrayList<Column<A>>();
        stamp = 0;
    }

    public int add_object_column<B>(View<A, B> view) {
        columns.add(new Column<A>(typeof(B), (x) => {
            Value v = Value(typeof(B));
            v.set_object((Object)view(x));
            return v;
        }));
        return columns.size-1;
    }

    public int add_string_column(View<A, string> view) {
        columns.add(new Column<A>(typeof(string), (x) => {
            Value v = Value(typeof(string));
            v.set_string(view(x));
            return v;
        }));
        return columns.size-1;
    }

    public int add_int_column(View<A, int> view) {
        columns.add(new Column<A>(typeof(int), (x) => {
            Value v = Value(typeof(int));
            v.set_int(view(x));
            return v;
        }));
        return columns.size-1;
    }

    public bool add(A x) {
        int i = data.index_of(x);
        if (i >= 0) {
            return false;
        }
        data.add(x);
        i = data.size-1;
        var sig = ((Object)x).notify.connect((s,p) => {
            row_changed(get_path_from_index(i), get_iter_from_index(i));
        });
        signals.add(sig);
        stamp++;
        row_inserted(get_path_from_index(i), get_iter_from_index(i));
        return true;
    }

    public bool remove(A x) {
        int i = data.index_of(x);
        Gtk.TreePath path = get_path_from_index(i);
        SignalHandler.disconnect(data[i], signals[i]);
        data.remove_at(i);
        signals.remove_at(i);
        row_deleted(path);
        stamp++;
        return true;
    }

    public new void foreach(Func<A> f) {
        foreach (var x in data)
            f(x);
    }

    public new A @get(int i) {
        assert(0 <= i && i < data.size);
        return data[i];
    }

    public Type get_column_type (int index) {
        assert(0 <= index && index < columns.size);
        return columns[index].type;
    }

    public Gtk.TreeModelFlags get_flags () {
        return Gtk.TreeModelFlags.LIST_ONLY;
    }

    public void get_value(Gtk.TreeIter iter, int column, out Value val) {
        assert(0 <= column && column < columns.size);
        val = columns[column].view(data[get_index_from_iter(iter)]);
    }

    inline Gtk.TreeIter get_iter_from_index(int i) {
        assert(0 <= i && i < data.size);
        var iter = Gtk.TreeIter();
        iter.stamp = stamp;
        iter.user_data = i.to_pointer();
        return iter;
    }

    inline int get_index_from_iter(Gtk.TreeIter iter) {
        assert(iter.stamp == stamp);
        return (int)iter.user_data;
    }

    inline Gtk.TreePath get_path_from_index(int i) {
        assert(0 <= i && i < data.size);
        Gtk.TreePath path = new Gtk.TreePath();
        path.append_index(i);
        return path;
    }

    public bool get_iter(out Gtk.TreeIter iter, Gtk.TreePath path) {
        if (path.get_depth() != 1 || data.size == 0)
            return invalid_iter(out iter);

        iter = get_iter_from_index(path.get_indices()[0]);
        return true;
    }

    public int get_n_columns() {
        return columns.size;
    }

    public Gtk.TreePath? get_path(Gtk.TreeIter iter) {
        return get_path_from_index(get_index_from_iter(iter));
    }

    public int iter_n_children(Gtk.TreeIter? iter) {
        if (iter == null)
            return data.size;
        assert(iter.stamp == stamp);
        return 0;
    }

    public bool iter_next(ref Gtk.TreeIter iter) {
        int i = get_index_from_iter(iter) + 1;
        if (0 <= i && i < data.size)
            iter.user_data = i.to_pointer();
        else
            return false;
        return true;
    }

    public bool iter_previous (ref Gtk.TreeIter iter) {
        int i = get_index_from_iter(iter) - 1;
        if (0 <= i && i < data.size)
            iter.user_data = i.to_pointer();
        else
            return false;
        return true;
    }

    public bool iter_nth_child (out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n) {
        assert(parent == null && 0 <= n && n < data.size);
        iter = get_iter_from_index(n);
        return true;
    }

    public bool iter_children (out Gtk.TreeIter iter, Gtk.TreeIter? parent) {
        return invalid_iter(out iter);
    }

    public bool iter_has_child (Gtk.TreeIter iter) {
        return false;
    }

    public bool iter_parent(out Gtk.TreeIter iter, Gtk.TreeIter child) {
        assert(false);
        iter = Gtk.TreeIter();
        return false;
    }

    bool invalid_iter(out Gtk.TreeIter iter) {
        iter = Gtk.TreeIter();
        iter.stamp = -1;
        return false;
    }
}
