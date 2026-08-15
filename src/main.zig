const r4os = @import("r4os");
const AppApi = struct {
    sys: r4os.r4sys.Context,
    desk: r4os.r4desk.Context,
    draw: r4os.r4draw.Context,
    net: r4os.r4net.Context,
    dev: r4os.r4dev.Context,

    fn init(r4_app: *r4os.App) ?AppApi {
        return .{
            .sys = r4_app.system(),
            .desk = r4_app.desktop() orelse return null,
            .draw = r4_app.drawing() orelse return null,
            .net = r4_app.networkLowLevel() orelse return null,
            .dev = r4_app.devicesLowLevel() orelse return null,
        };
    }
};

const editor_capacity: usize = 32 * 1024;
const path_capacity: usize = 192;
const status_capacity: usize = 96;
const dir_buffer_capacity: usize = 4096;
const max_dir_items: usize = 96;
const dir_item_capacity: usize = 96;
const max_fonts: usize = 65; // 64 installed R4F faces plus builtin
const font_name_capacity: usize = 40;
const font_size_label_capacity: usize = 12;
const font_path_capacity: usize = 96;
const find_capacity: usize = 96;
const scratch_capacity: usize = 512;
const status_h: i32 = 20;

const modifier_shift: u32 = 2;
const ctrl_n: u8 = 0x0E;
const ctrl_o: u8 = 0x0F;
const ctrl_s: u8 = 0x13;
const ctrl_f: u8 = 0x06;

const Editor = r4os.gui.TextArea(editor_capacity);

const Command = enum(u32) {
    file_new = 101,
    file_open = 102,
    file_save = 103,
    file_save_as = 104,
    file_exit = 105,
    edit_copy = 201,
    edit_paste = 202,
    settings_change_font = 301,
    settings_toggle_word_wrap = 302,
    search_find = 401,
};

const AppMenus = struct {
    file_items: [5]r4os.gui.MenuItem = undefined,
    settings_items: [2]r4os.gui.MenuItem = undefined,
    edit_items: [2]r4os.gui.MenuItem = undefined,
    search_items: [1]r4os.gui.MenuItem = undefined,
    menus: [4]r4os.gui.MenubarMenu = undefined,
};

const DialogMode = enum {
    none,
    open,
    save_as,
    save_prompt,
    change_font,
    find,
};

const PendingAction = enum {
    none,
    new_file,
    open_dialog,
    exit_app,
};

const FontDialogFocus = enum {
    family,
    style,
    size,
};

