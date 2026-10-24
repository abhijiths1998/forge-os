#include "pamac_channel.h"

#include <gio/gdesktopappinfo.h>
#include <pamac.h>

#include <cstring>

namespace {

struct Store {
  FlMethodChannel* channel;
  GtkWindow* window;
  PamacConfig* config;
  PamacDatabase* db;
  GSubprocess* transaction;  // the running `pamac` command, if any
  GDataInputStream* output;
};

Store* store = nullptr;

// --- FlValue helpers ---------------------------------------------------------

void set_str(FlValue* m, const char* key, const char* value) {
  fl_value_set_string_take(m, key, fl_value_new_string(value ? value : ""));
}

void set_int(FlValue* m, const char* key, int64_t value) {
  fl_value_set_string_take(m, key, fl_value_new_int(value));
}

void set_date(FlValue* m, const char* key, GDateTime* date) {
  g_autofree gchar* text =
      date ? g_date_time_format(date, "%Y-%m-%d") : nullptr;
  set_str(m, key, text);
}

// A GPtrArray of strings (dependency lists, screenshots) as a list.
void set_strv(FlValue* m, const char* key, GPtrArray* items) {
  FlValue* list = fl_value_new_list();
  for (guint i = 0; items && i < items->len; i++) {
    fl_value_append_take(
        list, fl_value_new_string(static_cast<const char*>(items->pdata[i])));
  }
  fl_value_set_string_take(m, key, list);
}

FlValue* package_to_value(PamacPackage* pkg, bool details) {
  FlValue* m = fl_value_new_map();
  set_str(m, "name", pamac_package_get_name(pkg));
  set_str(m, "appName", pamac_package_get_app_name(pkg));
  set_str(m, "appId", pamac_package_get_app_id(pkg));
  set_str(m, "version", pamac_package_get_version(pkg));
  set_str(m, "installedVersion", pamac_package_get_installed_version(pkg));
  set_str(m, "desc", pamac_package_get_desc(pkg));
  set_str(m, "repo", pamac_package_get_repo(pkg));
  set_str(m, "icon", pamac_package_get_icon(pkg));
  set_str(m, "launchable", pamac_package_get_launchable(pkg));
  set_int(m, "downloadSize",
          static_cast<int64_t>(pamac_package_get_download_size(pkg)));
  set_int(m, "installedSize",
          static_cast<int64_t>(pamac_package_get_installed_size(pkg)));
  const bool aur = PAMAC_IS_AUR_PACKAGE(pkg);
  fl_value_set_string_take(m, "aur", fl_value_new_bool(aur));
  if (!details) return m;

  set_str(m, "longDesc", pamac_package_get_long_desc(pkg));
  set_str(m, "url", pamac_package_get_url(pkg));
  set_str(m, "license", pamac_package_get_license(pkg));
  set_strv(m, "screenshots", pamac_package_get_screenshots(pkg));
  if (PAMAC_IS_ALPM_PACKAGE(pkg)) {
    PamacAlpmPackage* alpm = PAMAC_ALPM_PACKAGE(pkg);
    set_str(m, "packager", pamac_alpm_package_get_packager(alpm));
    set_date(m, "buildDate", pamac_alpm_package_get_build_date(alpm));
    set_date(m, "installDate", pamac_package_get_install_date(pkg));
    set_strv(m, "depends", pamac_alpm_package_get_depends(alpm));
    set_strv(m, "optdepends", pamac_alpm_package_get_optdepends(alpm));
    set_strv(m, "requiredBy", pamac_alpm_package_get_requiredby(alpm));
  }
  if (aur) {
    PamacAURPackage* a = PAMAC_AUR_PACKAGE(pkg);
    set_str(m, "maintainer", pamac_aur_package_get_maintainer(a));
    set_int(m, "votes", static_cast<int64_t>(pamac_aur_package_get_numvotes(a)));
    set_date(m, "lastModified", pamac_aur_package_get_lastmodified(a));
    set_date(m, "outOfDate", pamac_aur_package_get_outofdate(a));
  }
  return m;
}

FlValue* packages_to_value(GPtrArray* pkgs) {
  FlValue* list = fl_value_new_list();
  for (guint i = 0; pkgs && i < pkgs->len; i++) {
    fl_value_append_take(
        list, package_to_value(PAMAC_PACKAGE(pkgs->pdata[i]), false));
  }
  return list;
}

const char* string_arg(FlValue* args, const char* key) {
  FlValue* v = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                   ? fl_value_lookup_string(args, key)
                   : nullptr;
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(v)
             : "";
}

int64_t int_arg(FlValue* args, const char* key, int64_t fallback) {
  FlValue* v = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                   ? fl_value_lookup_string(args, key)
                   : nullptr;
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_INT ? fl_value_get_int(v)
                                                        : fallback;
}

void respond(FlMethodCall* call, FlValue* value) {
  g_autoptr(FlMethodResponse) r =
      FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  fl_method_call_respond(call, r, nullptr);
}

void respond_error(FlMethodCall* call, const char* code, const char* msg) {
  g_autoptr(FlMethodResponse) r =
      FL_METHOD_RESPONSE(fl_method_error_response_new(code, msg, nullptr));
  fl_method_call_respond(call, r, nullptr);
}

// --- Async package queries ---------------------------------------------------
// Each *_async call carries the FlMethodCall (a ref) as user data and
// answers it when libpamac is done, so the UI never waits on a query.

using Finish = GPtrArray* (*)(PamacDatabase*, GAsyncResult*);

template <Finish finish>
void list_done(GObject* source, GAsyncResult* res, gpointer data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
  GPtrArray* pkgs = finish(PAMAC_DATABASE(source), res);
  g_autoptr(FlValue) list = packages_to_value(pkgs);
  if (pkgs) g_ptr_array_unref(pkgs);
  respond(call, list);
}

void updates_done(GObject* source, GAsyncResult* res, gpointer data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
  PamacUpdates* updates =
      pamac_database_get_updates_finish(PAMAC_DATABASE(source), res);
  g_autoptr(FlValue) m = fl_value_new_map();
  fl_value_set_string_take(
      m, "repos",
      packages_to_value(updates ? pamac_updates_get_repos_updates(updates)
                                : nullptr));
  fl_value_set_string_take(
      m, "aur",
      packages_to_value(updates ? pamac_updates_get_aur_updates(updates)
                                : nullptr));
  if (updates) g_object_unref(updates);
  respond(call, m);
}

void aur_details_done(GObject* source, GAsyncResult* res, gpointer data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
  PamacAURPackage* pkg =
      pamac_database_get_aur_pkg_finish(PAMAC_DATABASE(source), res);
  if (pkg == nullptr) {
    respond(call, nullptr);
    return;
  }
  g_autoptr(FlValue) v = package_to_value(PAMAC_PACKAGE(pkg), true);
  g_object_unref(pkg);
  respond(call, v);
}

// --- Icons -------------------------------------------------------------------

// PNG bytes for an icon: an image file (AppStream ships JPEG XL, which
// Flutter can't decode but GdkPixbuf can), else a name from the GTK icon
// theme, else a generic package icon. Empty for a file that won't load, so
// the UI can fall back to the theme.
FlValue* icon_png(const char* name, int size) {
  const int scale = gtk_widget_get_scale_factor(GTK_WIDGET(store->window));
  g_autoptr(GdkPixbuf) pixbuf = nullptr;
  if (name[0] == '/') {
    pixbuf = gdk_pixbuf_new_from_file_at_scale(name, size * scale,
                                               size * scale, TRUE, nullptr);
    if (pixbuf == nullptr) return fl_value_new_null();
  } else {
    GtkIconTheme* theme = gtk_icon_theme_get_default();
    const auto flags = GTK_ICON_LOOKUP_FORCE_SIZE;
    g_autoptr(GtkIconInfo) info =
        *name ? gtk_icon_theme_lookup_icon_for_scale(theme, name, size, scale,
                                                     flags)
              : nullptr;
    if (info == nullptr) {
      info = gtk_icon_theme_lookup_icon_for_scale(theme, "package-x-generic",
                                                  size, scale, flags);
    }
    if (info == nullptr) return fl_value_new_null();
    pixbuf = gtk_icon_info_load_icon(info, nullptr);
  }
  gchar* buffer = nullptr;
  gsize length = 0;
  if (pixbuf == nullptr || !gdk_pixbuf_save_to_buffer(
                               pixbuf, &buffer, &length, "png", nullptr,
                               nullptr)) {
    return fl_value_new_null();
  }
  FlValue* bytes =
      fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(buffer), length);
  g_free(buffer);
  return bytes;
}

