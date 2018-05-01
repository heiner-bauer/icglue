/*
 *  ICGlue is a Tcl-Library for scripted HDL generation
 *  Copyright (C) 2017-2018  Andreas Dixius, Felix Neumärker
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

#include "ig_data.h"
#include "logger.h"
#include <stdio.h>

static        struct ig_attribute *ig_attribtue_new (const char *value, bool constant);
static inline void                 ig_attribute_free (struct ig_attribute *attr);
static        void                 ig_attribute_free_gpointer (gpointer attr);
static const  char                *ig_obj_type_name (enum ig_object_type type);
static const  char                *ig_port_dir_name (enum ig_port_dir dir);

/*******************************************************
 * object data
 *******************************************************/

static struct ig_attribute * ig_attribtue_new (const char *value, bool constant)
{
    struct ig_attribute *result = g_slice_new (struct ig_attribute);

    result->constant = constant;
    result->value    = value;

    return result;
}

static inline void ig_attribute_free (struct ig_attribute *attr)
{
    g_slice_free (struct ig_attribute, attr);
}

static void ig_attribute_free_gpointer (gpointer attr)
{
    ig_attribute_free ((struct ig_attribute *) attr);
}

static const char *ig_obj_type_name (enum ig_object_type type)
{
    switch (type) {
        case IG_OBJ_PORT:          return "port";
        case IG_OBJ_PIN:           return "pin";
        case IG_OBJ_PARAMETER:     return "parameter";
        case IG_OBJ_ADJUSTMENT:    return "adjustment";
        case IG_OBJ_DECLARATION:   return "declaration";
        case IG_OBJ_CODESECTION:   return "codesection";
        case IG_OBJ_MODULE:        return "module";
        case IG_OBJ_INSTANCE:      return "instance";
        case IG_OBJ_REGFILE_REG:   return "register";
        case IG_OBJ_REGFILE_ENTRY: return "regfile-entry";
        case IG_OBJ_REGFILE:       return "regfile";
    };

    return "UNKNOWN";
}

struct ig_object *ig_obj_new (enum ig_object_type type, const char *name, struct ig_object *parent, gpointer obj, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (obj  == NULL) return NULL;

    log_debug ("DONew", "Creating object of type %s, name %s, parent %s", ig_obj_type_name (type), name, (parent != NULL ? parent->id : "<none>"));
    struct ig_object *result = g_slice_new (struct ig_object);

    result->type = type;
    result->obj  = obj;

    if (storage == NULL) {
        result->string_storage      = g_string_chunk_new (256);
        result->string_storage_free = true;
    } else {
        result->string_storage      = storage;
        result->string_storage_free = false;
    }

    result->attributes = g_hash_table_new_full (g_str_hash, g_str_equal, NULL, ig_attribute_free_gpointer);

    /* id */
    GString *s_id = g_string_new (NULL);
    s_id = g_string_append (s_id, ig_obj_type_name (type));
    s_id = g_string_append (s_id, "::");
    if (parent != NULL) {
        s_id = g_string_append (s_id, ig_obj_attr_get (parent, "name"));
        s_id = g_string_append (s_id, ".");
    }
    s_id = g_string_append (s_id, name);


    ig_obj_attr_set (result, "type", ig_obj_type_name (type), true);
    ig_obj_attr_set (result, "id",   s_id->str,               true);
    ig_obj_attr_set (result, "name", name,                    true);
    if (parent != NULL) {
        ig_obj_attr_set (result, "parent", parent->id, true);
    }

    g_string_free (s_id, true);

    result->id = ig_obj_attr_get (result, "id");

    return result;
}

void ig_obj_free (struct ig_object *obj)
{
    if (obj == NULL) return;

    g_hash_table_destroy (obj->attributes);

    if (obj->string_storage_free) {
        g_string_chunk_free (obj->string_storage);
    }

    g_slice_free (struct ig_object, obj);
}

bool ig_obj_attr_set (struct ig_object *obj, const char *name, const char *value, bool constant)
{
    if (obj == NULL) return false;
    if (name == NULL) return false;
    if (value == NULL) return false;

    struct ig_attribute *old_val = (struct ig_attribute *) g_hash_table_lookup (obj->attributes, name);

    if ((old_val != NULL) && (old_val->constant)) return false;

    char *local_name                 = g_string_chunk_insert_const (obj->string_storage, name);
    char *local_value_string         = g_string_chunk_insert_const (obj->string_storage, value);
    struct ig_attribute *value_entry = ig_attribtue_new (local_value_string, constant);

    g_hash_table_insert (obj->attributes, local_name, value_entry);

    return true;
}

const char *ig_obj_attr_get (struct ig_object *obj, const char *name)
{
    if (obj == NULL) return NULL;
    if (name == NULL) return NULL;

    struct ig_attribute *value = (struct ig_attribute *) g_hash_table_lookup (obj->attributes, name);

    if (value == NULL) return NULL;
    return value->value;
}

static const char *ig_port_dir_name (enum ig_port_dir dir)
{
    switch (dir) {
        case IG_PD_IN:    return "input";
        case IG_PD_OUT:   return "output";
        case IG_PD_BIDIR: return "bidirectional";
    };

    return "UNKNOWN";
}


/*******************************************************
 * port data
 *******************************************************/

struct ig_port *ig_port_new (const char *name, enum ig_port_dir dir, struct ig_module *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (parent == NULL) return NULL;

    struct ig_port  *port = g_slice_new (struct ig_port);
    struct ig_object *obj = ig_obj_new (IG_OBJ_PORT, name, parent->object, port, storage);
    port->object = obj;

    ig_obj_attr_set (port->object, "direction", ig_port_dir_name (dir), true);

    port->name   = ig_obj_attr_get (port->object, "name");
    port->dir    = dir;
    port->parent = parent;

    g_queue_push_tail (parent->ports, port);

    return port;
}

void ig_port_free (struct ig_port *port)
{
    if (port == NULL) return;

    ig_obj_free (port->object);
    g_slice_free (struct ig_port, port);
}

/*******************************************************
 * parameter data
 *******************************************************/

struct ig_param *ig_param_new (const char *name, const char *value, bool local, struct ig_module *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (parent == NULL) return NULL;
    if (value == NULL) return NULL;

    struct ig_param  *param = g_slice_new (struct ig_param);
    struct ig_object *obj = ig_obj_new (IG_OBJ_PARAMETER, name, parent->object, param, storage);
    param->object = obj;

    ig_obj_attr_set (param->object, "value",  value, true);
    ig_obj_attr_set (param->object, "local",  (local ? "true" : "false"), true);

    param->name   = ig_obj_attr_get (param->object, "name");
    param->value  = ig_obj_attr_get (param->object, "value");
    param->local  = local;
    param->parent = parent;

    g_queue_push_tail (parent->params, param);

    return param;
}

void ig_param_free (struct ig_param *param)
{
    if (param == NULL) return;

    ig_obj_free (param->object);
    g_slice_free (struct ig_param, param);
}


/*******************************************************
 * declaration data
 *******************************************************/

struct ig_decl *ig_decl_new (const char *name, const char *assign, bool default_type, struct ig_module *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (parent == NULL) return NULL;

    struct ig_decl  *decl = g_slice_new (struct ig_decl);
    struct ig_object *obj = ig_obj_new (IG_OBJ_DECLARATION, name, parent->object, decl, storage);
    decl->object = obj;

    ig_obj_attr_set (decl->object, "default_type", (default_type ? "true" : "false"), true);
    if (assign != NULL) ig_obj_attr_set (decl->object, "assign", assign, true);

    decl->name               = ig_obj_attr_get (decl->object, "name");
    decl->default_assignment = ig_obj_attr_get (decl->object, "assign");
    decl->default_type       = default_type;
    decl->parent             = parent;

    g_queue_push_tail (parent->decls, decl);

    return decl;
}

void ig_decl_free (struct ig_decl *decl)
{
    if (decl == NULL) return;

    ig_obj_free (decl->object);
    g_slice_free (struct ig_decl, decl);
}

/*******************************************************
 * codesection data
 *******************************************************/

struct ig_code *ig_code_new (const char *name, const char *codesection, struct ig_module *parent, GStringChunk *storage)
{
    if (codesection == NULL) return NULL;
    if (parent == NULL) return NULL;
    if (parent->resource) {
        log_error ("DCsNw", "Cannot add codesection to resource module");
        return NULL;
    }

    GString *s_name = g_string_new (NULL);
    if (name == NULL) {
        g_string_printf (s_name, "_cs_%d", g_queue_get_length(parent->code));
    } else {
        s_name = g_string_append (s_name, name);
    }

