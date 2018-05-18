
#
#   ICGlue is a Tcl-Library for scripted HDL generation
#   Copyright (C) 2017-2018  Andreas Dixius, Felix Neumärker
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

package provide ICGlue 1.0a1

## @brief Main namespace of ICGlue.
# Contains functionality needed in construction scripts.
namespace eval ig {
    ## @brief Construction helpers.
    namespace eval construct {
        ## @brief Expand instance expression list.
        #
        # @param inst_list List of instance expressions.
        # @param ids Return instance object IDs instead of names (default: false).
        # @param merge (Only in combination with ids=true) Return list of merged expressions with IDs and originial expression remainder (default: false).
        #
        # @return List of expanded instance expressions {instance-name module-name remainder}.
        #
        # The input list can contain expressions of the form module\<instance1,instance2\>-\>signal.
        # The default result would then contain two lists: {module_instance1 module -\>signal} and {module_instance2 module -\>signal}.
        #
        # If ids is set, the object ids of module and instance will be returned.
        # If there is no instance of the given instance-name to be found, a module id will be looked up.
        # If merge is set as well, the result-list will be reduced to a single entry for each instance of the form ${id}-\>signal.
        proc expand_instances {inst_list {ids false} {merge false}} {
            set result [list]

            foreach i_entry $inst_list {
                if {[regexp -expanded {
                    ^
                    ([^<>]+)
                    (<(.*)>)?
                    (->[^\s]+)?
                    $
                } $i_entry m_entry m_module m_instwrap m_insts m_rem]} {
                    if {$m_instwrap eq ""} {
                        lappend result [list $m_module $m_module $m_rem]
                    } else {
                        foreach i_sfx [split $m_insts ","] {
                            if {[regexp {(.*)\.\.(.*)} $i_sfx m_sfx m_start m_stop]} {
                                for {set i $m_start} {$i <= $m_stop} {incr i} {
                                    lappend result [list "${m_module}_${i}" $m_module $m_rem]
                                }
                            } else {
                                lappend result [list "${m_module}_${i_sfx}" $m_module $m_rem]
                            }
                        }
                    }
                } else {
                    error "could not parse $i_entry"
                }
            }

            if {$ids} {
                set result_ids [list]

                foreach i_r $result {
                    set inst [lindex $i_r 0]
                    if {[catch {set inst_id [ig::db::get_instances -name $inst]}]} {
                        set inst_id [ig::db::get_modules -name $inst]
                    }
                    if {$merge} {
                        lappend result_ids "${inst_id}[lindex $i_r 2]"
                    } else {
                        lappend result_ids [list \
                            $inst_id \
                            [ig::db::get_modules   -name [lindex $i_r 1]] \
                            [lindex $i_r 2]
                        ]
                    }
                }

                set result $result_ids
            }

            return $result
        }

        ## @brief Run a construction script in encapsulated namespace.
        #
        # @param filename Path to script.
        proc run_script {filename} {
            eval [join [list \
                "namespace eval _construct_run \{" \
                "    namespace import ::ig::*" \
                "    if {\[catch {source [list $filename]}\]} \{" \
                "        ig::errinf::print_st_line [list $filename]" \
                "        ig::log -error \"Error while parsing source \\\"[list $filename]\\\"\"" \
                "        exit 1" \
                "    \}" \
                "\}" \
                ] "\n"]

            namespace delete _construct_run
        }
    }