// --- Transactions: the pamac CLI, its output streamed to the UI --------------

void read_line(void);

void line_read(GObject* source, GAsyncResult* res, gpointer) {
  gsize length = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* line = g_data_input_stream_read_line_finish_utf8(
      G_DATA_INPUT_STREAM(source), res, &length, &error);
  if (line != nullptr) {
    fl_method_channel_invoke_method(store->channel, "txOutput",
                                    fl_value_new_string(line), nullptr,
                                    nullptr, nullptr);
    read_line();
  }
  // End of output: transaction_done reports the exit status.
}

void read_line() {
  g_data_input_stream_read_line_async(store->output, G_PRIORITY_DEFAULT,
                                      nullptr, line_read, nullptr);
}

void transaction_done(GObject* source, GAsyncResult* res, gpointer) {
  GSubprocess* proc = G_SUBPROCESS(source);
  g_subprocess_wait_finish(proc, res, nullptr);
  const int status =
      g_subprocess_get_if_exited(proc) ? g_subprocess_get_exit_status(proc) : -1;
  g_clear_object(&store->output);
  g_clear_object(&store->transaction);
  // Fresh handle so the next query sees the new installed state.
  g_clear_object(&store->db);
  store->db = pamac_database_new(store->config);
  fl_method_channel_invoke_method(store->channel, "txDone",
                                  fl_value_new_int(status), nullptr, nullptr,
                                  nullptr);
}

