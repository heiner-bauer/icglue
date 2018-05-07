
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

package provide ICGlue 1.0a

namespace eval ig::aux {
    proc max_entry_len {data_list transform_proc} {
        set len 0
        foreach i_entry $data_list {
            set i_len [string length [$transform_proc $i_entry]]
            set len [expr {max ($len, $i_len)}]
        }
        return $len
    }


    proc is_last {lst entry} {
        if {[lindex $lst end] eq $entry} {
            return "true"
        } else {
            return "false"
        }
    }

    proc object_name {obj} {
        return [ig::db::get_attribute -object $obj -attribute "name"]
    }

    proc adapt_codesection {codesection} {
        set do_adapt [ig::db::get_attribute -object $codesection -attribute "adapt" -default "false"]
        set code [ig::db::get_attribute -object $codesection -attribute "code"]
        if {!$do_adapt} {
            return $code
        }

        set parent_mod [ig::db::get_attribute -object $codesection -attribute "parent"]
        set signal_replace [list]
        foreach i_port [ig::db::get_ports -of $parent_mod -all] {
            set i_rep [list \
                [ig::db::get_attribute -object $i_port -attribute "signal"] \
                [ig::db::get_attribute -object $i_port -attribute "name"] \
            ]
            lappend signal_replace $i_rep
        }
        foreach i_decl [ig::db::get_declarations -of $parent_mod -all] {
            set i_rep [list \
                [ig::db::get_attribute -object $i_decl -attribute "signal"] \
                [ig::db::get_attribute -object $i_decl -attribute "name"] \
            ]
            lappend signal_replace $i_rep
        }

        foreach i_rep $signal_replace {
            set i_orig  "\\m[lindex $i_rep 0]\\M"
            set i_subst [lindex $i_rep 1]

            regsub -all $i_orig $code $i_subst code
        }

        return $code
    }
}