    ## @brief Create a new module.
    #
    ## @brief Option parser helper wrapper
    #
    # @param args <b> [OPTION]... MODULENAME</b><br>
    #    <table style="border:0px; border-spacing:40px 0px;">
    #      <tr><td><b> MODULENAME  </b></td><td> specify a modulename <br></td></tr>
    #      <tr><td><b> OPTION </b></td><td><br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -u(nit)                  </i></td><td>  specify unit name [directory]      <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -i(nst(ances|anciate)?)  </i></td><td>  specify Module to be instanciated  <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -rtl                     </i></td><td>  specify rtl attribute for module   <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -beh(av(ioral|ioural)?)  </i></td><td>  specify rtl attribute for module   <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -(tb|testbench)          </i></td><td>  specify rtl attribute for module   <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -v(erilog)               </i></td><td>  output verilog language            <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -sv|-s(ystemverilog)     </i></td><td>  output systemverilog language      <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -v(dhl)                  </i></td><td>  output vhdl language               <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -(ilm|macro)             </i></td><td>  pass ilm attribute to icglue       <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -res(ource)              </i></td><td>  pass ressource attribute to icglue <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -(rf|(regf(ile)?))       </i></td><td>  pass regfile attribute to icglue   <br></td></tr>
    #      <tr><td><i> &ensp; &ensp; -attr(ibutes)            </i></td><td>  pass an arribute dict to icglue    <br></td></tr>
    #    </table>
    # @return Object-ID of the newly created module.
    proc M args {
        # defaults
        set name          ""
        set unit          ""
        set instance_tree {}
        set mode          "rtl"
        set lang          "verilog"
        set ilm           "false"
        set resource      "false"
        set instances     {}
        set regfiles      {}

        # parse_opts { <regexp> <argumenttype/check> <varname> <description> }
        set name [ig::aux::parse_opts [list \
                   { {^-u(nit)?$}                 "string"              unit       "specify unit name \[directory\]"     } \
                   { {^-i(nst(ances|anciate)?)?$} "string"              instances  "specify Module to be instanciated"   } \
                                                                                                                           \
                   { {^-rtl$}                     "const=rtl"           mode       "specify rtl attribute for module"    } \
                   { {^-beh(av(ioral|ioural)?)?$} "const=behavioral"    mode       "specify rtl attribute for module"    } \
                   { {^-(tb|testbench)$}          "const=behavioral"    mode       "specify rtl attribute for module"    } \
                                                                                                                           \
                   { {^-v(erilog)?$}              "const=verilog"       lang       "output verilog language"             } \
                   { {^-sv|-s(ystemverilog)?$}    "const=systemverilog" lang       "output systemverilog language"       } \
                   { {^-v(dhl)?$}                 "const=vhdl"          lang       "output vhdl language"                } \
                                                                                                                           \
                   { {^-(ilm|macro)$}             "const=ilm"           ilm        "pass ilm attribute to icglue"        } \
                   { {^-res(ource)?$}             "const=true"          resource   "pass ressource attribute to icglue"  } \
                                                                                                                           \
                   { {^-(rf|(regf(ile)?))$}       "string"              regfiles   "pass regfile attribute to icglue"    } \
                                                                                                                           \
                   { {^-attr(ibutes)?$}           "string"              attributes "pass an arribute dict to icglue"     } \
            ] -context "MODULENAME" $args]

        # argument checks
        if {[llength $name] > 1} {
            log -error -abort "M: too many arguments ($name)"
        }

        if {$unit eq ""} {set unit $name}
        if {$name eq ""} {
            log -error -abort "M: need a module name"
        }
        if {$resource && ([llength $instances] > 0)} {
            log -error -abort "M (module ${name}): a resource cannot have instances"
        }

        # actual module creation
        if {[catch {
            if {$resource} {
                set modid [ig::db::create_module -resource -name $name]
            } elseif {$ilm} {
                set modid [ig::db::create_module -ilm -name $name]
            } else {
                set modid [ig::db::create_module -name $name]
            }
            ig::db::set_attribute -object $modid -attribute "language"   -value $lang
            ig::db::set_attribute -object $modid -attribute "mode"       -value $mode
            ig::db::set_attribute -object $modid -attribute "parentunit" -value $unit

            # instances
            foreach i_inst [construct::expand_instances $instances] {
                set i_name [lindex $i_inst 0]
                set i_mod  [lindex $i_inst 1]

                log -debug "M (module = $name): creating instance $i_name of module $i_mod"

                ig::db::create_instance \
                    -name $i_name \
                    -of-module [ig::db::get_modules -name $i_mod] \
                    -parent-module $modid \
            }

            # regfiles
            foreach i_rf $regfiles {
                ig::db::add_regfile -regfile $i_rf -to $modid
            }
        } emsg]} {
            log -error -abort "M (module ${name}): error while creating module:\n${emsg}"
        }

        return $modid
    }