    struct ig_code  *code = g_slice_new (struct ig_code);
    struct ig_object *obj = ig_obj_new (IG_OBJ_CODESECTION, s_name->str, parent->object, code, storage);
    code->object = obj;

    ig_obj_attr_set (code->object, "code",   codesection,        true);

    code->name               = ig_obj_attr_get (code->object, "name");
    code->code               = ig_obj_attr_get (code->object, "code");
    code->parent             = parent;

    g_string_free (s_name, true);

    g_queue_push_tail (parent->code, code);

    return code;
}

void ig_code_free (struct ig_code *code)
{
    if (code == NULL) return;

    ig_obj_free (code->object);
    g_slice_free (struct ig_code, code);
}

/*******************************************************
 * regfile data
 *******************************************************/

struct ig_rf_reg *ig_rf_reg_new (const char *name, struct ig_rf_entry *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (parent == NULL) return NULL;

    struct ig_rf_reg *reg = g_slice_new (struct ig_rf_reg);
    struct ig_object *obj = ig_obj_new (IG_OBJ_REGFILE_REG, name, parent->object, reg, storage);
    reg->object = obj;

    reg->name   = ig_obj_attr_get (reg->object, "name");
    reg->parent = parent;

    g_queue_push_tail (parent->regs, reg);

    return reg;
}

void ig_rf_reg_free (struct ig_rf_reg *reg)
{
    if (reg == NULL) return;

    ig_obj_free (reg->object);
    g_slice_free (struct ig_rf_reg, reg);
}

struct ig_rf_entry *ig_rf_entry_new (const char *name, struct ig_rf_regfile *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (parent == NULL) return NULL;

    struct ig_rf_entry *entry = g_slice_new (struct ig_rf_entry);
    struct ig_object *obj = ig_obj_new (IG_OBJ_REGFILE_ENTRY, name, parent->object, entry, storage);
    entry->object = obj;

    entry->name   = ig_obj_attr_get (entry->object, "name");
    entry->parent = parent;

    g_queue_push_tail (parent->entries, entry);

    return entry;
}

void ig_rf_entry_free (struct ig_rf_entry *entry)
{
    if (entry == NULL) return;

    ig_obj_free (entry->object);

    if (entry->regs != NULL) g_queue_free (entry->regs);

    g_slice_free (struct ig_rf_entry, entry);
}

struct ig_rf_regfile *ig_rf_regfile_new (const char *name, struct ig_module *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (parent == NULL) return NULL;
    if (parent->resource) {
        log_error ("DRfNw", "Cannot add regfile to resource module");
        return NULL;
    }

    struct ig_rf_regfile *regfile = g_slice_new (struct ig_rf_regfile);
    struct ig_object *obj = ig_obj_new (IG_OBJ_REGFILE, name, NULL, regfile, storage);
    regfile->object = obj;

    regfile->name   = ig_obj_attr_get (regfile->object, "name");
    regfile->parent = parent;

    g_queue_push_tail (parent->regfiles, regfile);

    return regfile;
}

void ig_rf_regfile_free (struct ig_rf_regfile *regfile)
{
    if (regfile == NULL) return;

    ig_obj_free (regfile->object);

    if (regfile->entries != NULL) g_queue_free (regfile->entries);

    g_slice_free (struct ig_rf_regfile, regfile);
}

/*******************************************************
 * module data
 *******************************************************/

struct ig_module *ig_module_new (const char *name, bool ilm, bool resource, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    log_debug ("DMNew", "Generating module %s", name);

    struct ig_module *module = g_slice_new (struct ig_module);
    struct ig_object *obj    = ig_obj_new (IG_OBJ_MODULE, name, NULL, module, storage);
    module->object = obj;

    ig_obj_attr_set (module->object, "ilm",      (ilm      ? "true" : "false"), true);
    ig_obj_attr_set (module->object, "resource", (resource ? "true" : "false"), true);

    module->name     = ig_obj_attr_get (module->object, "name");
    module->ilm      = ilm;
    module->resource = resource;

    module->params        = g_queue_new ();
    module->ports         = g_queue_new ();
    module->mod_instances = g_queue_new ();

    if (resource) {
        module->decls            = NULL;
        module->code             = NULL;
        module->child_instances  = NULL;
        module->regfiles         = NULL;
        module->default_instance = NULL;
    } else {
        module->decls            = g_queue_new ();
        module->code             = g_queue_new ();
        module->child_instances  = g_queue_new ();
        module->regfiles         = g_queue_new ();
        module->default_instance = ig_instance_new (name, module, NULL, storage);
    }

    return module;
}

