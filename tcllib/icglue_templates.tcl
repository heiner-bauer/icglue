
#
#   ICGlue is a Tcl-Library for scripted HDL generation
#   Copyright (C) 2017-2019  Andreas Dixius, Felix Neumärker
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

package provide ICGlue 3.0a1

## @brief Template related functionality
namespace eval ig::templates {
    ## @brief Collect template data
    namespace eval collection {
        variable template_dir       {}
        variable output_types_gen   {}
        variable template_path_gen  {}
        variable output_path_gen    {}
    }

    ## @brief Functions to call from/with template init script
    namespace eval init {
        ## @brief Set path to template.
        # @param template Name of template.
        # @param dir Path to template directory.
        proc template_dir  {template dir} {
            lappend ig::templates::collection::template_dir [list \
                $template $dir \
            ]
        }

        ## @brief Set template callback for obtaining output types.
        # @param template Name of template.
        # @param body Proc body of callback.
        #
        # Proc callback body should match for argument list {object}, where
        # object is the Object-ID of the Object to generate output for.
        #
        # See also @ref ig::templates::current::get_output_types.
        proc output_types {template body} {
            lappend ig::templates::collection::output_types_gen [list \
                $template $body \
            ]
        }

        ## @brief Set template callback for path to template file.
        # @param template Name of template.
        # @param body Proc body of callback.
        #
        # Proc callback body should match for argument list {object type template_dir}, where
        # object is the Object-ID of the Object to generate output for,
        # type is one of the types returned by the callback set via @ref output_types for
        # the given object and template_dir is the path to this template.
        #
        # See also @ref ig::templates::current::get_template_file_raw and
        # @ref ig::templates::current::get_template_file.
        proc template_file {template body} {
            lappend ig::templates::collection::template_path_gen [list \
                $template $body \
            ]
        }

        ## @brief Set template callback for path to output file.
        # @param template Name of template.
        # @param body Proc body of callback.
        #
        # Proc callback body should match for argument list {object type}, where
        # object is the Object-ID of the Object to generate output for and
        # type is one of the types returned by the callback set via @ref output_types for
        # the given object.
        #
        # See also @ref ig::templates::current::get_output_file.
        proc output_file {template body} {
            lappend ig::templates::collection::output_path_gen [list \
                $template $body \
            ]
        }

        namespace export *
    }

    ## @brief Callback procs of currently loaded template.
    namespace eval current {
        variable template_dir ""

        ## @brief Actual callback to get the template file.
        # @param object The Object-ID of the Object to generate output for.
        # @param type One of the types returned by @ref get_output_types for the given object.
        # @param template_dir Path to this template.
        # @return Filename of the template file.
        #
        # See also @ref ig::templates::init::template_file.
        # Should be called by @ref get_template_file.
        proc get_template_file_raw {object type template_dir} {
            ig::log -error -abort "No template loaded"
        }

        ## @brief Callback to get supported output types for given object.
        # @param object Object-ID of the Object to generate output for.
        # @return A list of supported output types needed by
        # @ref get_template_file, @ref get_template_file_raw,
        # @ref get_output_file.
        #
        # See also @ref ig::templates::init::output_types.
        proc get_output_types {object} {
            ig::log -error -abort "No template loaded"
        }

        ## @brief Callback wrapper to get the template file.
        # @param object The Object-ID of the Object to generate output for.
        # @param type One of the types returned by @ref get_output_types for the given object.
        # @return Filename of the template file.
        #
        # Calls @ref get_template_file_raw with the path to the current template.
        proc get_template_file {object type} {
            variable template_dir
            return [get_template_file_raw $object $type $template_dir]
        }

        ## @brief Callback to get path to output file.
        # @param object Object-ID of the Object to generate output for.
        # @param type One of the types returned by @ref get_output_types for the given object.
        # @return Path to the output file to generate.
        #
        # See also @ref ig::templates::init::output_file.
        proc get_output_file {object type} {
            ig::log -error -abort "No template loaded"
        }
    }