const App = struct {
    ctx: *AppApi,
    editor: Editor = .{},
    menubar_state: r4os.gui.MenubarState = .{},
    menu_storage: AppMenus = .{},
    dialog: DialogMode = .none,
    pending_action: PendingAction = .none,
    quit_requested: bool = false,
    dirty: bool = false,
    loaded_truncated: bool = false,
    pending_recent_document: bool = false,
    text_selecting: bool = false,
    word_wrap: bool = true,
    hosted_w: i32 = 520,
    hosted_h: i32 = 340,
    dialog_selected_index: usize = 0,
    dialog_first_index: usize = 0,
    dialog_hover_index: ?usize = null,
    dialog_pressed_action: r4os.gui.DialogAction = .none,
    font_dialog_focus: FontDialogFocus = .family,
    font_family_selected: usize = 0,
    font_family_first: usize = 0,
    font_style_selected: usize = 0,
    font_style_first: usize = 0,
    font_size_selected: usize = 0,
    font_size_first: usize = 0,
    editor_font_id: u32 = r4os.abi.gui_font_builtin_id,
    editor_font_path: [font_path_capacity]u8 = .{0} ** font_path_capacity,
    current_dir: [path_capacity]u8 = .{0} ** path_capacity,
    current_path: [path_capacity]u8 = .{0} ** path_capacity,
    selected_path: [path_capacity]u8 = .{0} ** path_capacity,
    save_file_name: [path_capacity]u8 = .{0} ** path_capacity,
    find_text: [find_capacity]u8 = .{0} ** find_capacity,
    hosted_status: [status_capacity]u8 = .{0} ** status_capacity,
    dirbuf: [dir_buffer_capacity]u8 = .{0} ** dir_buffer_capacity,
    dir_items: [max_dir_items][dir_item_capacity]u8 = .{.{0} ** dir_item_capacity} ** max_dir_items,
    dir_item_slices: [max_dir_items][]const u8 = [_][]const u8{""} ** max_dir_items,
    dir_item_count: usize = 0,
    font_infos: [max_fonts]r4os.abi.GuiFontInfo = .{r4os.abi.GuiFontInfo{}} ** max_fonts,
    font_count: usize = 0,
    font_family_items: [max_fonts][font_name_capacity]u8 = .{.{0} ** font_name_capacity} ** max_fonts,
    font_family_slices: [max_fonts][]const u8 = [_][]const u8{""} ** max_fonts,
    font_family_count: usize = 0,
    font_style_items: [max_fonts][font_name_capacity]u8 = .{.{0} ** font_name_capacity} ** max_fonts,
    font_style_slices: [max_fonts][]const u8 = [_][]const u8{""} ** max_fonts,
    font_style_count: usize = 0,
    font_size_items: [max_fonts][font_size_label_capacity]u8 = .{.{0} ** font_size_label_capacity} ** max_fonts,
    font_size_slices: [max_fonts][]const u8 = [_][]const u8{""} ** max_fonts,
    font_size_ids: [max_fonts]u32 = .{0} ** max_fonts,
    font_size_values: [max_fonts]u32 = .{0} ** max_fonts,
    font_size_count: usize = 0,

    fn init(self: *App) void {
        setZ(self.current_dir[0..], "C:\\");
        setZ(self.hosted_status[0..], "Ready");
        self.editor.focused = true;
        self.loadFonts();
        self.openInitialArg();
    }

    fn run(self: *App) i32 {
        if (self.ctx.desk.programWindowId() >= 0) return self.runHosted();
        return self.runFullscreenFallback();
    }

    fn runHosted(self: *App) i32 {
        _ = self.ctx.desk.guiSetTitle("Notepad");
        _ = self.ctx.desk.guiSetMinSize(440, 280);
        self.updateHostedMetrics();
        self.renderHosted();

        while (!self.quit_requested) {
            if (self.ctx.sys.programShouldClose() and self.dialog == .none) {
                self.requestAction(.exit_app);
            }

            var event: r4os.abi.GuiEvent = .{};
            while (self.ctx.desk.guiPollEvent(&event) > 0) {
                self.handleHostedEvent(event);
                if (self.quit_requested) break;
            }
            if (self.quit_requested) break;
            if (self.pending_recent_document) {
                self.ctx.sys.sleepTicks(1);
                self.flushPendingRecentDocument();
                continue;
            }
            self.ctx.sys.sleepTicks(3);
        }
        return 0;
    }

    fn runFullscreenFallback(self: *App) i32 {
        self.ctx.desk.mouseShow();
        self.drawFullscreenFallback();
        if (self.pending_recent_document) {
            self.ctx.sys.taskYield();
            self.flushPendingRecentDocument();
        }
        while (!self.quit_requested and !self.ctx.sys.programShouldClose()) {
            const key = self.ctx.desk.readKey();
            if (key == 0) {
                self.ctx.sys.taskYield();
                continue;
            }
            if (key == r4os.gui.Key.escape) break;
            if (self.editor.handleKey(key, r4os.gui.TextAreaView.init(120, 40))) {
                self.dirty = true;
                self.drawFullscreenFallback();
            }
        }
        self.ctx.desk.mouseHide();
        return 0;
    }

    fn drawFullscreenFallback(self: *App) void {
        self.ctx.draw.clear(0xFFFFFF);
        self.ctx.draw.text(8, 8, "R4OS Notepad - hosted mode has menus, dialogs and selection", 0x000000, 0xFFFFFF);
        self.ctx.draw.text(8, 24, zptr(self.editor.buffer[0..]), 0x000000, 0xFFFFFF);
    }

    fn handleHostedEvent(self: *App, event: r4os.abi.GuiEvent) void {
        const kind: r4os.abi.GuiEventKind = @enumFromInt(event.kind);
        switch (kind) {
            .close => self.requestAction(.exit_app),
            .resize => {
                self.updateHostedMetrics();
                self.editor.ensureCursorVisible(self.editorView());
                self.renderHosted();
            },
            .key_down => self.handleHostedKey(r4os.gui.eventCodepoint(event), event.modifiers),
            .mouse_down => self.handleMouseDown(event.x, event.y),
            .mouse_up => self.handleMouseUp(event.x, event.y),
            .mouse_move => self.handleMouseMove(event.x, event.y, event.buttons),
            .font_changed => {
                self.loadFonts();
                self.editor.ensureCursorVisible(self.editorView());
                self.setStatus("System fonts updated");
                self.renderHosted();
            },
            else => {},
        }
    }

    fn updateHostedMetrics(self: *App) void {
        var info: r4os.abi.GuiWindowInfo = .{};
        _ = self.ctx.desk.guiWindowInfo(&info);
        const canvas = r4os.gui.Canvas.init(&self.ctx.draw, info);
        self.hosted_w = clampI32(canvas.w, 220, 1600);
        self.hosted_h = clampI32(canvas.h, 140, 1000);
    }

    fn handleHostedKey(self: *App, raw_key: u32, modifiers: u32) void {
        var key: u8 = if (raw_key <= 0xff) @intCast(raw_key) else 0;
        if (key == 0x85 or key == 0x86) key = r4os.gui.Key.menu_focus;

        if (self.dialog != .none) {
            self.handleDialogKey(key);
            self.renderHosted();
            return;
        }

        if (self.menubar_state.isOpen() or key == r4os.gui.Key.menu_focus or key == r4os.gui.Key.f10) {
            var menu_storage: AppMenus = undefined;
            const menus = buildAppMenus(&menu_storage, self.word_wrap);
            const result = self.menubar_state.keyAction(menus, key);
            if (result.hasCommand()) self.executeCommand(result.command_id);
            self.renderHosted();
            return;
        }

        if (self.handleCommandShortcut(key)) {
            self.renderHosted();
            return;
        }

        const view = self.editorView();
        const changed = switch (key) {
            r4os.gui.Key.ctrl_c => blk: {
                if (self.editor.copyToClipboard(&self.ctx.desk)) {
                    self.setStatus("Copied selection");
                    break :blk true;
                }
                self.setStatus("No selection");
                break :blk false;
            },
            r4os.gui.Key.ctrl_x => blk: {
                if (self.editor.cutToClipboard(&self.ctx.desk)) {
                    self.dirty = true;
                    self.loaded_truncated = false;
                    self.setStatus("Cut selection");
                    break :blk true;
                }
                self.setStatus("No selection");
                break :blk false;
            },
            r4os.gui.Key.ctrl_v => blk: {
                if (self.editor.pasteFromClipboard(&self.ctx.desk, view)) {
                    self.dirty = true;
                    self.loaded_truncated = false;
                    self.setStatus("Pasted");
                    break :blk true;
                }
                self.setStatus("Clipboard empty or text full");
                break :blk false;
            },
            else => blk: {
                const did_change = self.editor.handleCodepointEx(raw_key, (modifiers & modifier_shift) != 0, view);
                if (did_change and isTextEditingCodepoint(raw_key)) {
                    self.dirty = true;
                    self.loaded_truncated = false;
                }
                break :blk did_change;
            },
        };
        if (changed) self.renderHosted();
    }

    fn handleCommandShortcut(self: *App, key: u8) bool {
        switch (key) {
            ctrl_n => self.requestAction(.new_file),
            ctrl_o => self.requestAction(.open_dialog),
            ctrl_s => self.saveCurrentOrOpenSaveAs(),
            ctrl_f => self.openFindDialog(),
            else => return false,
        }
        return true;
    }

    fn handleMouseDown(self: *App, x: i32, y: i32) void {
        if (self.dialog != .none) {
            self.handleDialogMouseDown(x, y);
            self.renderHosted();
            return;
        }

        const canvas = self.appCanvas();
        var menu_storage: AppMenus = undefined;
        const menus = buildAppMenus(&menu_storage, self.word_wrap);
        const menu_rect = self.menubarRect(canvas);
        const menu_was_open = self.menubar_state.isOpen();
        const menu_result = self.menubar_state.mouseDown(menu_rect, menus, x, y);
        if (menu_rect.contains(x, y) or (menu_was_open and menu_result.action != .none)) {
            self.renderHosted();
            return;
        }

        if (self.handleScrollbarMouseDown(canvas, x, y)) {
            self.renderHosted();
            return;
        }

        if (self.editorIndexAt(canvas, x, y)) |index| {
            const editor_canvas = self.editorCanvas(canvas);
            self.beginEditorSelectionAt(editor_canvas, index);
            self.renderHosted();
        }
    }

    fn handleMouseUp(self: *App, x: i32, y: i32) void {
        if (self.dialog != .none) {
            self.handleDialogMouseUp(x, y);
            self.renderHosted();
            return;
        }
        if (self.menubar_state.isOpen()) {
            var menu_storage: AppMenus = undefined;
            const menus = buildAppMenus(&menu_storage, self.word_wrap);
            const result = self.menubar_state.mouseUp(self.menubarRect(self.appCanvas()), menus, x, y);
            if (result.hasCommand()) self.executeCommand(result.command_id);
            self.renderHosted();
            return;
        }
        if (self.text_selecting) {
            self.text_selecting = false;
            self.editor.finishMouseSelection();
            self.renderHosted();
        } else if (self.editorIndexAt(self.appCanvas(), x, y)) |index| {
            const editor_canvas = self.editorCanvas(self.appCanvas());
            _ = self.editor.moveCursorTo(index, false, self.editorViewForCanvas(editor_canvas));
            self.editor.focused = true;
            self.renderHosted();
        }
    }

    fn handleMouseMove(self: *App, x: i32, y: i32, buttons: u32) void {
        if (self.dialog != .none) return;
        if (self.menubar_state.isOpen()) {
            var menu_storage: AppMenus = undefined;
            const menus = buildAppMenus(&menu_storage, self.word_wrap);
            _ = self.menubar_state.mouseMove(self.menubarRect(self.appCanvas()), menus, x, y);
            self.renderHosted();
            return;
        }
        if (self.text_selecting or (buttons & 1) != 0) {
            const canvas = self.appCanvas();
            const index = self.editorIndexAt(canvas, x, y) orelse return;
            const editor_canvas = self.editorCanvas(canvas);
            if (!self.text_selecting) self.beginEditorSelectionAt(editor_canvas, index);
            self.editor.dragMouseSelection(index, self.editorViewForCanvas(editor_canvas));
            self.renderHosted();
        }
    }

    fn beginEditorSelectionAt(self: *App, editor_canvas: r4os.gui.Canvas, index: usize) void {
        self.editor.focused = true;
        self.editor.beginMouseSelection(index, self.editorViewForCanvas(editor_canvas));
        self.text_selecting = true;
    }

    fn editorIndexAt(self: *App, canvas: r4os.gui.Canvas, x: i32, y: i32) ?usize {
        const editor_rect = self.editorTextRect(canvas);
        if (!editor_rect.contains(x, y)) return null;
        const editor_canvas = self.editorCanvas(canvas);
        const text_rect = r4os.gui.textAreaClientRect(editor_rect);
        return self.editor.hitTest(x - text_rect.x, y - text_rect.y, editor_canvas.font.max_advance, editor_canvas.font.line_height, self.editorViewForCanvas(editor_canvas));
    }

    fn handleScrollbarMouseDown(self: *App, canvas: r4os.gui.Canvas, x: i32, y: i32) bool {
        const editor_canvas = self.editorCanvas(canvas);
        const view = self.editorViewForCanvas(editor_canvas);
        const vertical = self.verticalScrollbar(editor_canvas);
        if (vertical.rect.contains(x, y)) {
            const step = vertical.step(vertical.partAt(x, y));
            if (step.action == .changed) self.editor.scrollTo(step.first_index, self.editor.scroll_col, view);
            return true;
        }
        const horizontal = self.horizontalScrollbar(editor_canvas);
        if (horizontal.rect.contains(x, y)) {
            const step = horizontal.step(horizontal.partAt(x, y));
            if (step.action == .changed) self.editor.scrollTo(self.editor.scroll_line, step.first_index, view);
            return true;
        }
        return false;
    }

    fn executeCommand(self: *App, command_id: u32) void {
        self.menubar_state.close();
        switch (command_id) {
            @intFromEnum(Command.file_new) => self.requestAction(.new_file),
            @intFromEnum(Command.file_open) => self.requestAction(.open_dialog),
            @intFromEnum(Command.file_save) => self.saveCurrentOrOpenSaveAs(),
            @intFromEnum(Command.file_save_as) => self.openFileDialog(.save_as),
            @intFromEnum(Command.file_exit) => self.requestAction(.exit_app),
            @intFromEnum(Command.edit_copy) => {
                if (self.editor.copyToClipboard(&self.ctx.desk)) {
                    self.setStatus("Copied selection");
                } else {
                    self.setStatus("No selection");
                }
            },
            @intFromEnum(Command.edit_paste) => {
                if (self.editor.pasteFromClipboard(&self.ctx.desk, self.editorView())) {
                    self.dirty = true;
                    self.loaded_truncated = false;
                    self.setStatus("Pasted");
                } else {
                    self.setStatus("Clipboard empty or text full");
                }
            },
            @intFromEnum(Command.settings_change_font) => self.openFontDialog(),
            @intFromEnum(Command.settings_toggle_word_wrap) => self.toggleWordWrap(),
            @intFromEnum(Command.search_find) => self.openFindDialog(),
            else => {},
        }
    }

    fn toggleWordWrap(self: *App) void {
        self.word_wrap = !self.word_wrap;
        if (self.word_wrap) self.editor.scroll_col = 0;
        self.editor.ensureCursorVisible(self.editorView());
        self.setStatus(if (self.word_wrap) "Word wrap enabled" else "Word wrap disabled");
    }

    fn requestAction(self: *App, action: PendingAction) void {
        if (self.dirty) {
            self.pending_action = action;
            self.dialog = .save_prompt;
            self.dialog_pressed_action = .none;
            self.setStatus("Unsaved changes");
            self.renderHosted();
            return;
        }
        self.performAction(action);
    }

    fn performAction(self: *App, action: PendingAction) void {
        switch (action) {
            .none => {},
            .new_file => self.newDocument(),
            .open_dialog => self.openFileDialog(.open),
            .exit_app => self.quit_requested = true,
        }
    }

    fn newDocument(self: *App) void {
        self.editor.clear();
        self.editor.focused = true;
        zero(self.current_path[0..]);
        self.dirty = false;
        self.loaded_truncated = false;
        self.pending_action = .none;
        self.pending_recent_document = false;
        self.dialog = .none;
        self.setStatus("New file");
    }

    fn saveCurrentOrOpenSaveAs(self: *App) void {
        if (self.current_path[0] == 0) {
            self.openFileDialog(.save_as);
            return;
        }
        if (self.loaded_truncated) {
            self.setStatus("Loaded text is truncated; use Save As");
            return;
        }
        _ = self.saveToCurrentPath();
    }

    fn saveToCurrentPath(self: *App) bool {
        if (self.loaded_truncated) {
            self.setStatus("Loaded text is truncated; use Save As");
            return false;
        }
        const written = self.ctx.sys.fileWrite(zptr(self.current_path[0..]), self.editor.value());
        if (written < 0 or @as(usize, @intCast(written)) != self.editor.value().len) {
            self.setStatus("Save failed");
            return false;
        }
        self.dirty = false;
        self.loaded_truncated = false;
        self.setStatus("Saved");
        self.noteRecentDocument();
        return true;
    }

    fn openFileDialog(self: *App, mode: DialogMode) void {
        if (mode == .save_as) {
            if (self.current_path[0] != 0) {
                setZ(self.save_file_name[0..], baseName(spanZ(self.current_path[0..])));
            } else if (self.save_file_name[0] == 0) {
                setZ(self.save_file_name[0..], "UNTITLED.TXT");
            }
        }

        if (!self.loadDirectory()) {
            self.dialog = .none;
            self.setStatus("Directory read failed");
            return;
        }
        self.dialog = mode;
        self.dialog_selected_index = 0;
        self.dialog_first_index = 0;
        self.dialog_hover_index = null;
        self.dialog_pressed_action = .none;
        self.setStatus(if (mode == .save_as) "Choose name and folder" else "Choose file to open");
    }

    fn loadDirectory(self: *App) bool {
        zero(self.dirbuf[0..]);
        self.dir_item_count = 0;
        const read = self.ctx.sys.dirList(zptr(self.current_dir[0..]), self.dirbuf[0 .. self.dirbuf.len - 1]);
        if (read < 0) return false;
        const len: usize = @intCast(read);
        if (len < self.dirbuf.len) self.dirbuf[len] = 0;
        self.parseDirectoryItems(self.dirbuf[0..@min(len, self.dirbuf.len - 1)]);
        return true;
    }

    fn parseDirectoryItems(self: *App, data: []const u8) void {
        var start: usize = 0;
        var i: usize = 0;
        while (i <= data.len) : (i += 1) {
            if (i == data.len or data[i] == '\n') {
                var end = i;
                while (end > start and (data[end - 1] == '\r' or data[end - 1] == '\n')) end -= 1;
                if (end > start) self.addDirItem(data[start..end]);
                start = i + 1;
            }
        }
    }

    fn addDirItem(self: *App, text: []const u8) void {
        if (self.dir_item_count >= max_dir_items) return;
        const index = self.dir_item_count;
        zero(self.dir_items[index][0..]);
        const len = @min(text.len, dir_item_capacity - 1);
        if (len > 0) @memcpy(self.dir_items[index][0..len], text[0..len]);
        self.dir_items[index][len] = 0;
        self.dir_item_slices[index] = self.dir_items[index][0..len];
        self.dir_item_count += 1;
    }

    fn handleDialogKey(self: *App, key: u8) void {
        switch (self.dialog) {
            .save_prompt => self.handleSavePromptAction(self.savePromptKeyAction(key)),
            .open, .save_as => self.handleFileDialogKey(key),
            .change_font => self.handleFontDialogKey(key),
            .find => self.handleFindDialogKey(key),
            .none => {},
        }
    }

    fn handleFileDialogKey(self: *App, key: u8) void {
        if (key == r4os.gui.Key.escape) {
            self.closeDialog("Cancelled");
            return;
        }
        if (self.dialog == .save_as and key == r4os.gui.Key.backspace) {
            backspaceZ(self.save_file_name[0..], 0);
            return;
        }
        if (self.dialog == .save_as and isFileNameChar(key)) {
            appendZChar(self.save_file_name[0..], key);
            return;
        }

        const dialog = self.fileDialog();
        switch (dialog.keyAction(key)) {
            .ok => self.fileDialogOk(),
            .cancel => self.closeDialog("Cancelled"),
            .previous, .next => |action| {
                self.dialog_selected_index = dialog.selectedIndexForAction(action);
                self.dialog_first_index = self.fileDialog().firstIndexForSelection();
            },
            else => {},
        }
    }

    fn handleFontDialogKey(self: *App, key: u8) void {
        if (key == r4os.gui.Key.escape) {
            self.closeDialog("Cancelled");
            return;
        }
        if (key == r4os.gui.Key.enter or key == ' ') {
            self.applySelectedFont();
            return;
        }
        if (key == r4os.gui.Key.tab or key == r4os.gui.Key.right) {
            self.cycleFontDialogFocus(1);
        } else if (key == r4os.gui.Key.shift_tab or key == r4os.gui.Key.left) {
            self.cycleFontDialogFocus(-1);
        } else if (key == r4os.gui.Key.up) {
            self.stepFontDialogSelection(-1);
        } else if (key == r4os.gui.Key.down) {
            self.stepFontDialogSelection(1);
        }
    }

    fn handleFindDialogKey(self: *App, key: u8) void {
        if (key == r4os.gui.Key.backspace) {
            backspaceZ(self.find_text[0..], 0);
            return;
        }
        if (key >= 0x20 and key < 0x7F) {
            appendZChar(self.find_text[0..], key);
            return;
        }
        switch (self.findDialog().keyAction(key)) {
            .ok => self.findNext(),
            .cancel => self.closeDialog("Cancelled"),
            else => {},
        }
    }

    fn handleDialogMouseDown(self: *App, x: i32, y: i32) void {
        switch (self.dialog) {
            .save_prompt => self.dialog_pressed_action = self.savePromptActionAt(x, y),
            .open, .save_as => self.handleFileDialogMouseDown(x, y),
            .change_font => self.handleFontDialogMouseDown(x, y),
            .find => self.dialog_pressed_action = self.findDialog().actionAt(x, y),
            .none => {},
        }
    }

    fn handleDialogMouseUp(self: *App, x: i32, y: i32) void {
        switch (self.dialog) {
            .save_prompt => {
                const action = self.savePromptActionAt(x, y);
                const pressed = self.dialog_pressed_action;
                self.dialog_pressed_action = .none;
                if (action == pressed) self.handleSavePromptAction(action);
            },
            .open, .save_as => self.handleFileDialogMouseUp(x, y),
            .change_font => self.handleFontDialogMouseUp(x, y),
            .find => self.handleFindDialogMouseUp(x, y),
            .none => {},
        }
    }

    fn handleFindDialogMouseUp(self: *App, x: i32, y: i32) void {
        const action = self.findDialog().actionAt(x, y);
        const pressed = self.dialog_pressed_action;
        self.dialog_pressed_action = .none;
        if (action != pressed) return;
        switch (action) {
            .ok => self.findNext(),
            .cancel => self.closeDialog("Cancelled"),
            else => {},
        }
    }

    fn handleFileDialogMouseDown(self: *App, x: i32, y: i32) void {
        const dialog = self.fileDialog();
        const action = dialog.actionAt(x, y);
        if (action == .select) {
            if (dialog.indexAt(x, y)) |index| {
                self.dialog_selected_index = index;
                self.dialog_first_index = self.fileDialog().firstIndexForSelection();
                self.selectDirEntry(index);
            }
            return;
        }
        self.dialog_pressed_action = action;
    }

    fn handleFileDialogMouseUp(self: *App, x: i32, y: i32) void {
        const dialog = self.fileDialog();
        const action = dialog.actionAt(x, y);
        const pressed = self.dialog_pressed_action;
        self.dialog_pressed_action = .none;
        if (action != pressed) return;
        switch (action) {
            .ok => self.fileDialogOk(),
            .cancel => self.closeDialog("Cancelled"),
            else => {},
        }
    }

    fn handleFontDialogMouseDown(self: *App, x: i32, y: i32) void {
        const rect = self.fontDialogRect();
        if (r4os.gui.listIndexAtEx(self.fontFamilyListRect(rect), self.font_family_count, self.font_family_first, null, r4os.gui.default_metrics.list_row_h, x, y)) |index| {
            self.font_dialog_focus = .family;
            self.selectFontFamily(index);
            return;
        }
        if (r4os.gui.listIndexAtEx(self.fontStyleListRect(rect), self.font_style_count, self.font_style_first, null, r4os.gui.default_metrics.list_row_h, x, y)) |index| {
            self.font_dialog_focus = .style;
            self.selectFontStyle(index);
            return;
        }
        if (r4os.gui.listIndexAtEx(self.fontSizeListRect(rect), self.font_size_count, self.font_size_first, null, r4os.gui.default_metrics.list_row_h, x, y)) |index| {
            self.font_dialog_focus = .size;
            self.font_size_selected = index;
            self.updateFontListFirstIndices();
            return;
        }
        var button_storage: [2]r4os.gui.DialogButton = undefined;
        self.dialog_pressed_action = r4os.gui.dialogButtonActionAt(rect, self.fontDialogButtons(&button_storage), .right, x, y);
    }

    fn handleFontDialogMouseUp(self: *App, x: i32, y: i32) void {
        const rect = self.fontDialogRect();
        var button_storage: [2]r4os.gui.DialogButton = undefined;
        const action = r4os.gui.dialogButtonActionAt(rect, self.fontDialogButtons(&button_storage), .right, x, y);
        const pressed = self.dialog_pressed_action;
        self.dialog_pressed_action = .none;
        if (action != pressed) return;
        switch (action) {
            .ok => self.applySelectedFont(),
            .cancel => self.closeDialog("Cancelled"),
            else => {},
        }
    }

    fn selectDirEntry(self: *App, index: usize) void {
        const kind = self.resolveDirEntry(index);
        if (kind < 0) {
            self.setStatus("Selection failed");
            return;
        }
        if (kind > 0) {
            copyZ(self.current_dir[0..], self.selected_path[0..]);
            if (self.loadDirectory()) {
                self.dialog_selected_index = 0;
                self.dialog_first_index = 0;
                self.setStatus("Opened folder");
            } else {
                self.setStatus("Directory read failed");
            }
            return;
        }
        if (self.dialog == .save_as) setZ(self.save_file_name[0..], baseName(spanZ(self.selected_path[0..])));
        self.setStatus("Selected file");
    }

    fn resolveDirEntry(self: *App, index: usize) i32 {
        if (index >= self.dir_item_count) return -1;
        zero(self.selected_path[0..]);
        const kind = self.ctx.sys.dirEntry(zptr(self.current_dir[0..]), @intCast(index), self.selected_path[0 .. self.selected_path.len - 1]);
        self.selected_path[self.selected_path.len - 1] = 0;
        return kind;
    }

    fn fileDialogOk(self: *App) void {
        if (self.dialog == .save_as) {
            self.saveFromDialog();
            return;
        }
        self.openFromDialog();
    }

    fn openFromDialog(self: *App) void {
        const kind = self.resolveDirEntry(self.dialog_selected_index);
        if (kind < 0) {
            self.setStatus("Selection failed");
            return;
        }
        if (kind > 0) {
            self.selectDirEntry(self.dialog_selected_index);
            return;
        }
        if (self.loadFile(self.selected_path[0..])) {
            self.dialog = .none;
            self.pending_action = .none;
        }
    }

    fn saveFromDialog(self: *App) void {
        if (spanZ(self.save_file_name[0..]).len == 0) {
            self.setStatus("Enter a file name");
            return;
        }
        if (!buildPath(self.current_dir[0..], self.save_file_name[0..], self.selected_path[0..])) {
            self.setStatus("Path too long");
            return;
        }
        const written = self.ctx.sys.fileWrite(zptr(self.selected_path[0..]), self.editor.value());
        if (written < 0 or @as(usize, @intCast(written)) != self.editor.value().len) {
            self.setStatus("Save failed");
            return;
        }
        copyZ(self.current_path[0..], self.selected_path[0..]);
        self.setDirFromPath(spanZ(self.current_path[0..]));
        self.dirty = false;
        self.loaded_truncated = false;
        self.dialog = .none;
        self.setStatus("Saved");
        self.noteRecentDocument();
        const action = self.pending_action;
        self.pending_action = .none;
        self.performAction(action);
    }

    fn loadFile(self: *App, path_buffer: []const u8) bool {
        return self.loadFileWithRecent(path_buffer, true);
    }

    fn loadFileWithRecent(self: *App, path_buffer: []const u8, record_recent: bool) bool {
        self.editor.clear();
        var read_buffer: [512]u8 = .{0} ** 512;
        var path_copy: [path_capacity]u8 = .{0} ** path_capacity;
        copyZ(path_copy[0..], path_buffer);
        var offset: u32 = 0;
        var failed = false;
        while (self.editor.available() > 0) {
            const want = @min(read_buffer.len, self.editor.available());
            const read = self.ctx.sys.fileReadAt(zptr(path_copy[0..]), offset, read_buffer[0..want]);
            if (read < 0) {
                failed = true;
                break;
            }
            if (read == 0) break;
            const len: usize = @intCast(read);
            _ = self.editor.insertSlice(read_buffer[0..len], self.editorView());
            offset += @intCast(len);
            if (len < want) break;
        }

        if (failed) {
            self.editor.clear();
            self.pending_recent_document = false;
            self.setStatus("Open failed");
            return false;
        }

        copyZ(self.current_path[0..], path_copy[0..]);
        self.setDirFromPath(spanZ(self.current_path[0..]));
        self.dirty = false;
        self.loaded_truncated = false;
        if (self.ctx.sys.fileInfo(zptr(path_copy[0..]))) |info| {
            self.loaded_truncated = info.size > offset;
        }
        self.editor.focused = true;
        self.editor.ensureCursorVisible(self.editorView());
        self.setStatus(if (self.loaded_truncated) "Opened truncated at 32 KB limit" else "Opened file");
        if (record_recent) {
            self.pending_recent_document = false;
            self.noteRecentDocument();
        } else {
            self.pending_recent_document = true;
        }
        return true;
    }

    fn flushPendingRecentDocument(self: *App) void {
        if (!self.pending_recent_document) return;
        self.pending_recent_document = false;
        self.noteRecentDocument();
    }

    fn noteRecentDocument(self: *App) void {
        if (self.current_path[0] == 0) return;
        _ = r4os.recent_documents.addOpenedFile(&self.ctx.sys, spanZ(self.current_path[0..]), "Notepad");
    }

    fn closeDialog(self: *App, status: []const u8) void {
        self.dialog = .none;
        self.pending_action = .none;
        self.dialog_pressed_action = .none;
        self.setStatus(status);
    }

    fn savePromptKeyAction(self: *App, key: u8) r4os.gui.DialogAction {
        if (key == 'd' or key == 'D' or key == 'n' or key == 'N') return .no;
        var button_storage: [3]r4os.gui.DialogButton = undefined;
        const buttons = self.savePromptButtons(&button_storage);
        return r4os.gui.dialogKeyAction(buttons, .ok, key);
    }

    fn handleSavePromptAction(self: *App, action: r4os.gui.DialogAction) void {
        switch (action) {
            .ok => {
                self.dialog = .none;
                if (self.current_path[0] == 0) {
                    self.openFileDialog(.save_as);
                    return;
                }
                if (self.saveToCurrentPath()) {
                    const pending = self.pending_action;
                    self.pending_action = .none;
                    self.performAction(pending);
                }
            },
            .no => {
                const pending = self.pending_action;
                self.pending_action = .none;
                self.dialog = .none;
                self.dirty = false;
                self.performAction(pending);
            },
            .cancel => self.closeDialog("Cancelled"),
            else => {},
        }
    }

    fn openFontDialog(self: *App) void {
        self.loadFonts();
        self.dialog = .change_font;
        self.font_dialog_focus = .family;
        self.dialog_pressed_action = .none;
        self.setStatus("Choose editor font, style and native size");
    }

    fn openFindDialog(self: *App) void {
        const selection = self.editor.selectionRange();
        if (!selection.isEmpty()) setZ(self.find_text[0..], self.editor.value()[selection.start..selection.end]);
        self.dialog = .find;
        self.dialog_pressed_action = .none;
        self.setStatus("Enter text to find");
    }

    fn findNext(self: *App) void {
        const needle = spanZ(self.find_text[0..]);
        if (needle.len == 0) {
            self.setStatus("Enter text to find");
            return;
        }

        const selection = self.editor.selectionRange();
        const start = if (!selection.isEmpty()) selection.end else self.editor.cursor;
        const value = self.editor.value();
        const found = findTextIndex(value, needle, start) orelse findTextIndex(value, needle, 0);
        if (found) |index| {
            self.editor.setSelection(index, index + needle.len);
            self.editor.ensureCursorVisible(self.editorView());
            self.dialog = .none;
            self.setStatus("Found text");
        } else {
            self.setStatus("Text not found");
        }
    }

    fn loadFonts(self: *App) void {
        const wanted_path = spanZ(self.editor_font_path[0..]);
        self.font_count = 0;
        var wanted_index: ?usize = null;
        const count = @min(@as(usize, @intCast(self.ctx.draw.fontCount())), max_fonts);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            var info: r4os.abi.GuiFontInfo = .{};
            if (self.ctx.draw.fontInfo(@intCast(i), &info) <= 0) continue;
            if ((info.flags & r4os.abi.gui_font_flag_renderable) == 0) continue;
            const index = self.font_count;
            self.font_infos[index] = info;
            const path = fixedSpan(info.path[0..]);
            if ((wanted_path.len == 0 and info.id == r4os.abi.gui_font_builtin_id) or
                (wanted_path.len > 0 and equalsIgnoreCase(path, wanted_path))) wanted_index = index;
            self.font_count += 1;
        }
        if (self.font_count == 0) {
            self.font_infos[0] = .{
                .id = r4os.abi.gui_font_builtin_id,
                .flags = r4os.abi.gui_font_flag_renderable | r4os.abi.gui_font_flag_builtin,
            };
            setZ(self.font_infos[0].family[0..], "R4OS");
            setZ(self.font_infos[0].face[0..], "Builtin");
            setZ(self.font_infos[0].style[0..], "Regular");
            self.font_count = 1;
        }
        const selected = wanted_index orelse 0;
        self.editor_font_id = self.font_infos[selected].id;
        setZ(self.editor_font_path[0..], fixedSpan(self.font_infos[selected].path[0..]));
        self.rebuildFontChoices(self.editor_font_id);
    }

    fn rebuildFontChoices(self: *App, selected_id: u32) void {
        const selected_info = self.fontInfoById(selected_id);
        self.font_family_count = 0;
        self.font_family_selected = 0;
        var index: usize = 0;
        while (index < self.font_count) : (index += 1) {
            const family = fontFamily(&self.font_infos[index]);
            if (choiceIndex(self.font_family_items[0..], self.font_family_count, family) != null) continue;
            const choice = self.font_family_count;
            setZ(self.font_family_items[choice][0..], family);
            self.font_family_slices[choice] = spanZ(self.font_family_items[choice][0..]);
            if (selected_info) |info| {
                if (equalsIgnoreCase(family, fontFamily(&info))) self.font_family_selected = choice;
            }
            self.font_family_count += 1;
        }
        self.rebuildFontStyles(selected_info);
        self.rebuildFontSizes(selected_id);
        self.updateFontListFirstIndices();
    }

    fn rebuildFontStyles(self: *App, selected_info: ?r4os.abi.GuiFontInfo) void {
        self.font_style_count = 0;
        self.font_style_selected = 0;
        if (self.font_family_count == 0) return;
        const family = self.font_family_slices[self.font_family_selected];
        var index: usize = 0;
        while (index < self.font_count) : (index += 1) {
            const info = self.font_infos[index];
            if (!equalsIgnoreCase(fontFamily(&info), family)) continue;
            const style = fontStyle(&info);
            if (choiceIndex(self.font_style_items[0..], self.font_style_count, style) != null) continue;
            const choice = self.font_style_count;
            setZ(self.font_style_items[choice][0..], style);
            self.font_style_slices[choice] = spanZ(self.font_style_items[choice][0..]);
            if (selected_info) |wanted| {
                if (equalsIgnoreCase(style, fontStyle(&wanted))) self.font_style_selected = choice;
            }
            self.font_style_count += 1;
        }
    }

    fn rebuildFontSizes(self: *App, selected_id: u32) void {
        self.font_size_count = 0;
        self.font_size_selected = 0;
        if (self.font_family_count == 0 or self.font_style_count == 0) return;
        const family = self.font_family_slices[self.font_family_selected];
        const style = self.font_style_slices[self.font_style_selected];
        var index: usize = 0;
        while (index < self.font_count) : (index += 1) {
            const info = self.font_infos[index];
            if (!equalsIgnoreCase(fontFamily(&info), family) or !equalsIgnoreCase(fontStyle(&info), style)) continue;
            var existing: ?usize = null;
            var size_index: usize = 0;
            while (size_index < self.font_size_count) : (size_index += 1) {
                if (self.font_size_values[size_index] == info.height) {
                    existing = size_index;
                    break;
                }
            }
            if (existing) |duplicate| {
                if (info.id == selected_id) self.font_size_ids[duplicate] = info.id;
                continue;
            }
            self.font_size_values[self.font_size_count] = info.height;
            self.font_size_ids[self.font_size_count] = info.id;
            self.font_size_count += 1;
        }
        index = 1;
        while (index < self.font_size_count) : (index += 1) {
            var position = index;
            while (position > 0 and self.font_size_values[position - 1] > self.font_size_values[position]) : (position -= 1) {
                const value = self.font_size_values[position - 1];
                self.font_size_values[position - 1] = self.font_size_values[position];
                self.font_size_values[position] = value;
                const id = self.font_size_ids[position - 1];
                self.font_size_ids[position - 1] = self.font_size_ids[position];
                self.font_size_ids[position] = id;
            }
        }
        index = 0;
        while (index < self.font_size_count) : (index += 1) {
            formatFontSize(self.font_size_items[index][0..], self.font_size_values[index]);
            self.font_size_slices[index] = spanZ(self.font_size_items[index][0..]);
            if (self.font_size_ids[index] == selected_id) self.font_size_selected = index;
        }
    }

    fn selectFontFamily(self: *App, index: usize) void {
        if (index >= self.font_family_count) return;
        self.font_family_selected = index;
        self.rebuildFontStyles(null);
        self.rebuildFontSizes(0);
        self.updateFontListFirstIndices();
    }

    fn selectFontStyle(self: *App, index: usize) void {
        if (index >= self.font_style_count) return;
        self.font_style_selected = index;
        self.rebuildFontSizes(0);
        self.updateFontListFirstIndices();
    }

    fn cycleFontDialogFocus(self: *App, direction: i32) void {
        self.font_dialog_focus = if (direction < 0)
            switch (self.font_dialog_focus) {
                .family => .size,
                .style => .family,
                .size => .style,
            }
        else switch (self.font_dialog_focus) {
            .family => .style,
            .style => .size,
            .size => .family,
        };
    }

    fn stepFontDialogSelection(self: *App, direction: i32) void {
        switch (self.font_dialog_focus) {
            .family => {
                if (self.font_family_count == 0) return;
                const next = steppedIndex(self.font_family_selected, self.font_family_count, direction);
                self.selectFontFamily(next);
            },
            .style => {
                if (self.font_style_count == 0) return;
                const next = steppedIndex(self.font_style_selected, self.font_style_count, direction);
                self.selectFontStyle(next);
            },
            .size => {
                if (self.font_size_count == 0) return;
                self.font_size_selected = steppedIndex(self.font_size_selected, self.font_size_count, direction);
                self.updateFontListFirstIndices();
            },
        }
    }

    fn updateFontListFirstIndices(self: *App) void {
        const rect = self.fontDialogRect();
        self.font_family_first = r4os.gui.listFirstIndexForSelection(self.font_family_count, r4os.gui.visibleListRows(self.fontFamilyListRect(rect), r4os.gui.default_metrics.list_row_h), self.font_family_selected, self.font_family_first);
        self.font_style_first = r4os.gui.listFirstIndexForSelection(self.font_style_count, r4os.gui.visibleListRows(self.fontStyleListRect(rect), r4os.gui.default_metrics.list_row_h), self.font_style_selected, self.font_style_first);
        self.font_size_first = r4os.gui.listFirstIndexForSelection(self.font_size_count, r4os.gui.visibleListRows(self.fontSizeListRect(rect), r4os.gui.default_metrics.list_row_h), self.font_size_selected, self.font_size_first);
    }

    fn fontInfoById(self: *const App, id: u32) ?r4os.abi.GuiFontInfo {
        var index: usize = 0;
        while (index < self.font_count) : (index += 1) {
            if (self.font_infos[index].id == id) return self.font_infos[index];
        }
        return null;
    }

    fn applySelectedFont(self: *App) void {
        if (self.font_size_selected >= self.font_size_count) return;
        self.editor_font_id = self.font_size_ids[self.font_size_selected];
        if (self.fontInfoById(self.editor_font_id)) |info| setZ(self.editor_font_path[0..], fixedSpan(info.path[0..]));
        self.editor.ensureCursorVisible(self.editorView());
        self.dialog = .none;
        self.setStatus("Editor font and size changed");
    }

    fn openInitialArg(self: *App) void {
        const raw = self.ctx.sys.argsRaw();
        if (raw[0] == 0) return;
        copyZPtr(self.selected_path[0..], raw);
        _ = self.loadFileWithRecent(self.selected_path[0..], false);
    }

    fn renderHosted(self: *App) void {
        var paint = switch (r4os.app_gui.beginPaintForSize(&self.ctx.draw, self.hosted_w, self.hosted_h)) {
            .paint => |value| value,
            .failure => return,
        };
        defer paint.discard();
        const canvas = paint.canvas;
        var scratch: [scratch_capacity]u8 = .{0} ** scratch_capacity;
        _ = canvas.clear(r4os.gui.default_palette.face);
        const editor_canvas = self.editorCanvas(canvas);
        _ = r4os.gui.drawTextAreaExWithWrap(editor_canvas, self.editorTextRect(canvas), scratch[0..], self.editor.value(), self.editor.cursor, self.editor.selectionRange(), self.editor.scroll_line, self.editor.scroll_col, self.word_wrap, self.editor.focused, self.editor.disabled, self.editor.palette);
        _ = self.verticalScrollbar(editor_canvas).draw(canvas, scratch[0..]);
        _ = self.horizontalScrollbar(editor_canvas).draw(canvas, scratch[0..]);
        _ = canvas.rect(self.editorScrollbarCornerRect(canvas), r4os.gui.default_palette.face);
        self.renderStatus(canvas, scratch[0..]);
        _ = canvas.menubar(self.menubar(), scratch[0..]);
        self.renderDialog(canvas, scratch[0..]);
        _ = paint.present();
    }

    fn renderStatus(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const rect = self.statusRect(canvas);
        _ = canvas.rect(rect, r4os.gui.default_palette.face);
        _ = canvas.rect(.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = 1 }, r4os.gui.default_palette.face_shadow);
        const status_text = if (self.hosted_status[0] != 0) spanZ(self.hosted_status[0..]) else "Ready";
        _ = r4os.gui.drawTextInRect(canvas, rect.inset(6, 2), scratch, status_text, .left, r4os.gui.default_palette.text, r4os.gui.default_palette.face);
        const marker = if (self.loaded_truncated) "TRUNCATED" else if (self.dirty) "Modified" else if (self.current_path[0] != 0) spanZ(self.current_path[0..]) else "Untitled";
        _ = r4os.gui.drawTextInRect(canvas, rect.inset(6, 2), scratch, marker, .right, r4os.gui.default_palette.text, r4os.gui.default_palette.face);
    }

    fn renderDialog(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        switch (self.dialog) {
            .none => {},
            .open, .save_as => _ = canvas.fileDialog(self.fileDialog(), scratch),
            .save_prompt => self.drawSavePrompt(canvas, scratch),
            .change_font => self.drawFontDialog(canvas, scratch),
            .find => _ = canvas.inputDialog(self.findDialog(), scratch),
        }
    }

    fn drawSavePrompt(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const rect = self.savePromptRect();
        var button_storage: [3]r4os.gui.DialogButton = undefined;
        _ = r4os.gui.drawDialogFrame(canvas, rect, scratch, "Notepad", r4os.gui.default_palette);
        _ = r4os.gui.drawTextInRect(canvas, rect.inset(12, 34), scratch, "Save changes to this document?", .left, r4os.gui.default_palette.text, r4os.gui.default_palette.face);
        _ = r4os.gui.drawDialogButtons(canvas, rect, scratch, self.savePromptButtons(&button_storage), .ok, self.dialog_pressed_action, .right, r4os.gui.default_palette);
    }

    fn drawFontDialog(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const rect = self.fontDialogRect();
        _ = r4os.gui.drawDialogFrame(canvas, rect, scratch, "Change Font", r4os.gui.default_palette);
        _ = canvas.text(self.fontFamilyListRect(rect).x, rect.y + 27, "Font:", r4os.gui.default_palette.text, r4os.gui.default_palette.face);
        _ = canvas.text(self.fontStyleListRect(rect).x, rect.y + 27, "Style:", r4os.gui.default_palette.text, r4os.gui.default_palette.face);
        _ = canvas.text(self.fontSizeListRect(rect).x, rect.y + 27, "Size:", r4os.gui.default_palette.text, r4os.gui.default_palette.face);
        _ = (r4os.gui.List{
            .rect = self.fontFamilyListRect(rect),
            .items = self.font_family_slices[0..self.font_family_count],
            .selected_index = self.font_family_selected,
            .first_index = self.font_family_first,
            .focused = self.font_dialog_focus == .family,
        }).draw(canvas, scratch);
        _ = (r4os.gui.List{
            .rect = self.fontStyleListRect(rect),
            .items = self.font_style_slices[0..self.font_style_count],
            .selected_index = self.font_style_selected,
            .first_index = self.font_style_first,
            .focused = self.font_dialog_focus == .style,
        }).draw(canvas, scratch);
        _ = (r4os.gui.List{
            .rect = self.fontSizeListRect(rect),
            .items = self.font_size_slices[0..self.font_size_count],
            .selected_index = self.font_size_selected,
            .first_index = self.font_size_first,
            .focused = self.font_dialog_focus == .size,
        }).draw(canvas, scratch);
        if (self.font_size_count > 0) {
            const selected_id = self.font_size_ids[self.font_size_selected];
            const preview = canvas.withFontId(selected_id);
            const preview_rect = self.fontPreviewRect(rect);
            _ = canvas.groupBox(.{ .rect = preview_rect, .title = "Sample" }, scratch);
            _ = preview.textClipped(preview_rect.x + 8, preview_rect.y + 16, preview_rect.w - 16, scratch, "AaBbYyZz 123", r4os.gui.default_palette.text, r4os.gui.default_palette.face);
        }
        var button_storage: [2]r4os.gui.DialogButton = undefined;
        _ = r4os.gui.drawDialogButtons(canvas, rect, scratch, self.fontDialogButtons(&button_storage), .ok, self.dialog_pressed_action, .right, r4os.gui.default_palette);
    }

    fn appCanvas(self: *App) r4os.gui.Canvas {
        return r4os.gui.Canvas.initSize(&self.ctx.draw, self.hosted_w, self.hosted_h);
    }

    fn editorCanvas(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Canvas {
        return canvas.withFontId(self.editor_font_id);
    }

    fn menubar(self: *App) r4os.gui.Menubar {
        const menus = buildAppMenus(&self.menu_storage, self.word_wrap);
        return .{
            .rect = self.menubarRect(self.appCanvas()),
            .menus = menus,
            .state = self.menubar_state,
        };
    }

    fn menubarRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        _ = self;
        return .{ .x = 0, .y = 0, .w = canvas.w, .h = r4os.gui.default_metrics.menu_bar_h };
    }

    fn editorRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        _ = self;
        return .{
            .x = 4,
            .y = r4os.gui.default_metrics.menu_bar_h + 4,
            .w = @max(0, canvas.w - 8),
            .h = @max(0, canvas.h - r4os.gui.default_metrics.menu_bar_h - status_h - 8),
        };
    }

    fn editorScrollbarSize(self: *App, canvas: r4os.gui.Canvas) i32 {
        const rect = self.editorRect(canvas);
        return @min(r4os.gui.default_metrics.scrollbar_w, @min(rect.w, rect.h));
    }

    fn editorTextRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        const rect = self.editorRect(canvas);
        const size = self.editorScrollbarSize(canvas);
        return .{ .x = rect.x, .y = rect.y, .w = @max(0, rect.w - size), .h = @max(0, rect.h - size) };
    }

    fn verticalScrollbarRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        const rect = self.editorRect(canvas);
        const size = self.editorScrollbarSize(canvas);
        return .{ .x = rect.right() - size, .y = rect.y, .w = size, .h = @max(0, rect.h - size) };
    }

    fn horizontalScrollbarRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        const rect = self.editorRect(canvas);
        const size = self.editorScrollbarSize(canvas);
        return .{ .x = rect.x, .y = rect.bottom() - size, .w = @max(0, rect.w - size), .h = size };
    }

    fn editorScrollbarCornerRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        const rect = self.editorRect(canvas);
        const size = self.editorScrollbarSize(canvas);
        return .{ .x = rect.right() - size, .y = rect.bottom() - size, .w = size, .h = size };
    }

    fn verticalScrollbar(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Scrollbar {
        const view = self.editorViewForCanvas(canvas);
        const total = r4os.gui.textAreaVisualLineCount(self.editor.value(), view.effectiveWrapCols());
        return .{
            .rect = self.verticalScrollbarRect(canvas),
            .orientation = .vertical,
            .total_items = total,
            .visible_items = view.effectiveVisibleRows(),
            .first_index = self.editor.scroll_line,
            .disabled = total <= view.effectiveVisibleRows(),
        };
    }

    fn horizontalScrollbar(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Scrollbar {
        const view = self.editorViewForCanvas(canvas);
        const total = if (self.word_wrap) 0 else r4os.gui.textAreaVisualMaxColumns(self.editor.value(), 0);
        return .{
            .rect = self.horizontalScrollbarRect(canvas),
            .orientation = .horizontal,
            .total_items = total,
            .visible_items = view.effectiveVisibleCols(),
            .first_index = self.editor.scroll_col,
            .disabled = self.word_wrap or total <= view.effectiveVisibleCols(),
        };
    }

    fn statusRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        _ = self;
        return .{ .x = 0, .y = @max(0, canvas.h - status_h), .w = canvas.w, .h = status_h };
    }

    fn editorView(self: *App) r4os.gui.TextAreaView {
        const canvas = self.editorCanvas(self.appCanvas());
        return self.editorViewForCanvas(canvas);
    }

    fn editorViewForCanvas(self: *App, canvas: r4os.gui.Canvas) r4os.gui.TextAreaView {
        var view = r4os.gui.textAreaViewForRect(canvas, self.editorTextRect(canvas));
        view.wrap_cols = if (self.word_wrap) view.visible_cols else 0;
        return view;
    }

    fn fileDialog(self: *App) r4os.gui.FileDialog {
        const mode: r4os.gui.FileDialogMode = if (self.dialog == .save_as) .save else .open;
        return .{
            .rect = self.fileDialogRect(),
            .title = if (mode == .save) "Save As" else "Open",
            .path = spanZ(self.current_dir[0..]),
            .items = self.dir_item_slices[0..self.dir_item_count],
            .mode = mode,
            .file_name = if (mode == .save) spanZ(self.save_file_name[0..]) else "",
            .ok_text = if (mode == .save) "Save" else "Open",
            .cancel_text = "Cancel",
            .selected_index = @min(self.dialog_selected_index, if (self.dir_item_count == 0) 0 else self.dir_item_count - 1),
            .hover_index = self.dialog_hover_index,
            .first_index = self.dialog_first_index,
            .focus_action = .select,
            .pressed_action = self.dialog_pressed_action,
        };
    }

    fn fileDialogRect(self: *App) r4os.gui.Rect {
        const canvas = self.appCanvas();
        const width = @min(520, @max(300, canvas.w - 24));
        const height = @min(340, @max(220, canvas.h - 36));
        return r4os.gui.centeredRect(canvas.bounds(), width, height);
    }

    fn savePromptRect(self: *App) r4os.gui.Rect {
        return r4os.gui.centeredRect(self.appCanvas().bounds(), @min(360, @max(260, self.hosted_w - 40)), 116);
    }

    fn fontDialogRect(self: *App) r4os.gui.Rect {
        return r4os.gui.centeredRect(self.appCanvas().bounds(), @min(520, @max(360, self.hosted_w - 40)), @min(360, @max(260, self.hosted_h - 40)));
    }

    fn findDialogRect(self: *App) r4os.gui.Rect {
        return r4os.gui.centeredRect(self.appCanvas().bounds(), @min(380, @max(260, self.hosted_w - 40)), 126);
    }

    fn fontFamilyListRect(self: *App, rect: r4os.gui.Rect) r4os.gui.Rect {
        _ = self;
        const available = @max(0, rect.w - 32);
        return .{ .x = rect.x + 12, .y = rect.y + 42, .w = @max(80, @divTrunc(available * 46, 100)), .h = @max(54, rect.h - 156) };
    }

    fn fontStyleListRect(self: *App, rect: r4os.gui.Rect) r4os.gui.Rect {
        const family = self.fontFamilyListRect(rect);
        const available = @max(0, rect.w - 32);
        return .{ .x = family.right() + 4, .y = family.y, .w = @max(70, @divTrunc(available * 30, 100)), .h = family.h };
    }

    fn fontSizeListRect(self: *App, rect: r4os.gui.Rect) r4os.gui.Rect {
        const style = self.fontStyleListRect(rect);
        return .{ .x = style.right() + 4, .y = style.y, .w = @max(54, rect.right() - 12 - (style.right() + 4)), .h = style.h };
    }

    fn fontPreviewRect(self: *App, rect: r4os.gui.Rect) r4os.gui.Rect {
        const list = self.fontFamilyListRect(rect);
        return .{ .x = rect.x + 12, .y = list.bottom() + 10, .w = rect.w - 24, .h = 54 };
    }

    fn findDialog(self: *App) r4os.gui.InputDialog {
        return .{
            .rect = self.findDialogRect(),
            .title = "Find",
            .label = "Find what:",
            .value = spanZ(self.find_text[0..]),
            .ok_text = "Find Next",
            .cancel_text = "Cancel",
            .focus_action = .select,
            .pressed_action = self.dialog_pressed_action,
        };
    }

    fn savePromptButtons(self: *App, out: *[3]r4os.gui.DialogButton) []const r4os.gui.DialogButton {
        _ = self;
        out.* = .{
            .{ .action = .ok, .text = "Save", .role = .default },
            .{ .action = .no, .text = "Don't Save" },
            .{ .action = .cancel, .text = "Cancel", .role = .cancel },
        };
        return out[0..];
    }

    fn fontDialogButtons(self: *App, out: *[2]r4os.gui.DialogButton) []const r4os.gui.DialogButton {
        _ = self;
        out.* = .{
            .{ .action = .ok, .text = "OK", .role = .default },
            .{ .action = .cancel, .text = "Cancel", .role = .cancel },
        };
        return out[0..];
    }

    fn savePromptActionAt(self: *App, x: i32, y: i32) r4os.gui.DialogAction {
        var button_storage: [3]r4os.gui.DialogButton = undefined;
        return r4os.gui.dialogButtonActionAt(self.savePromptRect(), self.savePromptButtons(&button_storage), .right, x, y);
    }

    fn setDirFromPath(self: *App, path: []const u8) void {
        var last_sep: ?usize = null;
        var i: usize = 0;
        while (i < path.len) : (i += 1) {
            if (path[i] == '\\' or path[i] == '/') last_sep = i;
        }
        if (last_sep) |sep| {
            setZ(self.current_dir[0..], path[0 .. sep + 1]);
        } else {
            setZ(self.current_dir[0..], "C:\\");
        }
    }

    fn setStatus(self: *App, message: []const u8) void {
        setZ(self.hosted_status[0..], message);
    }
};

