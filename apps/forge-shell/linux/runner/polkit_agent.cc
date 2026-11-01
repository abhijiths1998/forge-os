#include "polkit_agent.h"

#define POLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE
#include <polkitagent/polkitagent.h>

#include <pwd.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <map>
#include <string>

namespace {

FlMethodChannel* g_channel = nullptr;
int g_next_id = 1;

// One authentication polkit asked for, until it succeeds or is cancelled.
struct Request {
  int id;
  GTask* task;
  gchar* cookie;
  GList* identities;  // PolkitIdentity, owned
  PolkitAgentSession* session;
  gchar* password;  // held only until PAM asks for it
  GCancellable* cancellable;
  gulong cancel_id;
};

std::map<int, Request*>& requests() {
  static std::map<int, Request*> map;
  return map;
}

void send(const char* method, FlValue* args) {
  if (g_channel == nullptr) {
    fl_value_unref(args);
    return;
  }
  fl_method_channel_invoke_method(g_channel, method, args, nullptr, nullptr,
                                  nullptr);
  fl_value_unref(args);
}

FlValue* id_map(int id) {
  FlValue* m = fl_value_new_map();
  fl_value_set_string_take(m, "id", fl_value_new_int(id));
  return m;
}

void wipe_password(Request* r) {
  if (r->password != nullptr) {
    memset(r->password, 0, strlen(r->password));
    g_clear_pointer(&r->password, g_free);
  }
}

void drop_session(Request* r) {
  if (r->session == nullptr) return;
  g_signal_handlers_disconnect_by_data(r->session, r);
  polkit_agent_session_cancel(r->session);
  // Not unreffed from inside its own signal handler.
  g_idle_add(
      [](gpointer s) -> gboolean {
        g_object_unref(s);
        return G_SOURCE_REMOVE;
      },
      r->session);
  r->session = nullptr;
}

// Finishes the request: polkit hears `ok` (or that it was cancelled).
void finish(Request* r, gboolean ok) {
  requests().erase(r->id);
  drop_session(r);
  wipe_password(r);
  if (r->cancellable != nullptr && r->cancel_id != 0) {
    g_cancellable_disconnect(r->cancellable, r->cancel_id);
  }
  if (ok) {
    g_task_return_boolean(r->task, TRUE);
  } else {
    g_task_return_new_error(r->task, POLKIT_ERROR, POLKIT_ERROR_CANCELLED,
                            "Authentication was cancelled");
  }
  g_object_unref(r->task);
  g_clear_object(&r->cancellable);
  g_list_free_full(r->identities, g_object_unref);
  g_free(r->cookie);
  delete r;
}

std::string user_name(PolkitIdentity* identity) {
  if (!POLKIT_IS_UNIX_USER(identity)) return "";
  const gint uid = polkit_unix_user_get_uid(POLKIT_UNIX_USER(identity));
  struct passwd* pw = getpwuid(uid);
  return pw != nullptr ? pw->pw_name : std::to_string(uid);
}

// --- The PAM conversation ---------------------------------------------------

void on_request(PolkitAgentSession* session, const gchar* /*prompt*/,
                gboolean /*echo_on*/, gpointer data) {
  auto* r = static_cast<Request*>(data);
  // One password per attempt: asked again, PAM gets an empty answer and
  // the attempt fails, and the dialog asks the person again.
  polkit_agent_session_response(session, r->password ? r->password : "");
  wipe_password(r);
}

void on_message(Request* r, const gchar* text, gboolean error) {
  FlValue* m = id_map(r->id);
  fl_value_set_string_take(m, "text", fl_value_new_string(text ? text : ""));
  fl_value_set_string_take(m, "error", fl_value_new_bool(error));
  send("authInfo", m);
}

void on_show_error(PolkitAgentSession*, const gchar* text, gpointer data) {
  on_message(static_cast<Request*>(data), text, TRUE);
}

void on_show_info(PolkitAgentSession*, const gchar* text, gpointer data) {
  on_message(static_cast<Request*>(data), text, FALSE);
}

void on_completed(PolkitAgentSession*, gboolean gained, gpointer data) {
  auto* r = static_cast<Request*>(data);
  FlValue* m = id_map(r->id);
  fl_value_set_string_take(m, "ok", fl_value_new_bool(gained));
  send("authDone", m);
  if (gained) {
    finish(r, TRUE);
  } else {
    drop_session(r);  // the dialog stays up for another try
    wipe_password(r);
  }
}

void on_cancelled(GCancellable*, gpointer data) {
  auto* r = static_cast<Request*>(data);
  // Runs inside g_cancellable_cancel; finish from the main loop instead.
  const int id = r->id;
  g_idle_add(
      [](gpointer p) -> gboolean {
        const int id = GPOINTER_TO_INT(p);
        auto it = requests().find(id);
        if (it == requests().end()) return G_SOURCE_REMOVE;
        send("authClose", id_map(id));
        finish(it->second, FALSE);
        return G_SOURCE_REMOVE;
      },
      GINT_TO_POINTER(id));
}

}  // namespace

// --- The listener -------------------------------------------------------------

G_DECLARE_FINAL_TYPE(ForgeAgent, forge_agent, FORGE, AGENT,
                     PolkitAgentListener)

struct _ForgeAgent {
  PolkitAgentListener parent_instance;
};

G_DEFINE_TYPE(ForgeAgent, forge_agent, POLKIT_AGENT_TYPE_LISTENER)