    ## @brief Preprocess helpers for template files
    namespace eval preprocess {
        ## @brief Preprocess regfile-object into array-list.
        # @param regfile_id Object-ID of regfile-object.
        # @return List of arrays (as list like obtained via array get) of regfile-entry data.
        #
        # Structure of returned array-list:
        # Main List contains arrays with entries
        # @li name = Name of regfile entry.
        # @li object = Object-ID of regfile entry.
        # @li address = Address of regfile entry.
        # @li regs = Array-list for registers in this entry.
        #
        # The regs-entry of the regfile-entry is a list of arrays with entries
        # @li name = Name of the register.
        # @li object = Object-ID of register.
        # @li bit_high = MSBit occupied inside regfile-entry.
        # @li bit_low = LSBit occupied inside regfile-entry.
        # @li width = Size of register in bits.
        # @li entrybits = Verilog-range of bits occupied inside regfile-entry.
        # @li type = Type of register, e.g. R, RW.
        # @li reset = Reset value of register.
        # @li signal = Signal this register connects to.
        # @li signalbits = Verilog-range of bits of signal to connect to.
        proc regfile_to_arraylist {regfile_id} {
            # collect all regfile entries, sort by address
            set entries [ig::db::get_regfile_entries -all -of $regfile_id]
            set entry_list {}
            set wordsize 32

            foreach i_entry $entries {
                set reg_list {}
                set regs [ig::db::get_regfile_regs -all -of $i_entry]
                set next_bit 0

                try {
                    #entry_default_map {name width entrybits type reset signal signalbits}
                    foreach i_reg $regs {
                        set name       [ig::db::get_attribute -object $i_reg -attribute "name"]
                        set width      [ig::db::get_attribute -object $i_reg -attribute "rf_width"      -default -1]
                        set entrybits  [ig::db::get_attribute -object $i_reg -attribute "rf_entrybits"  -default ""]
                        set type       [ig::db::get_attribute -object $i_reg -attribute "rf_type"       -default "RW"]
                        set reset      [ig::db::get_attribute -object $i_reg -attribute "rf_reset"      -default "-"]
                        set signal     [ig::db::get_attribute -object $i_reg -attribute "rf_signal"     -default "-"]
                        set signalbits [ig::db::get_attribute -object $i_reg -attribute "rf_signalbits" -default "-"]
                        set comment    [ig::db::get_attribute -object $i_reg -attribute "rf_comment"    -default ""]

                        if {$width < 0} {
                            if {$entrybits eq ""} {
                                set width $wordsize
                                set entrybits "[expr {$wordsize - 1}]:0"
                            } else {
                                set blist [split $entrybits ":"]
                                if {[llength $blist] == 1} {
                                    set width 1
                                } else {
                                    set width [expr {[lindex $blist 0] - [lindex $blist 1] + 1}]
                                }
                            }
                        } elseif {$entrybits eq ""} {
                            if {$width == 1} {
                                set entrybits "$next_bit"
                            } else {
                                set entrybits "[expr {$width + $next_bit - 1}]:$next_bit"
                            }
                        }

                        set blist [split $entrybits ":"]
                        set bit_high [lindex $blist 0]
                        set next_bit [expr {$bit_high+1}]
                        if {[llength $blist] == 2} {
                            set bit_low  [lindex $blist 1]
                        } else {
                            set bit_low  $bit_high
                        }

                        lappend reg_list [list \
                            $name $bit_high $bit_low $width $entrybits $type $reset $signal $signalbits $comment $i_reg \
                            ]
                    }
                    set reg_list_raw [lsort -integer -index 2 $reg_list]
                    set reg_list {}
                    set idx_start -1

                    foreach i_reg $reg_list_raw {
                        set i_bit_low [lindex $i_reg 2]
                        set i_bit_high [lindex $i_reg 1]
                        if {$i_bit_low - $idx_start > 1} {
                            set tmp_high [expr {$i_bit_low - 1}]
                            set tmp_low  [expr {$idx_start + 1}]
                            if {$tmp_high == $tmp_low} {
                                set entrybits $tmp_high
                            } else {
                                set entrybits "${tmp_high}:${tmp_low}"
                            }

                            lappend reg_list [list \
                                "name"       "-" \
                                "bit_high"   $tmp_high \
                                "bit_low"    $tmp_low \
                                "width"      [expr {$tmp_high - $tmp_low + 1}] \
                                "entrybits"  $entrybits \
                                "type"       "-" \
                                "reset"      "-" \
                                "signal"     "-" \
                                "signalbits" "-" \
                                "comment"    "" \
                                "object"     "" \
                                ]
                        }
                        lappend reg_list [list \
                            "name"       [lindex $i_reg 0] \
                            "bit_high"   [lindex $i_reg 1] \
                            "bit_low"    [lindex $i_reg 2] \
                            "width"      [lindex $i_reg 3] \
                            "entrybits"  [lindex $i_reg 4] \
                            "type"       [lindex $i_reg 5] \
                            "reset"      [lindex $i_reg 6] \
                            "signal"     [lindex $i_reg 7] \
                            "signalbits" [lindex $i_reg 8] \
                            "comment"    [lindex $i_reg 9] \
                            "object"     [lindex $i_reg 10] \
                            ]

                        set idx_start $i_bit_high
                    }
                    if {$idx_start < $wordsize - 1} {
                        set tmp_high [expr {$wordsize - 1}]
                        set tmp_low  [expr {$idx_start + 1}]
                        if {$tmp_high == $tmp_low} {
                            set entrybits $tmp_high
                        } else {
                            set entrybits "${tmp_high}:${tmp_low}"
                        }

                        lappend reg_list [list \
                            "name"       "-" \
                            "bit_high"   $tmp_high \
                            "bit_low"    $tmp_low \
                            "width"      [expr {$tmp_high - $tmp_low + 1}] \
                            "entrybits"  $entrybits \
                            "type"       "-" \
                            "reset"      "-" \
                            "signal"     "-" \
                            "signalbits" "-" \
                            "comment"    "" \
                            "object"     "" \
                            ]
                    }

                    set entry_attributes [ig::db::get_attribute -object $i_entry]
                    lappend entry_list [list                                                    \
                        "address" [ig::db::get_attribute -object $i_entry -attribute "address"] \
                        {*}[dict remove $entry_attributes "address"]                            \
                        "regs"    $reg_list                                                     \
                        "object"  $i_entry                                                      \
                        ]
                } on error {emsg eopt} {
                    ig::log -error -id RF [format "Error while processing register \"%s/%s\" in regfile \"%s\" \n -- (%s) --\n%s" \
                        [ig::db::get_attribute -object ${i_entry} -attribute "name"] ${name} \
                        [ig::db::get_attribute -object ${regfile_id} -attribute "name"] \
                        ${i_entry} \
                        [dict get $eopt {-errorinfo}]
                    ]
                }
            }
            set entry_list [lsort -integer -index 1 $entry_list]

            return $entry_list
        }

