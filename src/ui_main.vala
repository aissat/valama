/*
 * src/ui_main.vala
 * Copyright (C) 2012, 2013, Valama development team
 *
 * Valama is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Valama is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

using GLib;
using Gtk;
using Gdl;
using Gee;

/**
 * Main window class. Setup {@link Gdl.Dock} and {@link Gdl.DockBar} stuff.
 */
public class MainWindow : Window {
    private Dock dock;
    private DockLayout layout;
    private MenuBar menubar;
    private Toolbar toolbar;

    private Dock srcdock;
    private DockLayout srclayout;
    private ArrayList<DockItem> srcitems;

    private AccelGroup accel_group;

    private  string _current_srcfocus;
    public string current_srcfocus {
        get {
            return _current_srcfocus;
        }
        private set {
#if DEBUG
            stdout.printf (_("Change current focus: %s\n"), value);
#endif
            this.current_srcid = get_sourceview_id (value);
            _current_srcfocus = value;
            srcfocus_changed();
        }
    }
    private int _current_srcid = -1;
    private int current_srcid {
        get {
            return _current_srcid;
        }
        private set {
            this.current_srcview = get_sourceview (this.srcitems[value]);
            _current_srcid = value;
        }
    }
    public SourceView current_srcview { get; private set; }
    public TextBuffer current_srcbuffer {
        get {
            return current_srcview.buffer;
        }
    }

    /**
     * Emit signal to indicate that source item focus has probably changed.
     */
    public signal void srcfocus_changed();


    public MainWindow() {
        this.destroy.connect (main_quit);
        this.title = _("Valama");
        this.hide_titlebar_when_maximized = true;
        this.set_default_size (1200, 600);
        this.maximize();

        accel_group = new AccelGroup();
        this.add_accel_group (accel_group);

        var vbox_main = new Box (Orientation.VERTICAL, 0);
        this.add (vbox_main);

        /* Menubar. */
        this.menubar = new MenuBar();
        vbox_main.pack_start (menubar, false, true);

        /* Toolbar. */
        this.toolbar = new Toolbar();
        vbox_main.pack_start (toolbar, false, true);
        var toolbar_scon = toolbar.get_style_context();
        toolbar_scon.add_class (STYLE_CLASS_PRIMARY_TOOLBAR);

        /* Gdl dock stuff. */
        this.dock = new Dock();

        this.layout = new DockLayout (this.dock);

        var dockbar = new DockBar (this.dock);
        dockbar.set_style (DockBarStyle.TEXT);

        var box = new Box (Orientation.HORIZONTAL, 5);
        vbox_main.pack_start (box, true, true, 0);
        box.pack_start (dockbar, false, false, 0);
        box.pack_end (dock, true, true, 0);

        this.srcitems = new ArrayList<DockItem>();
    }

    /**
     * Focus source view {@link Gdl.DockItem} in {@link Gdl.Dock} and select
     * recursively all {@link Gdl.DockNotebook} tabs.
     */
    public void focus_src (string filename) {
        foreach (var srcitem in srcitems) {
            if (srcitem.long_name == filename) {
                /* Hack arround gdl_dock_notebook with gtk_notebook. */
                var pa = srcitem.parent;
                // pa.grab_focus();
                /* If something strange happens (pa == null) break the loop. */
                while (!(pa is Dock) && (pa != null)) {
                    //stdout.printf("item: %s\n", pa.name);
                    if (pa is Switcher) {
                        var nbook = (Notebook) pa;
                        nbook.page = nbook.page_num (srcitem);
                    }
                    pa = pa.parent;
                    // pa.grab_focus();
                }
                return;
            }
        }
    }

    /**
     * Connect to this signal to interrupt hiding (closing) of
     * {@link Gdl.DockItem} with {@link Gtk.SourceView}.
     *
     * Return false to interrupt or return true proceed.
     */
    public signal bool buffer_close (SourceView view);

    /**
     * Hide (close) {@link Gdl.DockItem} with {@link Gtk.SourceView} by
     * filename.
     */
    public void close_srcitem (string filename) {
        foreach (var srcitem in srcitems)
            if (srcitem.long_name == filename) {
                srcitems.remove (srcitem);
                srcitem.hide_item();
            }
    }

