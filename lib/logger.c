

#include "logger.h"

#include <glib/gprintf.h>
#include "color.h"

gboolean log_linenumbers = FALSE;
static log_level_t default_log_level = LOGLEVEL_DEBUG;
static GHashTable *log_property = NULL;

gchar*  loglevel_label[LOGLEVEL_COUNT] = {
    "D",
    "I",
    "W",
    "E",
    "INTERNAL ERROR",
};

void set_default_log_level(log_level_t log_level)
{
    default_log_level = log_level;
}

void log_particular_level (const gchar *id, const log_level_t level)
{
    static GStringChunk *ids = NULL;

    if (log_property == NULL) {
        log_property = g_hash_table_new(g_str_hash, g_str_equal);
        ids = g_string_chunk_new (128);
    }

    if (level == LOGLEVEL_DEFAULT) {
        g_hash_table_remove (log_property, id);
    }

    gchar *id_local = g_string_chunk_insert_const(ids, id);
    g_hash_table_insert (log_property, id_local, GINT_TO_POINTER(level));
}

void log_base (const log_level_t level, const gchar *id, const gchar *sfile, gint sline, const gchar *format, ...)
{
    va_list argptr;
    va_start (argptr, format);
    log_basev (level, id, sfile, sline, format, argptr);
    va_end (argptr);
}

gboolean log_suppress (const log_level_t level, const gchar *id)
{
    gint log_level_threshold = default_log_level;

    if (log_property && g_hash_table_contains(log_property, id)) {
        log_level_threshold = GPOINTER_TO_INT (g_hash_table_lookup (log_property, id));
    }

    return (level < log_level_threshold);
}

void log_basev (const log_level_t level, const gchar *id, const gchar *sfile, gint sline, const gchar *format, va_list arg_list)
{
    if (log_suppress (level, id)) {
        return;
    }

    gchar *log_header_color;

    if (level == LOGLEVEL_DEBUG) {
        log_header_color = g_strconcat (color_bold, color_blue, NULL);
    } else if (level == LOGLEVEL_INFO) {
        log_header_color = g_strconcat (color_bold, NULL);
    } else if (level == LOGLEVEL_WARNING) {
        log_header_color = g_strconcat (color_bold, color_magenta, NULL);
    } else if (level == LOGLEVEL_ERROR) {
        log_header_color = g_strconcat (color_bold, color_red, NULL);
    } else if (level == LOGLEVEL_ERRORINT) {
        log_header_color = g_strconcat (color_bold, color_red, NULL);
    } else {
        log_header_color = g_malloc0(sizeof(gchar));
    }

    GString *log_string = g_string_new (NULL);
    GString *log_formated = g_string_new (NULL);

    g_string_vprintf (log_string, format, arg_list);
    g_string_printf (log_formated, "%s%s,%s%s    %s", log_header_color, loglevel_label[level], id, color_reset, log_string->str);
    g_string_free (log_string, TRUE);
    g_free (log_header_color);

    if (log_linenumbers) {
        g_fprintf (stderr, "%s (%s:%d)\n", log_formated->str, sfile, sline);
    } else {
        g_fprintf (stderr, "%s\n", log_formated->str);
    }
    g_string_free (log_formated, TRUE);
}

void log_dump_settings ()
{

    GHashTableIter iter;
    gpointer id_local, level;

    g_fprintf (stderr, "Default loglevel is %s\n", loglevel_label[GPOINTER_TO_INT (level)];
    g_hash_table_iter_init (&iter, log_property);
    while (g_hash_table_iter_next (&iter, &id_local, &level)) {
        g_fprintf (stderr, "LogID: %s is set to level %s\n", (gchar *)id_local ,loglevel_label[GPOINTER_TO_INT(level)]);
    }
}