        ## @brief Preprocess instance-object into array-list.
        # @param instance_id Object-ID of instance-object.
        # @return Array as list (like obtained via array get) with instance data.
        #
        # Elements of returned array:
        # @li name = Name of instance.
        # @li object = Object-ID of instance.
        # @li module = Object-ID of module instanciated.
        # @li module.name = Name of module instanciated.
        # @li ilm = ilm property of instance.
        # @li pins = Array-List of pins of instance.
        # @li parameters = Array-List of parameters of instance.
        # @li hasparams = Boolean indicating whether instance has parameters.
        #
        # The pins entry is an array-list of arrays with entries
        # @li name = Name of pin.
        # @li object = Object-ID of pin.
        # @li connection = Connected signal/value to this pin.
        # @li invert = Pin should be inverted.
        #
        # The parameters entry is an array-list of arrays with entries
        # @li name = Name of parameter.
        # @li object = Object-ID of parameter.
        # @li value = Value assigned to parameter.
        proc instance_to_arraylist {instance_id} {
            set result {}

            set mod [ig::db::get_modules -of $instance_id]
            set ilm [ig::db::get_attribute -object $mod -attribute "ilm" -default "false"]

            lappend result "name"        [ig::db::get_attribute -object $instance_id -attribute "name"]
            lappend result "object"      $instance_id
            lappend result "module"      $mod
            lappend result "ilm"         $ilm
            lappend result "module.name" [ig::db::get_attribute -object $mod -attribute "name"]

            # pins
            set pin_data {}
            foreach i_pin [ig::db::get_pins -of $instance_id] {
                lappend pin_data [list \
                    "name"           [ig::db::get_attribute -object $i_pin -attribute "name"] \
                    "object"         $i_pin \
                    "connection"     [ig::aux::adapt_pin_connection $i_pin] \
                    "connection_raw" [ig::db::get_attribute -object $i_pin -attribute "connection"] \
                    "invert"         [ig::db::get_attribute -object $i_pin -attribute "invert" -default "false"] \
                ]
            }
            lappend result "pins" $pin_data

            # parameters
            set param_data {}
            foreach i_param [ig::db::get_adjustments -of $instance_id] {
                lappend param_data [list \
                    "name"           [ig::db::get_attribute -object $i_param -attribute "name"] \
                    "object"         $i_param \
                    "value"          [ig::db::get_attribute -object $i_param -attribute "value"] \
                ]
            }
            lappend result "parameters" $param_data

            lappend result "hasparams" [expr {(!$ilm) && ([llength $param_data] > 0)}]

            return $result
        }