fn buildAppMenus(out: *AppMenus, word_wrap: bool) []const r4os.gui.MenubarMenu {
    out.file_items = .{
        .{ .text = "New", .id = @intFromEnum(Command.file_new), .shortcut = "Ctrl+N" },
        .{ .text = "Open", .id = @intFromEnum(Command.file_open), .shortcut = "Ctrl+O" },
        .{ .text = "Save", .id = @intFromEnum(Command.file_save), .shortcut = "Ctrl+S" },
        .{ .text = "Save As", .id = @intFromEnum(Command.file_save_as) },
        .{ .text = "Exit", .id = @intFromEnum(Command.file_exit), .separator_before = true },
    };
    out.settings_items = .{
        .{ .text = "Change Font", .id = @intFromEnum(Command.settings_change_font) },
        .{ .text = if (word_wrap) "Word Wrap: On" else "Word Wrap: Off", .id = @intFromEnum(Command.settings_toggle_word_wrap), .separator_before = true },
    };
    out.edit_items = .{
        .{ .text = "Copy", .id = @intFromEnum(Command.edit_copy), .shortcut = "Ctrl+C" },
        .{ .text = "Paste", .id = @intFromEnum(Command.edit_paste), .shortcut = "Ctrl+V" },
    };
    out.search_items = .{
        .{ .text = "Find...", .id = @intFromEnum(Command.search_find), .shortcut = "Ctrl+F" },
    };
    out.menus = .{
        .{ .text = "File", .items = out.file_items[0..] },
        .{ .text = "Settings", .items = out.settings_items[0..] },
        .{ .text = "Edit", .items = out.edit_items[0..] },
        .{ .text = "Search", .items = out.search_items[0..] },
    };
    return out.menus[0..];
}

