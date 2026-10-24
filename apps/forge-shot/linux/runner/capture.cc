// Screenshots through KWin's ScreenShot2 D-Bus interface, the one Spectacle
// uses. KWin only answers apps whose desktop file lists the interface in
// X-KDE-DBUS-Restricted-Interfaces, with an Exec that is this binary
// (data/org.forgeos.shot.desktop).
//
// KWin writes the pixels into a pipe we hand it and replies with their
// layout (width, height, stride, QImage format). The pipe is read on a
// thread while the call runs, so neither side waits on a full pipe.
#include "capture.h"

#include <fcntl.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>

namespace {

struct ReadJob {
  int fd;
  GByteArray* data;
};

gpointer read_all(gpointer user_data) {
  auto* job = static_cast<ReadJob*>(user_data);
  guint8 buffer[1 << 16];
  ssize_t n;
  while ((n = read(job->fd, buffer, sizeof buffer)) > 0 ||
         (n < 0 && errno == EINTR)) {
    if (n > 0) g_byte_array_append(job->data, buffer, n);
  }
  close(job->fd);
  return nullptr;
}

guint32 lookup_uint(GVariant* dict, const char* key) {
  guint32 value = 0;
  g_variant_lookup(dict, key, "u", &value);
  return value;
}

// QImage formats KWin uses: 4 RGB32, 5 ARGB32, 6 ARGB32 premultiplied (bytes
// B G R A on little-endian), 16 RGBX8888, 17 RGBA8888, 18 RGBA8888
// premultiplied (bytes R G B A).
GdkPixbuf* to_pixbuf(const guint8* data, guint32 width, guint32 height,
                     guint32 stride, guint32 format, GError** error) {
  const bool bgra = format == 4 || format == 5 || format == 6;
  const bool rgba = format == 16 || format == 17 || format == 18;
  if (!bgra && !rgba) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                "unsupported image format %u", format);
    return nullptr;
  }
  const bool premultiplied = format == 6 || format == 18;
  const bool opaque = format == 4 || format == 16;
  GdkPixbuf* pixbuf =
      gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, width, height);
  guint8* out = gdk_pixbuf_get_pixels(pixbuf);
  const int out_stride = gdk_pixbuf_get_rowstride(pixbuf);
  for (guint32 y = 0; y < height; y++) {
    const guint8* src = data + static_cast<gsize>(y) * stride;
    guint8* dst = out + static_cast<gsize>(y) * out_stride;
    for (guint32 x = 0; x < width; x++, src += 4, dst += 4) {
      guint8 r = bgra ? src[2] : src[0];
      guint8 g = src[1];
      guint8 b = bgra ? src[0] : src[2];
      guint8 a = opaque ? 255 : src[3];
      if (premultiplied && a > 0 && a < 255) {
        r = MIN(255, r * 255 / a);
        g = MIN(255, g * 255 / a);
        b = MIN(255, b * 255 / a);
      }
      dst[0] = r;
      dst[1] = g;
      dst[2] = b;
      dst[3] = a;
    }
  }
  return pixbuf;
}

}  // namespace

gboolean forge_capture(const char* mode, const char* png_path,
                       GError** error) {
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, error);
  if (bus == nullptr) return FALSE;

  int fds[2];
  if (pipe2(fds, O_CLOEXEC) != 0) {
    g_set_error(error, G_IO_ERROR, g_io_error_from_errno(errno),
                "pipe: %s", g_strerror(errno));
    return FALSE;
  }
  // The list owns the write end from here; dropping it closes our copy.
  GUnixFDList* fd_list = g_unix_fd_list_new_from_array(&fds[1], 1);

  ReadJob job{fds[0], g_byte_array_new()};
  GThread* reader = g_thread_new("forge-shot-read", read_all, &job);

  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&options, "{sv}", "native-resolution",
                        g_variant_new_boolean(TRUE));
  g_variant_builder_add(&options, "{sv}", "include-cursor",
                        g_variant_new_boolean(FALSE));
  g_variant_builder_add(&options, "{sv}", "include-decoration",
                        g_variant_new_boolean(TRUE));
  g_variant_builder_add(&options, "{sv}", "include-shadow",
                        g_variant_new_boolean(FALSE));

  const char* method;
  GVariant* params;
  if (g_strcmp0(mode, "workspace") == 0) {
    method = "CaptureWorkspace";
    params = g_variant_new("(a{sv}h)", &options, 0);
  } else if (g_strcmp0(mode, "window") == 0) {
    method = "CaptureInteractive";  // kind 0: a window, picked by clicking
    params = g_variant_new("(ua{sv}h)", 0u, &options, 0);
  } else if (g_strcmp0(mode, "active-window") == 0) {
    method = "CaptureActiveWindow";
    params = g_variant_new("(a{sv}h)", &options, 0);
  } else {
    method = "CaptureActiveScreen";
    params = g_variant_new("(a{sv}h)", &options, 0);
  }

  // Picking a window waits for a click, so give it time.
  g_autoptr(GVariant) reply = g_dbus_connection_call_with_unix_fd_list_sync(
      bus, "org.kde.KWin", "/org/kde/KWin/ScreenShot2",
      "org.kde.KWin.ScreenShot2", method, params, G_VARIANT_TYPE("(a{sv})"),
      G_DBUS_CALL_FLAGS_NONE, 120000, fd_list, nullptr, nullptr, error);
  g_object_unref(fd_list);  // our write end closes: the reader sees EOF
  g_thread_join(reader);
  g_autoptr(GByteArray) data = job.data;
  if (reply == nullptr) return FALSE;

  g_autoptr(GVariant) info = g_variant_get_child_value(reply, 0);
  const guint32 width = lookup_uint(info, "width");
  const guint32 height = lookup_uint(info, "height");
  const guint32 stride = lookup_uint(info, "stride");
  const guint32 format = lookup_uint(info, "format");
  if (width == 0 || height == 0 ||
      data->len < static_cast<gsize>(stride) * height) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "KWin sent %u bytes for a %ux%u image", data->len, width,
                height);
    return FALSE;
  }

  g_autoptr(GdkPixbuf) pixbuf =
      to_pixbuf(data->data, width, height, stride, format, error);
  if (pixbuf == nullptr) return FALSE;
  return gdk_pixbuf_save(pixbuf, png_path, "png", error, "compression", "1",
                         nullptr);
}