static void initiate_authentication(PolkitAgentListener* listener,
                                    const gchar* action_id,
                                    const gchar* message,
                                    const gchar* icon_name,
                                    PolkitDetails* details,
                                    const gchar* cookie, GList* identities,
                                    GCancellable* cancellable,
                                    GAsyncReadyCallback callback,
                                    gpointer user_data) {
  auto* r = new Request{};
  r->id = g_next_id++;
  r->task = g_task_new(listener, nullptr, callback, user_data);
  r->cookie = g_strdup(cookie);
  r->identities = g_list_copy_deep(
      identities, [](gconstpointer i, gpointer) -> gpointer {
        return g_object_ref(G_OBJECT(i));
      }, nullptr);
  if (cancellable != nullptr) {
    r->cancellable = G_CANCELLABLE(g_object_ref(cancellable));
    r->cancel_id = g_cancellable_connect(
        cancellable, G_CALLBACK(on_cancelled), r, nullptr);
  }
  requests()[r->id] = r;

  // Who may answer: the person at the machine first, if they're one of them.
  FlValue* users = fl_value_new_list();
  const std::string me = g_get_user_name();
  bool have_me = false;
  for (GList* l = identities; l != nullptr; l = l->next) {
    if (user_name(POLKIT_IDENTITY(l->data)) == me) have_me = true;
  }
  if (have_me) fl_value_append_take(users, fl_value_new_string(me.c_str()));
  for (GList* l = identities; l != nullptr; l = l->next) {
    const std::string name = user_name(POLKIT_IDENTITY(l->data));
    if (!name.empty() && name != me) {
      fl_value_append_take(users, fl_value_new_string(name.c_str()));
    }
  }

  FlValue* m = id_map(r->id);
  auto set = [m](const char* key, const char* value) {
    fl_value_set_string_take(m, key, fl_value_new_string(value ? value : ""));
  };
  set("message", message);
  set("action", action_id);
  set("icon", icon_name);
  set("program", details ? polkit_details_lookup(details, "polkit.command_line")
                         : nullptr);
  fl_value_set_string_take(m, "users", users);
  send("authBegin", m);
}

static gboolean initiate_authentication_finish(PolkitAgentListener*,
                                               GAsyncResult* res,
                                               GError** error) {
  return g_task_propagate_boolean(G_TASK(res), error);
}

static void forge_agent_class_init(ForgeAgentClass* klass) {
  auto* listener = POLKIT_AGENT_LISTENER_CLASS(klass);
  listener->initiate_authentication = initiate_authentication;
  listener->initiate_authentication_finish = initiate_authentication_finish;
}

static void forge_agent_init(ForgeAgent*) {}

// --- Registration and the channel ----------------------------------------------

gboolean forge_polkit_register(FlMethodChannel* channel, GError** error) {
  g_channel = channel;
  g_autoptr(PolkitSubject) subject = nullptr;
  const char* test_pid = getenv("FORGE_POLKIT_PROCESS");
  if (test_pid != nullptr && *test_pid) {
    subject = polkit_unix_process_new_for_owner(atoi(test_pid), 0, getuid());
  } else {
    subject = polkit_unix_session_new_for_process_sync(getpid(), nullptr,
                                                       error);
    if (subject == nullptr) return FALSE;
  }
  // Kept for the life of the process; polkit drops it when we exit.
  PolkitAgentListener* agent =
      POLKIT_AGENT_LISTENER(g_object_new(forge_agent_get_type(), nullptr));
  gpointer handle = polkit_agent_listener_register(
      agent, POLKIT_AGENT_REGISTER_FLAGS_NONE, subject,
      "/org/forgeos/PolicyKit1/AuthenticationAgent", nullptr, error);
  if (handle == nullptr) {
    g_object_unref(agent);
    return FALSE;
  }
  return TRUE;
}

static Request* request_arg(FlValue* args) {
  FlValue* v = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                   ? fl_value_lookup_string(args, "id")
                   : nullptr;
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_INT) return nullptr;
  auto it = requests().find(static_cast<int>(fl_value_get_int(v)));
  return it == requests().end() ? nullptr : it->second;
}

static const char* string_of(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(v)
             : "";
}

gboolean forge_polkit_method(const gchar* method, FlValue* args) {
  if (strcmp(method, "authCancel") == 0) {
    if (Request* r = request_arg(args)) finish(r, FALSE);
    return TRUE;
  }
  if (strcmp(method, "authRespond") != 0) return FALSE;
  Request* r = request_arg(args);
  if (r == nullptr) return TRUE;

  const std::string user = string_of(args, "user");
  PolkitIdentity* identity = nullptr;
  for (GList* l = r->identities; l != nullptr; l = l->next) {
    if (user_name(POLKIT_IDENTITY(l->data)) == user) {
      identity = POLKIT_IDENTITY(l->data);
    }
  }
  if (identity == nullptr && r->identities != nullptr) {
    identity = POLKIT_IDENTITY(r->identities->data);
  }
  if (identity == nullptr) {
    finish(r, FALSE);
    return TRUE;
  }

  drop_session(r);
  wipe_password(r);
  r->password = g_strdup(string_of(args, "password"));
  r->session = polkit_agent_session_new(identity, r->cookie);
  g_signal_connect(r->session, "request", G_CALLBACK(on_request), r);
  g_signal_connect(r->session, "show-error", G_CALLBACK(on_show_error), r);
  g_signal_connect(r->session, "show-info", G_CALLBACK(on_show_info), r);
  g_signal_connect(r->session, "completed", G_CALLBACK(on_completed), r);
  polkit_agent_session_initiate(r->session);
  return TRUE;
}