pub fn r4_app_main(r4_app: *r4os.App) i32 {
    var ctx = AppApi.init(r4_app) orelse return r4os.abi.err_no_group;
    if (hasArg(ctx.sys.argsRaw(), "/SELFTEST")) return runFontChoiceSelfTest(&ctx);
    var app = App{ .ctx = &ctx };
    app.init();
    return app.run();
}

fn runFontChoiceSelfTest(ctx: *AppApi) i32 {
    var app = App{ .ctx = ctx };
    setTestFont(&app.font_infos[0], 16, "Courier", "Regular", 16, "C:\\R4OS\\FONTS\\COUR16.R4F");
    setTestFont(&app.font_infos[1], 8, "Courier", "Regular", 8, "C:\\R4OS\\FONTS\\COUR08.R4F");
    setTestFont(&app.font_infos[2], 12, "Courier", "Regular", 12, "C:\\R4OS\\FONTS\\COUR12.R4F");
    setTestFont(&app.font_infos[3], 112, "Courier", "Bold", 12, "C:\\R4OS\\FONTS\\COURB.R4F");
    setTestFont(&app.font_infos[4], 216, "Terminal", "Regular", 16, "C:\\R4OS\\FONTS\\TERM16.R4F");
    app.font_count = 5;
    app.rebuildFontChoices(12);
    if (app.font_family_count != 2 or app.font_style_count != 2 or app.font_size_count != 3) return fontChoiceSelfTestFail(ctx, "choice-counts");
    if (!equalsIgnoreCase(app.font_family_slices[app.font_family_selected], "Courier")) return fontChoiceSelfTestFail(ctx, "selected-family");
    if (!equalsIgnoreCase(app.font_style_slices[app.font_style_selected], "Regular")) return fontChoiceSelfTestFail(ctx, "selected-style");
    if (app.font_size_values[0] != 8 or app.font_size_values[1] != 12 or app.font_size_values[2] != 16) return fontChoiceSelfTestFail(ctx, "sorted-sizes");
    if (app.font_size_ids[app.font_size_selected] != 12) return fontChoiceSelfTestFail(ctx, "selected-size");
    app.selectFontFamily(1);
    if (!equalsIgnoreCase(app.font_family_slices[app.font_family_selected], "Terminal") or app.font_size_count != 1 or app.font_size_values[0] != 16) return fontChoiceSelfTestFail(ctx, "dependent-selection");
    ctx.sys.println("NOTEPAD font size selftest: OK");
    return 0;
}