void ig_module_free (struct ig_module *module)
{
    if (module == NULL) return;

    ig_obj_free (module->object);

    if (module->params          != NULL) g_queue_free (module->params);
    if (module->ports           != NULL) g_queue_free (module->ports);
    if (module->mod_instances   != NULL) g_queue_free (module->mod_instances);
    if (module->decls           != NULL) g_queue_free (module->decls);
    if (module->code            != NULL) g_queue_free (module->code);
    if (module->child_instances != NULL) g_queue_free (module->child_instances);
    if (module->regfiles        != NULL) g_queue_free (module->regfiles);

    g_slice_free (struct ig_module, module);
}


/*******************************************************
 * pin data
 *******************************************************/

struct ig_pin *ig_pin_new (const char *name, const char *connection, struct ig_instance *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (connection == NULL) return NULL;
    if (parent == NULL) return NULL;

    struct ig_pin  *pin = g_slice_new (struct ig_pin);
    struct ig_object *obj = ig_obj_new (IG_OBJ_PIN, name, parent->object, pin, storage);
    pin->object = obj;

    ig_obj_attr_set (pin->object, "connection", connection, true);

    pin->name       = ig_obj_attr_get (pin->object, "name");
    pin->connection = ig_obj_attr_get (pin->object, "connection");
    pin->parent     = parent;

    g_queue_push_tail (parent->pins, pin);

    return pin;
}

void ig_pin_free (struct ig_pin *pin)
{
    if (pin == NULL) return;

    ig_obj_free (pin->object);
    g_slice_free (struct ig_pin, pin);
}


/*******************************************************
 * adjustment data
 *******************************************************/

struct ig_adjustment *ig_adjustment_new (const char *name, const char *value, struct ig_instance *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (parent == NULL) return NULL;
    if (value == NULL) return NULL;

    struct ig_adjustment  *adjustment = g_slice_new (struct ig_adjustment);
    struct ig_object *obj = ig_obj_new (IG_OBJ_ADJUSTMENT, name, parent->object, adjustment, storage);
    adjustment->object = obj;

    ig_obj_attr_set (adjustment->object, "value",  value, true);

    adjustment->name   = ig_obj_attr_get (adjustment->object, "name");
    adjustment->value  = ig_obj_attr_get (adjustment->object, "value");
    adjustment->parent = parent;

    g_queue_push_tail (parent->adjustments, adjustment);

    return adjustment;
}

void ig_adjustment_free (struct ig_adjustment *adjustment)
{
    if (adjustment == NULL) return;

    ig_obj_free (adjustment->object);
    g_slice_free (struct ig_adjustment, adjustment);
}


/*******************************************************
 * instance data
 *******************************************************/

struct ig_instance *ig_instance_new (const char *name, struct ig_module *module, struct ig_module *parent, GStringChunk *storage)
{
    if (name == NULL) return NULL;
    if (module == NULL) return NULL;
    log_debug ("DINew", "Generating instance %s", name);

    struct ig_instance *instance = g_slice_new (struct ig_instance);
    struct ig_object   *obj      = ig_obj_new (IG_OBJ_INSTANCE, name, (parent == NULL ? NULL : parent->object), instance, storage);
    instance->object = obj;

    ig_obj_attr_set (instance->object, "module", module->object->id, true);
    if (parent != NULL) {
        g_queue_push_tail (parent->child_instances, instance);
    }
    g_queue_push_tail (module->mod_instances, instance);

    instance->name   = ig_obj_attr_get (instance->object, "name");
    instance->module = module;
    instance->parent = parent;

    instance->adjustments = g_queue_new ();
    instance->pins        = g_queue_new ();

    return instance;
}

void ig_instance_free (struct ig_instance *instance)
{
    if (instance == NULL) return;

    ig_obj_free (instance->object);

    if (instance->adjustments != NULL) g_queue_free (instance->adjustments);
    if (instance->pins        != NULL) g_queue_free (instance->pins);

    g_slice_free (struct ig_instance, instance);
}