        ## @brief Preprocess module-object into arra-list.
        # @param module_id Object-ID of module-object.
        # @return Array as list (like obtained via array get) with module data.
        #
        # Elements of returned array:
        # @li name = Name of module.
        # @li object = Object-ID of module.
        # @li ports = Array-List of ports of module.
        # @li parameters = Array-List of parameters of module.
        # @li declarations = Array-List of declarations of module.
        # @li code = Array-List of codesections of module.
        # @li instances = Array-List of instances of module.
        # @li regfiles = Array-List of regfiles of module.
        #
        # The ports entry is an array-list of arrays with entries
        # @li name = Name of port.
        # @li object = Object-ID of port.
        # @li size = Bitsize of port.
        # @li %vlog.bitrange = Verilog-Bitrange of port.
        # @li direction = Direction of port.
        # @li vlog.direction = Verilog port-direction.
        #
        # The parameters entry is an array-list of arrays with entries
        # @li name = Name of parameter.
        # @li object = Object-ID of parameter.
        # @li local = Boolean indicating whether this is a local parameter.
        # @li vlog.type = Verilog-Type of parameter.
        # @li value = Default value of parameter.
        #
        # The declarations entry is an array-list of arrays with entries
        # @li name = Name of declaration.
        # @li object = Object-ID of declaration.
        # @li size = Bitsize of declaration.
        # @li %vlog.bitrange = Verilog-Bitrange of declaration.
        # @li defaulttype = Boolean indicating whether declaration is of default type for declarations.
        # @li vlog.type = Verilog-Type of declarations.
        #
        # The code entry is an array-list of arrays with entries
        # @li name = Name of codesection.
        # @li object = Object-ID of codesection.
        # @li code_raw = Verbatim code of codesection.
        # @li code = Code adapted according to adapt property by @ref ig::aux::adapt_codesection.
        #
        # The instances entry is an array-list of arrays with entries as returned by
        # @ref instance_to_arraylist
        #
        # The regfiles entry is an array-list of arrays with entries
        # @li name = Name of regfile.
        # @li object = Object-ID of regfile.
        # @li entries = Entries of regfile as array-list as returned by @ref regfile_to_arraylist.
        proc module_to_arraylist {module_id} {
            set result {}

            lappend result "name"   [ig::db::get_attribute -object $module_id -attribute "name"]
            lappend result "object" $module_id

            # ports
            set port_data {}
            foreach i_port [ig::db::get_ports -of $module_id] {
                set dimension_bitrange {}
                foreach dimension [ig::db::get_attribute -object $i_port -attribute "dimension" -default {}] {
                    append dimension_bitrange [ig::vlog::bitrange $dimension]
                }
                lappend port_data [list \
                    "name"           [ig::db::get_attribute -object $i_port -attribute "name"] \
                    "object"         $i_port \
                    "size"           [ig::db::get_attribute -object $i_port -attribute "size"] \
                    "vlog.bitrange"  [ig::vlog::obj_bitrange $i_port] \
                    "direction"      [ig::db::get_attribute -object $i_port -attribute "direction"] \
                    "vlog.direction" [ig::vlog::port_dir $i_port] \
                    "dimension"      $dimension_bitrange \
                ]
            }
            lappend result "ports" $port_data

            # parameters
            set param_data {}
            foreach i_param [ig::db::get_parameters -of $module_id] {
                lappend param_data [list \
                    "name"           [ig::db::get_attribute -object $i_param -attribute "name"] \
                    "object"         $i_param \
                    "local"          [ig::db::get_attribute -object $i_param -attribute "local"] \
                    "vlog.type"      [ig::vlog::param_type $i_param] \
                    "value"          [ig::db::get_attribute -object $i_param -attribute "value"] \
                ]
            }
            lappend result "parameters" $param_data

            # delarations
            set decl_data {}
            foreach i_decl [ig::db::get_declarations -of $module_id] {
                set dimension_bitrange {}
                foreach dimension [ig::db::get_attribute -object $i_decl -attribute "dimension" -default {}] {
                    append dimension_bitrange [ig::vlog::bitrange $dimension]
                }
                lappend decl_data [list \
                    "name"           [ig::db::get_attribute -object $i_decl -attribute "name"] \
                    "object"         $i_decl \
                    "size"           [ig::db::get_attribute -object $i_decl -attribute "size"] \
                    "vlog.bitrange"  [ig::vlog::obj_bitrange $i_decl] \
                    "defaulttype"    [ig::db::get_attribute -object $i_decl -attribute "default_type"] \
                    "vlog.type"      [ig::vlog::declaration_type $i_decl] \
                    "dimension"      $dimension_bitrange \
                ]
            }
            lappend result "declarations" $decl_data

            # codesections
            set code_data {}
            foreach i_code [ig::db::get_codesections -of $module_id] {
                lappend code_data [list \
                    "name"           [ig::db::get_attribute -object $i_code -attribute "name"] \
                    "object"         $i_code \
                    "code_raw"       [ig::db::get_attribute -object $i_code -attribute "code"] \
                    "code"           [ig::aux::adapt_codesection $i_code] \
                ]
            }
            set code_data [ig::aux::align_codesections $code_data]
            lappend result "code" $code_data

            # instances
            set inst_data {}
            foreach i_inst [ig::db::get_instances -of $module_id] {
                lappend inst_data [instance_to_arraylist $i_inst]
            }
            lappend result "instances" $inst_data

            # regfiles
            set regfile_data {}
            foreach i_regfile [ig::db::get_regfiles -of $module_id] {
                lappend regfile_data [list \
                    "name"    [ig::db::get_attribute -object $i_regfile -attribute "name"] \
                    "object"  $i_regfile \
                    "entries" [regfile_to_arraylist $i_regfile] \
                ]
            }
            lappend result "regfiles" $regfile_data

            return $result
        }