fn setTestFont(out: *r4os.abi.GuiFontInfo, id: u32, family: []const u8, style: []const u8, height: u32, path: []const u8) void {
    out.* = .{
        .id = id,
        .flags = r4os.abi.gui_font_flag_renderable,
        .height = height,
        .line_height = height,
    };
    setZ(out.family[0..], family);
    setZ(out.face[0..], family);
    setZ(out.style[0..], style);
    setZ(out.path[0..], path);
}

fn fontChoiceSelfTestFail(ctx: *AppApi, label: []const u8) i32 {
    ctx.sys.write("NOTEPAD font size selftest FAILED: ");
    ctx.sys.println(label);
    return 1;
}

fn zptr(buffer: []const u8) [*:0]const u8 {
    return @ptrCast(buffer.ptr);
}

fn zero(buffer: []u8) void {
    @memset(buffer, 0);
}

fn setZ(buffer: []u8, text: []const u8) void {
    zero(buffer);
    const len = @min(buffer.len - 1, text.len);
    if (len > 0) @memcpy(buffer[0..len], text[0..len]);
    buffer[len] = 0;
}

fn copyZ(dest: []u8, source: []const u8) void {
    setZ(dest, spanZ(source));
}

fn copyZPtr(dest: []u8, source: [*:0]const u8) void {
    zero(dest);
    var i: usize = 0;
    while (i + 1 < dest.len and source[i] != 0) : (i += 1) dest[i] = source[i];
    if (dest.len > 0) dest[i] = 0;
}

fn appendSliceZ(buffer: []u8, text: []const u8) void {
    var len = zlen(buffer);
    var i: usize = 0;
    while (len + 1 < buffer.len and i < text.len) : ({
        len += 1;
        i += 1;
    }) {
        buffer[len] = text[i];
    }
    if (len < buffer.len) buffer[len] = 0;
}

fn appendZChar(buffer: []u8, ch: u8) void {
    const len = zlen(buffer);
    if (len + 1 >= buffer.len) return;
    buffer[len] = ch;
    buffer[len + 1] = 0;
}

fn backspaceZ(buffer: []u8, min_len: usize) void {
    const len = zlen(buffer);
    if (len <= min_len) return;
    buffer[len - 1] = 0;
}

fn zlen(buffer: []const u8) usize {
    var len: usize = 0;
    while (len < buffer.len and buffer[len] != 0) : (len += 1) {}
    return len;
}

fn spanZ(buffer: []const u8) []const u8 {
    return buffer[0..zlen(buffer)];
}

fn fixedSpan(buffer: []const u8) []const u8 {
    return spanZ(buffer);
}

fn fontFamily(info: *const r4os.abi.GuiFontInfo) []const u8 {
    const family = fixedSpan(info.family[0..]);
    return if (family.len > 0) family else "Unknown";
}