bool start_transaction(FlValue* args, GError** error) {
  FlValue* list = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                      ? fl_value_lookup_string(args, "args")
                      : nullptr;
  if (list == nullptr || fl_value_get_type(list) != FL_VALUE_TYPE_LIST) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "no args");
    return false;
  }
  // Only pamac's own transaction verbs, so the UI can't run anything else.
  static const char* const verbs[] = {"install", "remove", "build",
                                      "upgrade", "update", nullptr};
  const size_t n = fl_value_get_length(list);
  if (n == 0 || !g_strv_contains(verbs, fl_value_get_string(
                                            fl_value_get_list_value(list, 0)))) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "bad verb");
    return false;
  }
  g_autoptr(GPtrArray) argv = g_ptr_array_new();
  g_ptr_array_add(argv, const_cast<char*>("pamac"));
  for (size_t i = 0; i < n; i++) {
    g_ptr_array_add(argv, const_cast<char*>(fl_value_get_string(
                              fl_value_get_list_value(list, i))));
  }
  g_ptr_array_add(argv, const_cast<char*>("--no-confirm"));
  g_ptr_array_add(argv, nullptr);

  store->transaction = g_subprocess_newv(
      reinterpret_cast<const char* const*>(argv->pdata),
      static_cast<GSubprocessFlags>(G_SUBPROCESS_FLAGS_STDOUT_PIPE |
                                    G_SUBPROCESS_FLAGS_STDERR_MERGE |
                                    G_SUBPROCESS_FLAGS_STDIN_INHERIT),
      error);
  if (store->transaction == nullptr) return false;
  store->output = g_data_input_stream_new(
      g_subprocess_get_stdout_pipe(store->transaction));
  // pamac redraws progress lines with \r; the UI keeps the last segment.
  g_data_input_stream_set_newline_type(store->output,
                                       G_DATA_STREAM_NEWLINE_TYPE_LF);
  read_line();
  g_subprocess_wait_async(store->transaction, nullptr, transaction_done,
                          nullptr);
  return true;
}

