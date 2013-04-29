/* vim: set cin et sw=4 : */

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