fn fontStyle(info: *const r4os.abi.GuiFontInfo) []const u8 {
    const style = fixedSpan(info.style[0..]);
    return if (style.len > 0) style else "Regular";
}

fn choiceIndex(items: []const [font_name_capacity]u8, count: usize, wanted: []const u8) ?usize {
    var index: usize = 0;
    while (index < count and index < items.len) : (index += 1) {
        if (equalsIgnoreCase(spanZ(items[index][0..]), wanted)) return index;
    }
    return null;
}

fn steppedIndex(current: usize, count: usize, direction: i32) usize {
    if (count == 0) return 0;
    if (direction < 0) return if (current == 0 or current >= count) count - 1 else current - 1;
    return if (current + 1 >= count) 0 else current + 1;
}

fn formatFontSize(out: []u8, value: u32) void {
    zero(out);
    appendUnsignedZ(out, value);
    appendSliceZ(out, " px");
}

fn appendUnsignedZ(out: []u8, value: u32) void {
    var digits: [10]u8 = undefined;
    var remaining = value;
    var count: usize = 0;
    if (remaining == 0) {
        appendZChar(out, '0');
        return;
    }
    while (remaining > 0) : (remaining /= 10) {
        digits[count] = '0' + @as(u8, @intCast(remaining % 10));
        count += 1;
    }
    while (count > 0) {
        count -= 1;
        appendZChar(out, digits[count]);
    }
}