    ## @brief Create a new signal.
    #
    # @param args Parsed command arguments:<br>
    # [ -w \<signal-width\> ]<br>
    # \<signal-name\><br>
    # ( \<source\> -\> \<target-list\><br>
    # | \<target-list\> \<- \<source\><br>
    # | (-bidir | \<-\>) \<target-list\> )
    #
    # @return Object-IDs of the newly created objects of newly created signal.
    #
    # Source and target-lists will be expanded and can contain local signal-name specifications after a "->" symbol
    # (local signal-name suffixes can be generated when the signal-name is followed by "!")
    # and multi-instance-expressions e.g. module\<1,4..9,a,b\>.
    proc S args {
        # defaults
        set name      ""
        set width     1
        set bidir     "false"
        set invert    "false"
        set con_left  {}
        set con_right {}
        set con_list  0

        # args
        set lastarg {}

        foreach i_arg $args {
            switch -- $lastarg {
                -w {
                    set width $i_arg
                    set lastarg {}
                }
                default {
                    switch -regexp -- $i_arg {
                        {^-w(idth)?$}                {set lastarg -w}
                        {^-b(idir(ectional)?)?$}     {incr con_list; set bidir "true"}

                        {^->$}                       {incr con_list}
                        {^<-$}                       {incr con_list; set invert "true"}
                        {^<->$}                      {incr con_list; set bidir  "true"}

                        default {
                            if {$con_list == 0} {
                                incr con_list
                                set name $i_arg
                            } else {
                                foreach i_elem $i_arg {
                                    if {$con_list == 1} {
                                        lappend con_left $i_elem
                                    } elseif {$con_list == 2} {
                                        lappend con_right $i_elem
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        # argument checks
        if {[lsearch {-w} $lastarg] >= 0} {
            log -error -abort "S (signal ${name}): need an argument after ${lastarg}"
        }

        if {$con_list > 2} {
            log -error -abort "S (signal ${name}): too many direction arguments"
        }

        if {$name eq ""} {
            log -error -abort "S: no signal name specified"
        }

        # adaption
        if {$invert} {
            set temp      $con_left
            set con_left  $con_right
            set con_right $temp
        }
        if {$bidir} {
            set con_left  [concat $con_left $con_right]
            set con_right {}
        }

        # actual module creation
        if {[catch {
            set con_left  [construct::expand_instances $con_left  "true" "true"]
            set con_right [construct::expand_instances $con_right "true" "true"]

            if {$bidir} {
                set sigid [ig::db::connect -bidir $con_left -signal-name $name -signal-size $width]
            } else {
                set sigid [ig::db::connect -from {*}$con_left -to $con_right -signal-name $name -signal-size $width]
            }
        } emsg]} {
            log -error -abort "S (signal ${name}): error while creating signal:\n${emsg}"
        }

        return $sigid
    }

    ## @brief Create a new parameter.
    #
    # @param args Parsed command arguments:<br>
    # -v \<parameter-value\><br>
    # \<parameter-name\><br>
    # \<endpoint-list\>
    #
    # @return Object-IDs of the newly created objects of newly created parameter.
    #
    # Endpoint-list will be expanded and can contain local parameter-name specifications after a "->" symbol
    # and multi-instance-expressions e.g. module\<1,4..9,a,b\>.
    proc P args {
        # defaults
        set name      ""
        set value     {}
        set endpoints {}
        set ilist     0

        # args
        set lastarg {}

        foreach i_arg $args {
            switch -- $lastarg {
                -v {
                    set value $i_arg
                    set lastarg {}
                }
                default {
                    switch -regexp -- $i_arg {
                        {^-v(alue)?$}                {set lastarg -v}

                        default {
                            if {$ilist == 0} {
                                incr ilist
                                set name $i_arg
                            } else {
                                foreach i_elem $i_arg {
                                    lappend endpoints $i_elem
                                }
                            }
                        }
                    }
                }
            }
        }

        # argument checks
        if {[lsearch {-v} $lastarg] >= 0} {
            log -error -abort "P (parameter ${name}): need an argument after ${lastarg}"
        }

        if {$name eq ""} {
            log -error -abort "P: no parameter name specified"
        }
        if {$value eq ""} {
            log -error -abort "P (parameter ${name}): no value specified"
        }

        # actual parameter creation
        if {[catch {
            set endpoints [construct::expand_instances $endpoints "true" "true"]

            set paramid [ig::db::parameter -name $name -value $value -targets $endpoints]
        } emsg]} {
            log -error -abort "P (parameter ${name}): error while creating parameter:\n${emsg}"
        }

        return $paramid
    }

    ## @brief Create a new codesection.
    #
    # @param args Parsed command arguments:<br>
    # -m \<module\><br>
    # [( -adapt | -verbatim )]<br>
    # \<code\>
    #
    # @return Object-ID of the newly created codesection.
    #
    # If adapt is specified (default), signal names in the code-block will be adapted by their local names.
    proc C args {
        # defaults
        set modname   ""
        set adapt     "true"
        set code      {}

        # args
        set lastarg {}

        foreach i_arg $args {
            switch -- $lastarg {
                -m {
                    set modname $i_arg
                    set lastarg {}
                }
                default {
                    switch -regexp -- $i_arg {
                        {^-m(od(ule)?)?$}           {set lastarg -m}
                        {^-a(dapt)?$}               {set adapt "true"}
                        {^(-v(erbatim)?|-noadapt)$} {set adapt "false"}

                        default {
                            lappend code $i_arg
                        }
                    }
                }
            }
        }

        # argument checks
        if {[lsearch {-m} $lastarg] >= 0} {
            log -error -abort "C: need an argument after ${lastarg}"
        }

        if {$modname eq ""} {
            log -error -abort "C: no module name specified"
        }

        set code [join $code "\n"]
        if {$code eq ""} {
            log -error -abort "C (module ${modname}): no code section specified"
        }

        # actual code creation
        if {[catch {
            set cid [ig::db::add_codesection -parent-module [ig::db::get_modules -name $modname] -code $code]

            ig::db::set_attribute -object $cid -attribute "adapt" -value $adapt
        } emsg]} {
            log -error -abort "C (module ${modname}): error while creating codesection:\n${emsg}"
        }

        return $cid
    }

    ## @brief Create a new regfile-entry.
    #
    # @param args Parsed command arguments:<br>
    # -rf \<regfile-name\><br>
    # \<entry-name\><br>
    # \@\<address\><br>
    # \<register-table\>
    #
    # @return Object-ID of the newly created regfile-entry.
    #
    # \<register-table\> is a list of the form {\<header\> \<reg1\> \<reg2\> ...}.
    #
    # \<header\> is the register-table header and specifies the order of register-info block
    # in the following register sublists. It must contain at least "name", can contain:
    # @li name = name of the generated register.
    # @li width = bitwidth of the generated register.
    # @li entrybits = bitrange (\<high\>:\<low\>) inside the generated regfile-entry.
    # @li type = type of generated register. Can be one of "R","RW".
    # @li reset = reset value of generated register.
    # @li signal = signal to drive from generated register.
    # @li signalbits = bits of signal to drive (default: whole signal).
    #
    # \<reg\<n\>\>: Sublists containing the actual register-data.
    proc R args {
        # defaults
        set entryname   ""
        set regfilename ""
        set address     -1
        set regdef      {}

        # args
        set lastarg {}

        foreach i_arg $args {
            switch -- $lastarg {
                -rf {
                    set regfilename $i_arg
                    set lastarg {}
                }
                default {
                    switch -regexp -matchvar mlist -- $i_arg {
                        {^-(rf|regf(ile)?)$}        {set lastarg -rf}
                        {^@(.*)$}                   {set address [lindex $mlist 1]}

                        default {
                            if {$entryname eq ""} {
                                set entryname $i_arg
                            } elseif {[llength $regdef] == 0} {
                                set regdef $i_arg
                            } else {
                                log -error -abort "R (regfile-entry ${entryname}): too many arguments"
                            }
                        }
                    }
                }
            }
        }

        # argument checks
        if {[lsearch {-rf} $lastarg] >= 0} {
            log -error -abort "R: need an argument after ${lastarg}"
        }

        if {$entryname eq ""} {
            log -error -abort "R: no regfile-entry name specified"
        } elseif {$regfilename eq ""} {
            log -error -abort "R (regfile-entry ${entryname}): no regfile name specified"
        } elseif {(![string is integer $address]) || ($address < 0)} {
            log -error -abort "R (regfile-entry ${entryname}): no/invalid address"
        } elseif {[llength $regdef] <= 1} {
            log -error -abort "R (regfile-entry ${entryname}): no registers specified"
        }

        # entry map
        set entry_default_map {name width entrybits type reset signal signalbits}
        set entry_map {}
        foreach i_entry [lindex $regdef 0] {
            set idx_def [lsearch -glob $entry_default_map "${i_entry}*"]
            if {$idx_def < 0} {
                log -error -abort "R (regfile-entry ${entryname}): invalid register attribute-name: ${i_entry}"
            }
            lappend entry_map [lindex $entry_default_map $idx_def]
        }
        foreach i_entry $entry_default_map {
            if {[lsearch $entry_map $i_entry] < 0} {
                lappend entry_map $i_entry
            }
        }
        set regdef [lrange $regdef 1 end]

        # actual regfile creation
        if {[catch {
            # get regfile
            set regfile_id ""
            foreach i_md [ig::db::get_modules -all] {
                if {![catch {ig::db::get_regfiles -name $regfilename -of $i_md} i_id]} {
                    set regfile_id $i_id
                }
            }
            if {$regfile_id eq ""} {
                log -error -abort "R (regfile-entry ${entryname}): invalid regfile name specified: ${regfilename}"
            }

            # create entry
            set entry_id [ig::db::add_regfile -entry $entryname -to $regfile_id]
            ig::db::set_attribute -object $entry_id -attribute "address" -value $address

            # creating registers
            foreach i_reg $regdef {
                set i_name [lindex $i_reg [lsearch $entry_map "name"]]

                if {$i_name eq ""} {
                    log -error -abort "R (regfile-entry ${entryname}): reg defined without name"
                }

                set reg_id [ig::db::add_regfile -reg $i_name -to $entry_id]
                foreach i_attr [lrange $entry_default_map 1 end] {
                    # attributes except name
                    set i_val [lindex $i_reg [lsearch $entry_map $i_attr]]
                    if {$i_val ne ""} {
                        ig::db::set_attribute -object $reg_id -attribute "rf_${i_attr}" -value $i_val
                    }
                }
            }
        } emsg]} {
            log -error -abort "R (regfile-entry ${entryname}): error while creating regfile-entry:\n${emsg}"
        }

        return $entry_id
    }

    namespace export *
}

# vim: set filetype=icgluetcl syntax=tcl:
