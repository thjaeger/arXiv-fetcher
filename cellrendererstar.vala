/* vim: set cin et sw=4 : */

class CellRendererStar : Gtk.CellRenderer {
    public bool starred { get; set; }

    public CellRendererStar(int width, int height) {
        GLib.Object(width: width, height: height);
    }

    public override void get_size(Gtk.Widget widget, Gdk.Rectangle? cell_area, out int x_offset, out int y_offset, out int width, out int height) {
        x_offset = 0;
        y_offset = 0;
        width = this.width;
        height = this.height;
    }

    public override void render(Cairo.Context ctx, Gtk.Widget widget, Gdk.Rectangle background_area, Gdk.Rectangle cell_area, Gtk.CellRendererState flags) {
        ctx.translate(cell_area.x+cell_area.width/2.0, cell_area.y+cell_area.height/2.0);
        ctx.scale(cell_area.width/3.5, cell_area.height/3.5);

        for (int i = 0; i < 5; i++) {
            ctx.line_to(Math.sin(i*0.4*Math.PI), -Math.cos(i*0.4*Math.PI));
            ctx.line_to(Math.sin((i*0.4+0.2)*Math.PI)/2.5, -Math.cos((i*0.4+0.2)*Math.PI)/2.5);
        }
        ctx.close_path();

        if (starred) {
            var path = ctx.copy_path();
            ctx.set_source_rgba(1.0,1.0,0.0,1.0);
            ctx.fill();
            ctx.append_path(path);
        }

        ctx.set_line_width(0.1);
        ctx.set_source_rgba(0.0,0.0,0.0,0.8);
        ctx.stroke();
    }
}