fn equalsIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    var index: usize = 0;
    while (index < left.len) : (index += 1) {
        if (asciiUpper(left[index]) != asciiUpper(right[index])) return false;
    }
    return true;
}

fn asciiUpper(ch: u8) u8 {
    return if (ch >= 'a' and ch <= 'z') ch - 32 else ch;
}

fn hasArg(args: [*:0]const u8, wanted: []const u8) bool {
    var cursor: usize = 0;
    while (cursor < 256 and args[cursor] != 0) {
        while (cursor < 256 and (args[cursor] == ' ' or args[cursor] == '\t')) : (cursor += 1) {}
        const start = cursor;
        while (cursor < 256 and args[cursor] != 0 and args[cursor] != ' ' and args[cursor] != '\t') : (cursor += 1) {}
        var equal = cursor - start == wanted.len;
        var index: usize = 0;
        while (equal and index < wanted.len) : (index += 1) {
            if (asciiUpper(args[start + index]) != asciiUpper(wanted[index])) equal = false;
        }
        if (equal) return true;
    }
    return false;
}

fn baseName(path: []const u8) []const u8 {
    var start: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '\\' or path[i] == '/') start = i + 1;
    }
    return path[start..];
}

fn buildPath(dir_buffer: []const u8, name_buffer: []const u8, out: []u8) bool {
    const dir = spanZ(dir_buffer);
    const name = spanZ(name_buffer);
    if (name.len == 0 or out.len == 0) return false;
    zero(out);
    if (isAbsolutePath(name)) {
        if (name.len + 1 > out.len) return false;
        @memcpy(out[0..name.len], name);
        out[name.len] = 0;
        return true;
    }
    var len: usize = @min(dir.len, out.len - 1);
    if (len > 0) @memcpy(out[0..len], dir[0..len]);
    if (len > 0 and out[len - 1] != '\\' and out[len - 1] != '/') {
        if (len + 1 >= out.len) return false;
        out[len] = '\\';
        len += 1;
    }
    if (len + name.len + 1 > out.len) return false;
    @memcpy(out[len .. len + name.len], name);
    out[len + name.len] = 0;
    return true;
}

fn isAbsolutePath(path: []const u8) bool {
    if (path.len >= 2 and path[1] == ':') return true;
    return path.len > 0 and (path[0] == '\\' or path[0] == '/');
}

fn isFileNameChar(ch: u8) bool {
    if (ch < 0x20 or ch >= 0x7F) return false;
    return ch != '\\' and ch != '/' and ch != ':' and ch != '*' and ch != '?' and ch != '"' and ch != '<' and ch != '>' and ch != '|';
}

fn isTextEditingCodepoint(codepoint: u32) bool {
    const printable = codepoint >= 0x20 and codepoint <= 0x10ffff and
        !(codepoint >= 0x7f and codepoint <= 0x9f) and
        !(codepoint >= 0xd800 and codepoint <= 0xdfff);
    return printable or codepoint == r4os.gui.Key.backspace or codepoint == r4os.gui.Key.delete or codepoint == r4os.gui.Key.enter or codepoint == '\n' or codepoint == r4os.gui.Key.tab;
}

fn findTextIndex(value: []const u8, needle: []const u8, start: usize) ?usize {
    if (needle.len == 0 or needle.len > value.len) return null;
    var index = @min(start, value.len);
    while (index + needle.len <= value.len) : (index += 1) {
        var match = true;
        var needle_index: usize = 0;
        while (needle_index < needle.len) : (needle_index += 1) {
            if (value[index + needle_index] != needle[needle_index]) {
                match = false;
                break;
            }
        }
        if (match) return index;
    }
    return null;
}

fn clampI32(value: i32, min_value: i32, max_value: i32) i32 {
    if (value < min_value) return min_value;
    if (value > max_value) return max_value;
    return value;
}