        namespace export *
    }

    ## @brief Load directory with templates.
    # @param dir Path to directory with templates.
    #
    # dir should contain one subdirectory for each template.
    # Each subdirectory should contain an "init.tcl" script inserting the template's
    # callbacks using the methods provided by @ref ig::templates::init
    proc add_template_dir {dir} {
        set _tmpl_dirs [glob -directory $dir *]
        foreach _i_dir ${_tmpl_dirs} {
            set _initf_name "${_i_dir}/init.tcl"
            if {![file exists ${_initf_name}]} {
                continue
            }

            if {[catch {
                set _init_scr [open ${_initf_name} "r"]
                set _init [read ${_init_scr}]
                close ${_init_scr}
            }]} {
                continue
            }

            set template [file tail [file normalize [file dirname ${_initf_name}]]]
            eval ${_init}
            init::template_dir $template [file normalize "${dir}/${template}"]
        }
    }

    ## @brief Load a template to use.
    # @param template Template to use. The template must have been loaded with a
    # template directory using @ref add_template_dir.
    proc load_template {template} {
        # load vars/procs for current template
        set dir_idx  [lsearch -index 0 $collection::template_dir       $template]
        set type_idx [lsearch -index 0 $collection::output_types_gen   $template]
        set tmpl_idx [lsearch -index 0 $collection::template_path_gen  $template]
        set out_idx  [lsearch -index 0 $collection::output_path_gen    $template]

        if {($dir_idx < 0) || ($type_idx < 0) || ($tmpl_idx < 0) || ($out_idx < 0)} {
            ig::log -error -abort "template $template not (fully) defined"
        }

        set current::template_dir [lindex $collection::template_dir $dir_idx 1]
        # workaround for doxygen: is otherwise irritated by directly visible proc keyword
        set procdef "proc"
        $procdef current::get_output_types      {object}                   [lindex $collection::output_types_gen   $type_idx 1]
        $procdef current::get_template_file_raw {object type template_dir} [lindex $collection::template_path_gen  $tmpl_idx 1]
        $procdef current::get_output_file       {object type}              [lindex $collection::output_path_gen    $out_idx  1]
    }