    /**
     * Add new source view item to main {@link Gdl.Dock}.
     */
    public void add_srcitem (SourceView view, string filename = "") {
        if (filename == "")
            filename = _("New document");

        var src_view = new ScrolledWindow (null, null);
        src_view.add (view);
        /*
         * NOTE: Keep this in sync with get_sourceview method.
         */
        var item = new DockItem.with_stock ("SourceView " + srcitems.size.to_string(),
                                            filename,
                                            Stock.EDIT,
                                            DockItemBehavior.LOCKED);
        item.add (src_view);

        /* Set focus on tab change. */
        item.selected.connect (() => {
            this.current_srcfocus = filename;
        });
        /* Set focus on click. */
        view.grab_focus.connect (() => {
            this.current_srcfocus = filename;
        });

        /*
         * Set notebook tab properly if needed.
         */
        item.dock.connect (() => {
            set_notebook_tabs (item);
        });

        if (srcitems.size == 0) {
            this.srcdock = new Dock();
            this.srclayout = new DockLayout (this.srcdock);
            var box = new Box (Orientation.HORIZONTAL, 0);
            box.pack_end (this.srcdock);

            /* Don't make source view dockable. */
            var boxitem = new DockItem ("SourceView",  _("Source"),
                                        DockItemBehavior.NO_GRIP |
                                        DockItemBehavior.CANT_DOCK_CENTER);
            boxitem.add (box);
            this.dock.add_item (boxitem, DockPlacement.TOP);

            this.srcdock.add_item (item, DockPlacement.RIGHT);
            this.srcdock.master.switcher_style = SwitcherStyle.TABS;
        } else {
            /* Handle dock item closing. */
            item.hide.connect (() => {
                /* Suppress dialog by removing item first forom srcitems list.  */
                if (!(item in srcitems))
                    return;

                if (!buffer_close (get_sourceview (item))) {
                    /*
                     * This will work properly with gdl-3.0 >= 3.6
                     */
                    item.show_item();
                    set_notebook_tabs (item);
                    return;
                }
                srcitems.remove (item);
                if (srcitems.size == 1)
                    srcitems[0].show_item();
            });

            item.behavior = DockItemBehavior.CANT_ICONIFY;

            /*
             * Hide default source view if it is empty.
             * Dock new items to focused dock item.
             *
             * NOTE: Custom unsafed views are ignored (even if empty).
             */
            var id = get_sourceview_id (this.current_srcfocus);
            if (id != -1)
                this.srcitems[id].dock (item, DockPlacement.CENTER, 0);
            else {
                stderr.printf (_("Source view id out of range.\n"));
                stderr.printf (_("Please report a bug!\n"));
                return;
            }
            if (srcitems.size == 1) {
                var view_widget = get_sourceview (srcitems[0]);
                //TODO: Use dirty flag of buffer.
                if (view_widget.buffer.text == "")
                    srcitems[0].hide_item();
            }
        }
        srcitems.add (item);
        view.show();
        src_view.show();
        item.show_item();
    }

    /**
     * Set up {@link Gtk.Notebook} tab properties.
     */
    private void set_notebook_tabs (DockItem item) {
        var pa = item.parent;
        if (pa is Switcher) {
            var nbook = (Notebook) pa;
            nbook.set_tab_pos (PositionType.TOP);
            foreach (var child in nbook.get_children())
                nbook.set_tab_reorderable (child, true);
        }
    }

    /**
     * Get {@link Gtk.SourceView} from within {@link Gdl.DockItem}.
     *
     */
    /*
     * NOTE: Be careful. This have to be exactly the same objects as the
     *       objects at creation of new source views.
     */
    private SourceView get_sourceview (DockItem item) {
        var scroll_widget = (ScrolledWindow) item.child;
        return (SourceView) scroll_widget.get_children().nth_data (0);
    }

    /**
     * Get id of {@link Gtk.SourceView} by filename.
     *
     * If file wasn't found return -1.
     */
    private int get_sourceview_id (string filename) {
        for (int i = 0; i < srcitems.size; ++i)
            if (srcitems[i].long_name == filename)
                return i;
        return -1;
    }

    /**
     * Add new item to main {@link Gdl.Dock}.
     */
    public void add_item (string item_name, string item_long_name,
                          Widget widget,
                          string? stock = null,
                          DockItemBehavior behavior,
                          DockPlacement placement) {
        DockItem item;
        if (stock ==  null)
            item = new DockItem (item_name, item_long_name, behavior);
        else
            item = new DockItem.with_stock (item_name, item_long_name, stock, behavior);
        item.add (widget);
        this.dock.add_item (item, placement);
        item.show();
    }

    /**
     * Add menu to main {@link Gtk.MenuBar}.
     */
    public void add_menu (Gtk.MenuItem item) {
        this.menubar.add (item);
    }

    /**
     * Add new button to main {@link Gdl.DockBar}.
     */
    public void add_button (ToolItem item) {
        this.toolbar.add (item);
    }

    /**
     * Save current {@link Gdl.DockLayout} to file.
     */
    public bool save_layout (string filename) {
        bool ret = this.layout.save_to_file (filename);
        if (!ret)
            stderr.printf (_("Couldn't save layout to file: %s\n"), filename);
#if DEBUG
        else
            stdout.printf (_("Layout saved to file: %s\n"), filename);
#endif
        return ret;
    }

    /**
     * Load {@link Gdl.DockLayout} from filename.
     */
    public bool load_layout (string filename, string section = "__default__") {
        bool ret = this.layout.load_from_file (filename);
        if (!ret)
            stderr.printf (_("Couldn't load layout file: %s\n"), filename);
#if DEBUG
        else
            stdout.printf (_("Layout loaded from file: %s\n"), filename);
#endif
        return (ret && this.layout_reload (section));
    }

    /**
     * Reload current {@link Gdl.DockLayout}. May be helpful on window resize.
     */
    public bool layout_reload (string section = "__default__") {
        bool ret = this.layout.load_layout (section);
        if (!ret)
            stderr.printf (_("Couldn't load layout: %s\n"), section);
#if DEBUG
        else
            stdout.printf (_("Layout loaded: %s\n"), section);
#endif
        return ret;
    }

    /**
     * Add accelerator for 'activate' signal.
     */
    public void add_accel_activate (Widget item,
                                    string keyname,
                                    Gdk.ModifierType modtype = Gdk.ModifierType.CONTROL_MASK) {
        item.add_accelerator ("activate",
                              this.accel_group,
                              Gdk.keyval_from_name (keyname),
                              modtype,
                              AccelFlags.VISIBLE);
    }
}

// vim: set ai ts=4 sts=4 et sw=4