// --- Dispatch ----------------------------------------------------------------

void method_call_cb(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  PamacDatabase* db = store->db;
  gpointer ref = g_object_ref(call);

  if (strcmp(method, "config") == 0) {
    g_autoptr(FlValue) m = fl_value_new_map();
    fl_value_set_string_take(
        m, "aur", fl_value_new_bool(pamac_config_get_enable_aur(store->config)));
    respond(call, m);
  } else if (strcmp(method, "search") == 0) {
    pamac_database_search_pkgs_async(db, string_arg(args, "query"),
                                     list_done<pamac_database_search_pkgs_finish>,
                                     ref);
    return;
  } else if (strcmp(method, "searchAur") == 0) {
    pamac_database_search_aur_pkgs_async(
        db, string_arg(args, "query"),
        list_done<pamac_database_search_aur_pkgs_finish>, ref);
    return;
  } else if (strcmp(method, "category") == 0) {
    pamac_database_get_category_pkgs_async(
        db, string_arg(args, "name"),
        list_done<pamac_database_get_category_pkgs_finish>, ref);
    return;
  } else if (strcmp(method, "installed") == 0) {
    pamac_database_get_explicitly_installed_pkgs_async(
        db, list_done<pamac_database_get_explicitly_installed_pkgs_finish>,
        ref);
    return;
  } else if (strcmp(method, "updates") == 0) {
    pamac_database_get_updates_async(db, updates_done, ref);
    return;
  } else if (strcmp(method, "details") == 0) {
    const char* name = string_arg(args, "name");
    if (int_arg(args, "aur", 0)) {
      pamac_database_get_aur_pkg_async(db, name, aur_details_done, ref);
      return;
    }
    PamacAlpmPackage* pkg = pamac_database_get_pkg(db, name);
    g_autoptr(FlValue) v =
        pkg ? package_to_value(PAMAC_PACKAGE(pkg), true) : fl_value_new_null();
    if (pkg) g_object_unref(pkg);
    respond(call, v);
  } else if (strcmp(method, "icon") == 0) {
    g_autoptr(FlValue) png =
        icon_png(string_arg(args, "name"), int_arg(args, "size", 48));
    respond(call, png);
  } else if (strcmp(method, "run") == 0) {
    g_autoptr(GError) error = nullptr;
    if (store->transaction != nullptr) {
      respond_error(call, "busy", "another transaction is running");
    } else if (start_transaction(args, &error)) {
      respond(call, nullptr);
    } else {
      respond_error(call, "run", error->message);
    }
  } else if (strcmp(method, "launch") == 0) {
    g_autoptr(GDesktopAppInfo) info =
        g_desktop_app_info_new(string_arg(args, "id"));
    g_autoptr(GError) error = nullptr;
    if (info && g_app_info_launch(G_APP_INFO(info), nullptr, nullptr, &error)) {
      respond(call, nullptr);
    } else {
      respond_error(call, "launch", error ? error->message : "no such app");
    }
  } else {
    g_autoptr(FlMethodResponse) r =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, r, nullptr);
  }
  g_object_unref(ref);
}

}  // namespace

void pamac_channel_register(FlBinaryMessenger* messenger, GtkWindow* window) {
  store = g_new0(Store, 1);
  store->window = window;
  store->config = pamac_config_new("/etc/pamac.conf");
  store->db = pamac_database_new(store->config);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  store->channel = fl_method_channel_new(messenger, "forge/store",
                                         FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(store->channel, method_call_cb,
                                            nullptr, nullptr);
}