    ## @brief Parse a template.
    # @param txt Template as a single String.
    # @param filename Name of template file for error logging.
    # @return Tcl-Code generated from template as a single String.
    #
    # The template method is copied/modified to fit here from
    # http://wiki.tcl.tk/18175
    #
    # The resulting Tcl Code will write the generated output to a variable @c _res
    # when evaluated.
    proc parse_template {txt {filename {}}} {
        set code  "set _res {}\n"
        set stack [list [list $filename 1 $txt]]

        while {[llength $stack] > 0} {
            lassign [lindex $stack end] filename linenr txt
            set stack [lreplace $stack end end]

            append code "set _filename [list $filename]\n"
            append code "set _linenr $linenr\n"

            set re_delim_open     {<(%|\[)([+-])?}
            set delim_close       "%>"
            set delim_close_brack "\]>"

            # search  delimiter
            while {[regexp -indices $re_delim_open $txt indices m_type m_chomp]} {
                lassign $indices i_delim_start i_delim_end

                # include tag
                set incltag 0

                set opening_char [string index $txt [lindex $m_type 0]]
                if {$opening_char eq "%"} {
                    set closing_delim $delim_close
                } else {
                    set closing_delim $delim_close_brack
                }

                # check for right chomp
                set right_i [expr {$i_delim_start - 1}]


                set i [expr {$i_delim_end + 1}]
                if {([string index $txt [lindex $m_chomp 0]] eq "-") && ([string index $txt $right_i] eq "\n")} {
                    incr right_i -1
                }

                # append verbatim/normal template content (tcl-list)
                incr linenr [ig::aux::string_count_nl [string range $txt 0 [expr {$i-1}]]]
                append code "set _linenr $linenr\n"
                append code "append _res [list [string range $txt 0 $right_i]]\n"
                set txt [string range $txt $i end]

                if {$closing_delim eq "%>"} {
                    if {[string index $txt 0] eq "="} {
                    # <%= will be be append, but evaluated as tcl-argument
                        append code "append _res "
                        set txt [string range $txt 1 end]
                    } elseif {[string index $txt 0] eq "I"} {
                    # <%I will be included here
                        set incltag 1
                        set txt [string range $txt 1 end]
                    } else {
                    # append as tcl code
                    }
                } else {
                    # closing delimiter is closing square bracket
                    append code "append _res \[ "
                }

                # search ${closing_delim} delimiter
                if {[set i [string first $closing_delim $txt]] == -1} {
                    error "No matching $closing_delim"
                }
                set left_i [expr {$i + 2}]
                incr i -1
                # check for left chomp
                if {[string match {[-+]} [string index $txt $i]]} {
                    if {([string index $txt $i] eq "-") && ([string index $txt $left_i] eq "\n")} {
                        incr left_i
                    }
                    incr i -1
                }

                # include tag / code
                incr linenr [ig::aux::string_count_nl [string range $txt 0 [expr {$left_i-1}]]]

                if {$incltag} {
                    set incfname [eval "file join \${current::template_dir} [string range $txt 0 $i]"]
                    ig::log -info -id TPrs "...parsing included template $incfname"
                    set incfile [open $incfname "r"]
                    set inccontent [read $incfile]
                    close $incfile

                    lappend stack [list $filename $linenr [string range $txt $left_i end]]
                    set linenr 1
                    set filename $incfname
                    set txt $inccontent

                    # loop-check
                    if {[lsearch -index 0 $stack $filename] >= 0} {
                        error "template file $filename includes itself"
                    }
                } else {
                    if {$closing_delim eq "%>"} {
                        append code "[string range $txt 0 $i] \n"
                    } else {
                        # closing delimiter is closing square bracket
                        append code "[string range $txt 0 $i] \]\n"
                    }
                    set txt [string range $txt $left_i end]
                }
                append code "set _filename [list $filename]\n"
                append code "set _linenr $linenr\n"
            }

            # append remainder of verbatim/normal template content
            if {$txt ne ""} {
                append code "append _res [list $txt]\n"
            }
        }

        return $code
    }

    proc parse_template2 {txt} {
        set    code "set _res {}\n"
        append code "set _linenr 1\n"
        set linenr 1

        while {[regexp -expanded {
                    ^
                    (.*?)
                    (\n)?
                    <(%|\[)([-+]?)([i=]?)
                    (.*?)
                    ([I=]?)([-+]?)(%|\])>
                    (\n)?
                    (.*)
                    $
                } $txt m_whole \
                m_txt_pre m_nl_pre m_delim_left m_chomp_left m_delim2_left \
                m_code \
                m_delim2_right m_chomp_right m_delim_right m_nl_post m_txt_post]} {

            # remove newline at start tag
            append code "set _linenr $linenr\n"
            if {$m_chomp_left eq "-"} {
                append code "append _res [list ${m_txt_pre}]\n"
            } else {
                append code "append _res [list ${m_txt_pre}${m_nl_pre}]\n"
            }
            incr linenr [ig::aux::string_count_nl ${m_txt_pre}]
            incr linenr [ig::aux::string_count_nl ${m_nl_pre}]
            append code "set _linenr $linenr\n"

            # check
            if {(([string index $m_delim_left 0] eq "%") != ([string index $m_delim_right end] eq "%"))
                    || (($m_delim2_left eq "") && ($m_delim2_right ne ""))
                    || (($m_delim2_left ne "") && ($m_delim2_right ne "") && ($m_delim2_right ne $m_delim2_left))} {
                error "template tag mismatch - left: \"${m_delim_left}\", right: \"${m_delim_right}\""
            }

            # process tag
            set txt {}
            if {[string index $m_delim_left 0] eq "%"} {
                if {$m_delim2_left eq "="} {
                    append code "append _res ${m_code}\n"
                } elseif {$m_delim2_left eq "I"} {
                    set incfname [eval "file join \${current::template_dir} [string trim $m_code]"]
                    set incfile [open $incfname "r"]
                    set txt [read $incfile]
                    incr linenr [expr {-[ig::aux::string_count_nl ${txt}]}]
                    close $incfile
                } else {
                    append code "${m_code}\n"
                }
            } else {
                append code "append _res \[${m_code}\]\n"
            }
            incr linenr [ig::aux::string_count_nl ${m_code}]
            append code "set _linenr $linenr\n"

            # remove newline at end tag
            if {$m_chomp_right eq "-"} {
                append txt ${m_txt_post}
                incr linenr [ig::aux::string_count_nl ${m_nl_post}]
            } else {
                append txt ${m_nl_post}${m_txt_post}
            }
        }

        append code "set _linenr $linenr\n"
        # append remainder of verbatim/normal template content
        if {$txt ne ""} {
            append code "append _res [list $txt]\n"
        }
        return $code
    }

    ## @brief Return comment begin/end for given filetype
    # @param filesuffix Suffix for filetype
    # @return List with two elements: begin of comment and end of comment, e.g. {"/* " " */"}
    proc comment_begin_end {filesuffix} {
        switch -exact -- [string tolower $filesuffix] {
            .h      -
            .hpp    -
            .h++    -
            .c      -
            .cpp    -
            .c++    -
            .sv     -
            .svh    -
            .vh     -
            .v      {return [list "/* "   " */"]}

            .vhd    -
            .vhdl   {return [list "-- "   "\n"]}

            .htm    -
            .html   {return [list "<!-- " " -->"]}

            .tex    {return [list "% "    "\n"]}

            default {return [list "# "    "\n"]}
        }
    }

    ## @brief Parse keep blocks of an existing output (file).
    # @param txt Existing generated output as single String.
    # @param filesuffix Suffix of filetype of file blocks are parsed in
    # @return List of parsed blocks as sublists of form {\<maintype\> \<subtype\> \<content\>}.
    #
    # The blocks parsed are of the form @code{.v}
    # /* icglue <maintype> begin <subtype> */
    # /* icglue <maintype> end */
    # @endcode
    #
    # Currently only @c keep is supported as maintype.
    # Subtypes depend on the template used.
    proc parse_keep_blocks {txt {filesuffix ".v"}} {
        set result [list]
        lassign [comment_begin_end $filesuffix] cbegin cend

        # compatibility: accept comments with "pragma"
        if {[string first "${cbegin}pragma icglue keep begin " $txt] >= 0} {
            set block_start "${cbegin}pragma icglue keep begin "
            set block_end   "${cbegin}pragma icglue keep end${cend}"
        } else {
            set block_start "${cbegin}icglue keep begin "
            set block_end   "${cbegin}icglue keep end${cend}"
        }

        while {[set i [string first $block_start $txt]] >= 0} {
            incr i [string length $block_start]

            if {[set j [string first $cend $txt $i]] < 0} {
                error "No end of icglue keep comment"
            }

            set type [string range $txt $i [expr {$j - 1}]]
            set txt [string range $txt [expr {$j + [string length $cend]}] end]

            if {[set i [string first $block_end $txt]] < 0} {
                error "No end of block after keep block begin - pragma type was ${type}"
            }
            set value [string range $txt 0 [expr {$i-1}]]
            set txt [string range $txt [expr {$i + [string length $block_end]}] end]

            lappend result [list "keep" $type $value]
        }
        return $result
    }

    ## @brief Format given content of keep block for specified filetype.
    # @param block_entry Block main type.
    # @param block_subentry Block sub type.
    # @param content Content to format inside block.
    # @param filesuffix Suffix of filetype for generated block comments.
    # @return Formatted keep block string for given content/filetype.
    proc format_keep_block_content {block_entry block_subentry content filesuffix} {
        set result {}
        lassign [comment_begin_end $filesuffix] cbegin cend

        append result "${cbegin}icglue ${block_entry} begin ${block_subentry}${cend}"
        append result $content
        append result "${cbegin}icglue ${block_entry} end${cend}"

        return $result
    }

    ## @brief Get content of specific keep block.
    # @param block_data Block data as generated by @ref parse_keep_blocks.
    # @param block_entry Block main type to look up.
    # @param block_subentry Block sub type to look up.
    # @param filesuffix Suffix of filetype for generated block comments.
    # @param default_content Default block content if nothing has been parsed
    # @return Content of specified block previously parsed or default_content.
    proc get_keep_block_content {block_data block_entry block_subentry {filesuffix ".v"} {default_content {}}} {
        set idx [lsearch -index 1 [lsearch -inline -all -index 0 $block_data $block_entry] $block_subentry]

        if {$idx >= 0} {
            return [format_keep_block_content $block_entry $block_subentry [lindex $block_data $idx 2] $filesuffix]
        } else {
            return [format_keep_block_content $block_entry $block_subentry $default_content $filesuffix]
        }
    }

    ## @brief Get content of specific keep block and remove it from keep blocks.
    # @param block_data_var Variable name containing block data as generated by @ref parse_keep_blocks.
    # @param block_entry Block main type to look up.
    # @param block_subentry Block sub type to look up.
    # @param filesuffix Suffix of filetype for generated block comments.
    # @param default_content Default block content if nothing has been parsed
    # @return Content of specified block previously parsed or default_content.
    #
    # The returned block will be removed from the list in block_data_var.
    proc pop_keep_block_content {block_data_var block_entry block_subentry {filesuffix ".v"} {default_content {}}} {
        upvar 1 $block_data_var block_data
        set idx [lsearch -index 1 [lsearch -inline -all -index 0 $block_data $block_entry] $block_subentry]

        if {$idx >= 0} {
            set result [format_keep_block_content $block_entry $block_subentry [lindex $block_data $idx 2] $filesuffix]
            set block_data [lreplace $block_data $idx $idx]
            return $result
        } else {
            return [format_keep_block_content $block_entry $block_subentry $default_content $filesuffix]
        }
    }

    ## @brief Get a list of all remaining keep blocks.
    # @param block_data Block data as generated by @ref parse_keep_blocks.
    # @param filesuffix Suffix of filetype for generated block comments.
    # @param nonempty Only return non-empty keep blocks.
    # @return list of all generated keep block comments.
    proc remaining_keep_block_contents {block_data {filesuffix ".v"} {nonempty "true"}} {
        set result [list]

        foreach i_block $block_data {
            lassign $i_block block_entry block_subentry content

            if {$nonempty && ($content eq {})} {continue}

            lappend result [format_keep_block_content $block_entry $block_subentry $content $filesuffix]
        }

        return $result
    }

    # template parse cache
    variable template_script_cache [list]

    ## @brief Lookup template file in cache and returned cached template script or parse @c template_filename.
    # @param template_filename Path to file to lookup.
    # @return cached or parsed template file script.
    proc get_template_script {template_filename} {
        variable template_script_cache

        set fname_full [file normalize $template_filename]

        set idx [lsearch -index 0 $template_script_cache $fname_full]
        if {$idx >= 0} {
            return [lindex $template_script_cache $idx 1]
        }

        set template_file [open ${template_filename} "r"]
        set template_raw [read ${template_file}]
        close ${template_file}

        set template_script [parse_template ${template_raw} ${template_filename}]

        lappend template_script_cache [list $fname_full $template_script]

        return $template_script
    }

    ## @brief Generate output for given object of specified type.
    # @param obj_id Object-ID to write output for.
    # @param type Type of template as delivered by @ref ig::templates::current::get_output_types.
    # @param dryrun If set to true, no actual files are written.
    #
    # The output is written to the file specified by the template callback @ref ig::templates::current::get_output_file.
    proc write_object {obj_id type {dryrun false}} {
        if {[catch {set _tt_name [current::get_template_file $obj_id $type]}]} {
            return
        }

        set _outf_name [current::get_output_file $obj_id $type]

        set _outf_name_var ${_outf_name}
        set _tt_name_var   ${_tt_name}

        set _outf_name_var_norm [file normalize ${_outf_name_var}]
        set _outf_name_var_new [string map [list [file normalize [pwd]]  {.}] ${_outf_name_var_norm}]
        if {${_outf_name_var_new} ne ${_outf_name_var_norm}} {
            set _outf_name_var ${_outf_name_var_new}
        } else {
            if {[info exists ::env(ICPRO_DIR)]} {
                set _outf_name_var [string map [list $::env(ICPRO_DIR) {$ICPRO_DIR}] ${_outf_name_var}]
            }
        }

        ig::log -info -id Gen "Generating ${_outf_name_var}"
        ig::log -info -id TPrs "Parsing template ${_tt_name}"
        set block_data [list]
        if {[file exists ${_outf_name}]} {
            set _outf [open ${_outf_name} "r"]
            set _old [read ${_outf}]
            close ${_outf}
            set block_data [parse_keep_blocks ${_old} [file extension ${_outf_name}]]
        }

        set _tt_code [get_template_script ${_tt_name}]

        # evaluate result in temporary namespace
        eval [join [list \
            "namespace eval _template_run \{" \
            {    namespace import ::ig::aux::*} \
            {    namespace import ::ig::templates::preprocess::*} \
            {    namespace import ::ig::templates::get_keep_block_content} \
            {    namespace import ::ig::templates::pop_keep_block_content} \
            {    namespace import ::ig::templates::remaining_keep_block_contents} \
            {    namespace import ::ig::log} \
            "    variable keep_block_data [list $block_data]" \
            {    variable _res {}} \
            {    variable _linenr 0} \
            {    variable _filename {}} \
            {    variable _error {}} \
            "    proc echo {args} \{" \
            {        variable _res} \
            {        append _res {*}$args} \
            "    \}" \
            "    variable obj_id [list $obj_id]" \
            "    if {\[catch {" \
            "        eval [list ${_tt_code}]" \
            "        } _errorres\]} {" \
            {        set _error $_errorres} \
            "    }" \
            "\}" \
            ] "\n"]

        set _res      ${_template_run::_res}
        set _error    ${_template_run::_error}
        set _linenr   ${_template_run::_linenr}
        set _filename ${_template_run::_filename}
        namespace delete _template_run

        if {${_error} ne ""} {
            ig::log -error "Error while running template for object [ig::db::get_attribute -object ${obj_id} -attribute "name"] and output type ${type}\nstacktrace:\n${::errorInfo}"
            ig::log -error "template ${_filename} somewhere after line ${_linenr}"
            return
        }

        if {!$dryrun} {
            file mkdir [file dirname ${_outf_name}]
            set _outf [open ${_outf_name} "w"]
            puts -nonewline ${_outf} ${_res}
            close ${_outf}
        }
    }

    ## @brief Generate output for given object for all output types provided by template.
    # @param obj_id Object-ID to write output for.
    # @param dryrun If set to true, no actual files are written.
    #
    # Iterates over all output types provided by template callback @ref ig::templates::current::get_output_file
    # and writes output via the template.
    proc write_object_all {obj_id {dryrun false}} {
        foreach i_type [current::get_output_types $obj_id] {
            write_object $obj_id $i_type $dryrun
        }
    }

    namespace export *
}

